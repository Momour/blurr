import AVFoundation
import BlurrCore
import CoreMedia

/// Lecture des images décodées, communes aux trois passes.
enum FrameReading {

    /// Images BGRA en BT.709 : AVFoundation convertit les vidéos HDR (HLG, PQ, Dolby Vision) en SDR avec adaptation
    /// des tons, et les vidéos SDR d'autres espaces de couleurs en BT.709.
    static let sdrBGRASettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ]

    static let plainBGRASettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    /// Sortie vidéo BGRA ajoutée à `reader`. Si la conversion de couleurs est refusée, repli sur une sortie BGRA
    /// simple (consigné dans le journal).
    static func addVideoOutput(to reader: AVAssetReader, track: AVAssetTrack, copiesSampleData: Bool) throws -> AVAssetReaderTrackOutput {
        var output: AVAssetReaderTrackOutput?
        do {
            try BLREngineInfo.catchingExceptions {
                output = AVAssetReaderTrackOutput(track: track, outputSettings: sdrBGRASettings)
            }
        } catch {
            AppLog.e("Conversion BT.709 refusée par le lecteur, lecture BGRA simple", error)
            try BLREngineInfo.catchingExceptions {
                output = AVAssetReaderTrackOutput(track: track, outputSettings: plainBGRASettings)
            }
        }
        guard let out = output else { throw BlurrError("Lecture de la piste vidéo impossible.") }
        out.alwaysCopiesSampleData = copiesSampleData
        guard reader.canAdd(out) else { throw BlurrError("Lecture de la piste vidéo impossible (sortie refusée).") }
        reader.add(out)
        return out
    }

    static func start(_ reader: AVAssetReader) throws {
        var started = false
        try BLREngineInfo.catchingExceptions { started = reader.startReading() }
        if !started {
            throw reader.error.map { BlurrError("Lecture de la vidéo impossible : \(AppLog.describe($0))") }
                ?? BlurrError("Lecture de la vidéo impossible.")
        }
    }
}

enum FaceParsing {
    /// [x, y, w, h, score] * n (float32) vers des boîtes.
    static func boxes(from data: Data) -> [FaceBox] {
        let count = data.count / (5 * MemoryLayout<Float>.size)
        if count == 0 { return [] }
        return data.withUnsafeBytes { raw -> [FaceBox] in
            let f = raw.bindMemory(to: Float.self)
            return (0..<count).map { i in
                FaceBox(x: f[i * 5], y: f[i * 5 + 1], w: f[i * 5 + 2], h: f[i * 5 + 3], score: f[i * 5 + 4])
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------- passe 1 : analyse

struct AnalysisResult {
    let detections: Detections
    let frames: Int
    let avgDetectMs: Double
    let analysisSize: String
}

/// Passe 1 : décode toute la vidéo et détecte les visages image par image (équivalent de `Analyzer.kt`).
enum Analyzer {

    static func run(
        info: VideoInfo,
        options: Options,
        modelPath: String,
        cancel: CancelToken,
        progress: @escaping (_ fraction: Double, _ frames: Int, _ msPerFrame: Double) -> Void
    ) async throws -> AnalysisResult {
        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw BlurrError("Piste vidéo introuvable.")
        }
        let detector = try BLRFaceDetector(modelPath: modelPath, scoreThreshold: options.tracking.keepThreshold)
        let reader = try AVAssetReader(asset: asset)
        let output = try FrameReading.addVideoOutput(to: reader, track: track, copiesSampleData: false)
        try FrameReading.start(reader)
        defer { if reader.status == .reading { reader.cancelReading() } }

        let detections = Detections()
        var frames = 0
        var detectNs: UInt64 = 0
        var lastReport = DispatchTime.now().uptimeNanoseconds
        let mirrored = info.orientation.isMirrored
        let rotation = Int32(info.orientation.rotationDegrees)
        let maxSide = Int32(options.analysisMaxSide)

        while true {
            if cancel.isCancelled { throw CancelledError() }
            let more: Bool = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return false }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return true }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let t0 = DispatchTime.now().uptimeNanoseconds
                guard let data = detector.detect(pixelBuffer: pixelBuffer, maxSide: maxSide, mirrored: mirrored, rotation: rotation) else {
                    throw BlurrError(detector.lastError ?? "Détection impossible.")
                }
                let now = DispatchTime.now().uptimeNanoseconds
                detectNs += now - t0
                detections.add(ptsUs: pts.microseconds, faces: FaceParsing.boxes(from: data))
                frames += 1
                if frames == 1 {
                    AppLog.i("Première image : \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) BGRA, analysée en \(detector.lastWidth)x\(detector.lastHeight), \(info.orientation)")
                }
                if now - lastReport >= 250_000_000 {
                    lastReport = now
                    let fraction = info.durationUs > 0 ? min(1, max(0, Double(pts.microseconds) / Double(info.durationUs))) : 0
                    progress(fraction, frames, Double(detectNs) / 1e6 / Double(frames))
                }
                return true
            }
            if !more { break }
        }
        if reader.status == .failed {
            throw BlurrError("Décodage interrompu : \(reader.error.map(AppLog.describe) ?? "erreur inconnue")")
        }
        let avg = frames > 0 ? Double(detectNs) / 1e6 / Double(frames) : 0
        AppLog.i("Analyse terminée : \(frames) images, \(detections.totalFaces) détections, \(String(format: "%.1f", avg)) ms/image")
        return AnalysisResult(detections: detections, frames: frames, avgDetectMs: avg, analysisSize: "\(detector.lastWidth)x\(detector.lastHeight)")
    }
}

