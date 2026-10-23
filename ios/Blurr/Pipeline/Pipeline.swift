import AVFoundation
import BlurrCore
import Photos
import UIKit

/// Étape en cours, pour l'interface.
enum Stage: Equatable {
    case analysis
    case export
    case verification
    case finishing

    var label: String {
        switch self {
        case .analysis: return "Étape 1/3 : détection des visages"
        case .export: return "Étape 2/3 : export de la vidéo"
        case .verification: return "Étape 3/3 : contrôle du résultat"
        case .finishing: return "Enregistrement"
        }
    }
}

struct PipelineOutput {
    let url: URL
    let fileName: String
    let bytes: Int64
    let report: ProcessingReport
    let seconds: Double
}

/// Enchaîne les trois passes (analyse, export, contrôle) puis range le fichier produit.
enum Pipeline {

    static var modelPath: String {
        Bundle.main.path(forResource: "face_detection_yunet_2023mar", ofType: "onnx") ?? ""
    }

    /// Dossier des vidéos produites, visible dans l'app Fichiers (Sur mon iPhone > blurr).
    static var outputDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func process(
        info: VideoInfo,
        options: Options,
        verify: Bool,
        outputDirectory: URL = Pipeline.outputDirectory,
        cancel: CancelToken,
        progress: @escaping (Stage, Double, String?) -> Void
    ) async throws -> PipelineOutput {
        let started = Date()
        guard info.codedWidth > 0, info.codedHeight > 0 else { throw BlurrError("Dimensions de la vidéo inconnues.") }
        let model = modelPath
        guard FileManager.default.fileExists(atPath: model) else {
            throw BlurrError("Modèle de détection absent de l'application (face_detection_yunet_2023mar.onnx).")
        }
        let bitrate = ExportPolicy.bitrate(for: info)
        let needed = EncodingPolicy.requiredFreeBytes(durationUs: info.durationUs, videoBitrate: bitrate)
        if let free = freeBytes(), free < needed {
            let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let n = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            throw BlurrError("Espace insuffisant : environ \(n) nécessaires, \(f) libres.")
        }
        let t = options.tracking
        AppLog.i("--- Traitement : \(options.describe()), contrôle \(verify ? "oui" : "non") ; seuils \(t.keepThreshold)/\(t.confirmThreshold), OpenCV \(BLREngineInfo.openCVVersion())")

        // Passe 1 : analyse.
        progress(.analysis, 0, nil)
        let analysis = try await Analyzer.run(info: info, options: options, modelPath: model, cancel: cancel) { fraction, frames, ms in
            progress(.analysis, fraction, "\(frames) images, \(String(format: "%.0f", ms)) ms par image")
        }
        if analysis.frames == 0 { throw BlurrError("Aucune image n'a pu être décodée. Consultez le journal.") }
        try cancel.check()
        let aspect = Float(info.displayWidth) / Float(max(1, info.displayHeight))
        let plan = MaskPlan.build(
            detections: analysis.detections, params: options.tracking, maskScale: options.maskScale,
            marginFrames: options.marginFrames, aspect: aspect, unionFrames: options.unionFrames
        )
        AppLog.i(
            "Plan de masquage : \(plan.frameCount) images, \(analysis.detections.framesWithFaces) avec détection, "
                + "\(analysis.detections.totalFaces) détections, \(plan.stats.tracks) pistes dont \(plan.stats.confirmedTracks) masquées, "
                + "\(plan.stats.maskedFrames) images masquées"
        )

        // Passe 2 : export dans un fichier temporaire, rangé seulement à la fin (aucun fichier partiel visible).
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("blurr-\(UUID().uuidString).mp4")
        progress(.export, 0, nil)
        let export: ExportResult
        do {
            export = try await Exporter(info: info, plan: plan, options: options, output: temp, cancel: cancel) { fraction in
                progress(.export, fraction, nil)
            }.run()
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }

        // Passe 3 : contrôle. Une panne ici ne doit jamais empêcher de récupérer la vidéo.
        var check: VerificationResult?
        if verify {
            progress(.verification, 0, nil)
            do {
                check = try await Verifier.run(output: temp, plan: plan, options: options, modelPath: model, cancel: cancel) { fraction in
                    progress(.verification, fraction, nil)
                }
            } catch is CancelledError {
                try? FileManager.default.removeItem(at: temp)
                throw CancelledError()
            } catch {
                AppLog.e("Contrôle du résultat impossible", error)
            }
        }
        if cancel.isCancelled {
            try? FileManager.default.removeItem(at: temp)
            throw CancelledError()
        }

        progress(.finishing, 1, nil)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let wanted = OutputNaming.outputName(info.name)
        let name = OutputNaming.uniqueName(wanted) { candidate in
            FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent(candidate).path)
        }
        let final = outputDirectory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temp, to: final)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? NSNumber)?.int64Value ?? 0

        let report = ProcessingReport(
            analyzedFrames: analysis.frames,
            framesWithFaces: analysis.detections.framesWithFaces,
            detections: analysis.detections.totalFaces,
            plan: plan.stats,
            exportedFrames: export.frames,
            verifiedFrames: check?.sampledFrames,
            flaggedFrames: check?.framesWithFaces ?? 0,
            flaggedTimes: check?.flaggedTimes ?? [],
            audio: export.audio,
            hdrConverted: info.isHDR
        )
        let seconds = Date().timeIntervalSince(started)
        AppLog.i("Terminé : \(name), \(bytes) octets, \(String(format: "%.1f", seconds)) s")
        return PipelineOutput(url: final, fileName: name, bytes: bytes, report: report, seconds: seconds)
    }
}

/// Copie des vidéos choisies dans un dossier temporaire de l'application (les sélecteurs ne donnent qu'un accès
/// provisoire au fichier).
enum ImportStore {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("import", isDirectory: true)
    }

    /// Supprime les copies précédentes (une seule vidéo à la fois).
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func copy(_ source: URL, preferredName: String? = nil) throws -> URL {
        clear()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = preferredName ?? source.lastPathComponent
        if name.isEmpty { name = "video.mov" }
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

/// Enregistrement dans la photothèque (autorisation « ajout uniquement »).
enum PhotoSaver {
    static func save(_ url: URL, fileName: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw BlurrError("Accès à la photothèque refusé. Autorisez blurr dans Réglages > blurr > Photos, ou utilisez « Partager ».")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileName
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
        AppLog.i("Enregistré dans la photothèque : \(fileName)")
    }
}

/// En-tête du journal : appareil et système, sans donnée personnelle.
enum DeviceInfo {
    static var header: String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "blurr \(version) (\(build)) | \(machine) | \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) | OpenCV \(BLREngineInfo.openCVVersion())"
    }
}
