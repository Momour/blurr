import AVFoundation
import BlurrCore
import CoreMedia

/// Règles d'export propres à iOS.
enum ExportPolicy {
    /// Débit vidéo de sortie : règle commune (`EncodingPolicy`, débit de la source borné à 2-80 Mb/s), multipliée par
    /// 1,5 pour une source HEVC, la sortie étant en H.264, moins efficace à débit égal.
    static func bitrate(for info: VideoInfo) -> Int {
        let base = EncodingPolicy.videoBitrate(
            width: info.displayWidth, height: info.displayHeight, frameRate: info.frameRate, sourceBitrate: info.bitrate
        )
        guard info.isHEVC else { return base }
        return min(EncodingPolicy.maxBitrate, base * 3 / 2)
    }

    /// Formats audio recopiés sans ré-encodage dans le MP4 produit (famille AAC) ; les autres sont ré-encodés en AAC.
    static func canPassthrough(_ fd: CMFormatDescription) -> Bool {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return false }
        return [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD,
                kAudioFormatMPEG4AAC_ELD].contains(asbd.mFormatID)
    }

    static let bt709: [String: Any] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]
}

struct ExportResult {
    let frames: Int
    let maskedFrames: Int
    let drawnEllipses: Int
    let audio: String
    let bitrate: Int
    let firstPtsUs: Int64
    let shiftUs: Int64
}

/// Passe 2 : ré-encode la vidéo en floutant (ou noircissant) les ellipses du plan sur chaque image.
///
/// Lecture par AVAssetReader (BGRA, BT.709), rendu C++ sur l'image codée (les ellipses du plan, exprimées dans
/// l'image affichée, sont converties dans le repère codé), encodage H.264 par AVAssetWriter avec la même
/// transformation d'affichage que la source. Le son est copié sans ré-encodage (AAC) ou ré-encodé en AAC. Aucune
/// métadonnée de la source n'est recopiée (position, date, appareil).
final class Exporter: @unchecked Sendable {

    private let info: VideoInfo
    private let plan: MaskPlan
    private let options: Options
    private let outputURL: URL
    private let cancel: CancelToken
    private let progress: (Double) -> Void

    // État partagé entre les files vidéo et audio (protégé par `lock`).
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var videoDone = false
    private var audioDone = true
    private var finished = false
    private var failure: Error?

    // État de la file vidéo.
    private var pendingVideo: CMSampleBuffer?
    private var frames = 0
    private var lastReport: UInt64 = 0

    init(info: VideoInfo, plan: MaskPlan, options: Options, output: URL, cancel: CancelToken, progress: @escaping (Double) -> Void) {
        self.info = info
        self.plan = plan
        self.options = options
        self.outputURL = output
        self.cancel = cancel
        self.progress = progress
    }

    func run() async throws -> ExportResult {
        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw BlurrError("Piste vidéo introuvable.")
        }
        var audioTrack: AVAssetTrack?
        var audioFormat: CMFormatDescription?
        if options.keepAudio, let track = try await asset.loadTracks(withMediaType: .audio).first {
            audioTrack = track
            audioFormat = try await track.load(.formatDescriptions).first
        }

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []

        // ---- vidéo
        let bitrate = ExportPolicy.bitrate(for: info)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: true,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if info.frameRate >= 1 && info.frameRate <= 240 {
            compression[AVVideoExpectedSourceFrameRateKey] = Int(info.frameRate.rounded())
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: info.codedWidth,
            AVVideoHeightKey: info.codedHeight,
            AVVideoColorPropertiesKey: ExportPolicy.bt709,
            AVVideoCompressionPropertiesKey: compression,
        ]
        var videoInput: AVAssetWriterInput?
        try BLREngineInfo.catchingExceptions {
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        }
        guard let videoIn = videoInput else { throw BlurrError("Encodeur vidéo indisponible.") }
        videoIn.expectsMediaDataInRealTime = false
        videoIn.transform = info.transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoIn) else { throw BlurrError("Encodeur vidéo refusé par le fichier MP4.") }
        writer.add(videoIn)

        // ---- son : copie sans ré-encodage si possible, sinon AAC, sinon rien (consigné)
        var audioIn: AVAssetWriterInput?
        var audioReaderSettings: [String: Any]?
        var audioLabel = audioTrack == nil ? (info.hasAudio ? "coupé" : "aucun") : ""
        if let fd = audioFormat {
            if ExportPolicy.canPassthrough(fd) {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fd)
                if writer.canAdd(input) {
                    audioIn = input
                    audioLabel = "copié sans ré-encodage"
                }
            }
            if audioIn == nil {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee
                let channels = min(2, max(1, Int(asbd?.mChannelsPerFrame ?? 2)))
                let rate = min(48_000.0, max(8_000.0, asbd?.mSampleRate ?? 44_100))
                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
                let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
                let aacSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: rate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: channels == 1 ? 96_000 : 192_000,
                    AVChannelLayoutKey: layoutData,
                ]
                var input: AVAssetWriterInput?
                do {
                    try BLREngineInfo.catchingExceptions {
                        input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
                    }
                } catch {
                    AppLog.e("Encodeur AAC indisponible", error)
                }
                if let input, writer.canAdd(input) {
                    audioIn = input
                    audioReaderSettings = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: rate,
                        AVNumberOfChannelsKey: channels,
                        AVChannelLayoutKey: layoutData,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                    ]
                    audioLabel = "ré-encodé en AAC \(channels == 1 ? "mono" : "stéréo") 192 kb/s"
                    if channels == 1 { audioLabel = "ré-encodé en AAC mono 96 kb/s" }
                } else {
                    audioLabel = "non recopié (format non pris en charge)"
                }
            }
            if let audioIn { writer.add(audioIn) }
        }

        // ---- lecture
        let reader = try AVAssetReader(asset: asset)
        let videoOut = try FrameReading.addVideoOutput(to: reader, track: videoTrack, copiesSampleData: true)
        var audioOut: AVAssetReaderTrackOutput?
        if let track = audioTrack, audioIn != nil {
            var out: AVAssetReaderTrackOutput?
            try BLREngineInfo.catchingExceptions {
                out = AVAssetReaderTrackOutput(track: track, outputSettings: audioReaderSettings)
            }
            if let out, reader.canAdd(out) {
                out.alwaysCopiesSampleData = false
                reader.add(out)
                audioOut = out
            } else {
                throw BlurrError("Lecture de la piste audio impossible.")
            }
        }

        var startedWriting = false
        try BLREngineInfo.catchingExceptions { startedWriting = writer.startWriting() }
        guard startedWriting else {
            throw BlurrError("Démarrage de l'encodage impossible : \(writer.error.map(AppLog.describe) ?? "erreur inconnue")")
        }
        do {
            try FrameReading.start(reader)
        } catch {
            writer.cancelWriting()
            throw error
        }

        // Première image : définit le début de la session (horodatages d'origine conservés) et cale le plan.
        pendingVideo = videoOut.copyNextSampleBuffer()
        let firstPts = pendingVideo.map { CMSampleBufferGetPresentationTimeStamp($0) } ?? .zero
        let sessionStart = CMTimeCompare(firstPts, .zero) < 0 ? firstPts : .zero
        writer.startSession(atSourceTime: sessionStart)
        let shift = plan.alignTo(firstPts.microseconds)
        AppLog.i("Export : première image à \(firstPts.microseconds) us, décalage appliqué \(shift) us, débit visé \(bitrate / 1000) kb/s, rendu \(options.style.label), son \(audioLabel)")

        let renderer = BLRMaskRenderer(width: Int32(info.codedWidth), height: Int32(info.codedHeight), black: options.style == .black)
        lastReport = DispatchTime.now().uptimeNanoseconds

        // ---- écriture entrelacée : chaque entrée demande des données quand elle peut en recevoir
        audioDone = audioIn == nil
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            continuation = cont
            lock.unlock()

            let videoQueue = DispatchQueue(label: "blurr.export.video", qos: .userInitiated)
            videoIn.requestMediaDataWhenReady(on: videoQueue) { [self] in
                self.feedVideo(input: videoIn, output: videoOut, adaptor: adaptor, renderer: renderer, writer: writer, reader: reader)
            }
            if let audioIn, let audioOut {
                let audioQueue = DispatchQueue(label: "blurr.export.audio", qos: .userInitiated)
                audioIn.requestMediaDataWhenReady(on: audioQueue) { [self] in
                    self.feedAudio(input: audioIn, output: audioOut, writer: writer, reader: reader)
                }
            }
        }

        let error = currentFailure()
        if cancel.isCancelled || error != nil {
            writer.cancelWriting()
            reader.cancelReading()
            try? FileManager.default.removeItem(at: outputURL)
            if cancel.isCancelled { throw CancelledError() }
            throw error ?? BlurrError("Export interrompu.")
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw BlurrError("Décodage interrompu : \(reader.error.map(AppLog.describe) ?? "erreur inconnue")")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw BlurrError("Finalisation du fichier impossible : \(writer.error.map(AppLog.describe) ?? "erreur inconnue")")
        }
        AppLog.i("Export terminé : \(renderer.frames) images rendues, \(renderer.maskedFrames) avec au moins un masque, \(renderer.drawnEllipses) ellipses dessinées")
        return ExportResult(
            frames: frames, maskedFrames: renderer.maskedFrames, drawnEllipses: renderer.drawnEllipses,
            audio: audioLabel, bitrate: bitrate, firstPtsUs: firstPts.microseconds, shiftUs: shift
        )
    }

    // ------------------------------------------------------------------------------------------ files d'écriture

    private func feedVideo(
        input: AVAssetWriterInput, output: AVAssetReaderTrackOutput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
        renderer: BLRMaskRenderer, writer: AVAssetWriter, reader: AVAssetReader
    ) {
        while input.isReadyForMoreMediaData {
            if isFinished() { return }
            if cancel.isCancelled {
                fail(CancelledError())
                return
            }
            let keepGoing: Bool = autoreleasepool {
                let next = pendingVideo ?? output.copyNextSampleBuffer()
                pendingVideo = nil
                guard let sample = next else {
                    input.markAsFinished()
                    markVideoDone()
                    return false
                }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return true }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let display = plan.lookup(pts.microseconds)
                let coded = info.orientation.toCoded(display, codedWidth: info.codedWidth, codedHeight: info.codedHeight)
                let drawn = coded.withUnsafeBufferPointer { buffer in
                    renderer.apply(pixelBuffer: pixelBuffer, ellipses: buffer.baseAddress, count: Int32(coded.count / 4))
                }
                if drawn < 0 {
                    fail(BlurrError(renderer.lastError ?? "Rendu impossible."))
                    return false
                }
                if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                    let detail = writer.error.map(AppLog.describe) ?? "erreur inconnue"
                    fail(BlurrError("Encodage de l'image \(frames + 1) impossible : \(detail)"))
                    return false
                }
                frames += 1
                let now = DispatchTime.now().uptimeNanoseconds
                if now - lastReport >= 250_000_000 {
                    lastReport = now
                    progress(info.durationUs > 0 ? min(1, max(0, Double(pts.microseconds) / Double(info.durationUs))) : 0)
                }
                return true
            }
            if !keepGoing { return }
        }
    }

    private func feedAudio(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput, writer: AVAssetWriter, reader: AVAssetReader) {
        while input.isReadyForMoreMediaData {
            if isFinished() || cancel.isCancelled { return }
            let keepGoing: Bool = autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    markAudioDone()
                    return false
                }
                if !input.append(sample) {
                    let detail = writer.error.map(AppLog.describe) ?? "erreur inconnue"
                    fail(BlurrError("Écriture du son impossible : \(detail)"))
                    return false
                }
                return true
            }
            if !keepGoing { return }
        }
    }

    // ------------------------------------------------------------------------------------------ coordination

    private func isFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func currentFailure() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private func markVideoDone() {
        lock.lock()
        videoDone = true
        let resume = videoDone && audioDone && !finished
        if resume { finished = true }
        let cont = resume ? continuation : nil
        if resume { continuation = nil }
        lock.unlock()
        cont?.resume()
    }

    private func markAudioDone() {
        lock.lock()
        audioDone = true
        let resume = videoDone && audioDone && !finished
        if resume { finished = true }
        let cont = resume ? continuation : nil
        if resume { continuation = nil }
        lock.unlock()
        cont?.resume()
    }

    /// Erreur ou annulation : termine l'attente une seule fois (les entrées cessent d'être alimentées).
    private func fail(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        let cont = finished ? nil : continuation
        finished = true
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