// ---------------------------------------------------------------------------------------------- passe 3 : contrôle

struct VerificationResult {
    let sampledFrames: Int
    /// Images où un visage reste détectable hors de toute zone masquée.
    let framesWithFaces: Int
    let faces: Int
    let maxScore: Float
    /// Instants (s) des images signalées, 20 au plus.
    let flaggedTimes: [Double]
    /// Détections situées dans une zone masquée (normal avec le flou), pour le journal.
    let insideMask: Int
    let decodedFrames: Int
}

/// Passe 3 : relit la vidéo PRODUITE et cherche des visages encore détectables HORS des zones masquées (équivalent
/// de `Verifier.kt`). Ce contrôle ne voit pas les visages que le détecteur n'a déjà pas trouvés dans la source.
enum Verifier {

    static func run(
        output url: URL,
        plan: MaskPlan,
        options: Options,
        modelPath: String,
        cancel: CancelToken,
        progress: @escaping (Double) -> Void
    ) async throws -> VerificationResult {
        let info = try await VideoProbe.read(url: url, name: url.lastPathComponent)
        let sampling = Verification.sampling(durationUs: info.durationUs, frameRate: info.frameRate)
        let threshold = Verification.threshold(for: options.tracking)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw BlurrError("Piste vidéo du fichier produit introuvable.")
        }
        // Même résolution d'analyse : les scores sont comparables à ceux qui ont servi au masquage.
        let detector = try BLRFaceDetector(modelPath: modelPath, scoreThreshold: threshold)
        let reader = try AVAssetReader(asset: asset)
        let output = try FrameReading.addVideoOutput(to: reader, track: track, copiesSampleData: false)
        try FrameReading.start(reader)
        defer { if reader.status == .reading { reader.cancelReading() } }

        var decoded = 0
        var sampled = 0
        var withFaces = 0
        var faces = 0
        var maxScore: Float = 0
        var insideMask = 0
        var flagged: [Double] = []
        var shift: Int64? = nil
        var lastReport = DispatchTime.now().uptimeNanoseconds
        let mirrored = info.orientation.isMirrored
        let rotation = Int32(info.orientation.rotationDegrees)
        let maxSide = Int32(options.analysisMaxSide)

        while true {
            if cancel.isCancelled { throw CancelledError() }
            let more: Bool = try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return false }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return true }
                let index = decoded
                decoded += 1
                if index % sampling.stride != 0 { return true }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).microseconds
                if shift == nil { shift = plan.shiftFor(pts) }
                let ellipses = plan.lookupShifted(pts, shift: shift ?? 0)
                guard let data = detector.detect(pixelBuffer: pixelBuffer, maxSide: maxSide, mirrored: mirrored, rotation: rotation) else {
                    throw BlurrError(detector.lastError ?? "Détection impossible.")
                }
                let found = FaceParsing.boxes(from: data)
                let outside = found.filter { !Verification.isInside($0, ellipses) }
                insideMask += found.count - outside.count
                sampled += 1
                if !outside.isEmpty {
                    withFaces += 1
                    faces += outside.count
                    let best = outside.map(\.score).max() ?? 0
                    maxScore = max(maxScore, best)
                    if flagged.count < 20 { flagged.append(Double(pts) / 1_000_000) }
                    AppLog.i("Contrôle : \(outside.count) visage(s) détectable(s) hors masque à \(pts / 1000) ms (score \(String(format: "%.2f", best)))")
                }
                let now = DispatchTime.now().uptimeNanoseconds
                if now - lastReport >= 250_000_000 {
                    lastReport = now
                    progress(info.durationUs > 0 ? min(1, max(0, Double(pts) / Double(info.durationUs))) : 0)
                }
                return true
            }
            if !more { break }
        }
        if reader.status == .failed {
            throw BlurrError("Relecture interrompue : \(reader.error.map(AppLog.describe) ?? "erreur inconnue")")
        }
        AppLog.i(
            "Contrôle terminé : \(sampled) images relues (une sur \(sampling.stride)), seuil \(threshold), \(withFaces) avec visage "
                + "détectable hors masque (\(faces) visages), \(insideMask) détections dans une zone masquée"
        )
        return VerificationResult(
            sampledFrames: sampled, framesWithFaces: withFaces, faces: faces, maxScore: maxScore,
            flaggedTimes: flagged, insideMask: insideMask, decodedFrames: decoded
        )
    }
}
