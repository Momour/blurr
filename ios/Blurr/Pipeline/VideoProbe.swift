import AVFoundation
import BlurrCore
import CoreMedia

/// Métadonnées utiles d'une vidéo, lues avant tout traitement (équivalent de `VideoProbe.kt`, Android v0.2).
struct VideoInfo {
    let url: URL
    let name: String
    /// Dimensions de l'image codée (avant redressement).
    let codedWidth: Int
    let codedHeight: Int
    /// Transformation d'affichage de la piste (`preferredTransform`), recopiée telle quelle dans le fichier produit.
    let transform: CGAffineTransform
    let orientation: DisplayOrientation
    /// Vrai si la transformation n'est ni un quart de tour ni une symétrie (traitée comme l'identité).
    let orientationApproximated: Bool
    let durationUs: Int64
    /// Cadence annoncée, 0 si inconnue.
    let frameRate: Float
    /// Débit annoncé en bits par seconde, 0 si inconnu.
    let bitrate: Int
    /// Code du format vidéo (FourCC), par exemple "hvc1".
    let codec: String
    let isHDR: Bool
    let hasAudio: Bool
    let audioDescription: String

    var displayWidth: Int { orientation.displaySize(codedWidth: codedWidth, codedHeight: codedHeight).width }
    var displayHeight: Int { orientation.displaySize(codedWidth: codedWidth, codedHeight: codedHeight).height }

    var codecLabel: String {
        switch codec {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "dvh1", "dvhe": return "HEVC Dolby Vision"
        case "ap4h", "ap4x", "apch", "apcn", "apcs", "apco": return "ProRes"
        case "mp4v": return "MPEG-4"
        default: return codec.isEmpty ? "format inconnu" : codec
        }
    }

    var isHEVC: Bool { ["hvc1", "hev1", "dvh1", "dvhe"].contains(codec) }

    /// Résumé affiché sous le bouton de choix.
    var summary: String {
        let fps = frameRate > 0 ? String(format: "%.0f i/s", frameRate) : "cadence inconnue"
        let rate = bitrate > 0 ? String(format: "%.1f Mb/s", Double(bitrate) / 1_000_000) : "débit inconnu"
        var lines = [
            name,
            "\(displayWidth) x \(displayHeight), \(codecLabel), \(fps), \(VideoInfo.formatDuration(durationUs)), \(rate)",
            hasAudio ? "Son : \(audioDescription)" : "Son : aucun",
        ]
        if isHDR { lines.append("HDR : sera converti en SDR") }
        return lines.joined(separator: "\n")
    }

    /// Description technique pour le journal (aucune donnée personnelle, aucune position).
    var logLine: String {
        "Vidéo : \(codec) \(codedWidth)x\(codedHeight), \(orientation)\(orientationApproximated ? " (transformation non standard ignorée)" : ""), "
            + "\(frameRate) i/s annoncées, \(durationUs / 1000) ms, \(bitrate) b/s, HDR=\(isHDR), son=\(hasAudio ? audioDescription : "aucun")"
    }

    static func formatDuration(_ us: Int64) -> String {
        let total = Int(us / 1_000_000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension CMTime {
    /// Horodatage en microsecondes (0 si invalide).
    var microseconds: Int64 {
        guard isValid, !isIndefinite, timescale > 0 else { return 0 }
        return Int64((Double(value) * 1_000_000.0 / Double(timescale)).rounded())
    }
}

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
    let text = String(bytes: bytes, encoding: .ascii) ?? ""
    return text.trimmingCharacters(in: .whitespaces.union(.controlCharacters))
}

enum VideoProbe {

    static func read(url: URL, name: String) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw BlurrError("Ce fichier ne contient pas de piste vidéo.")
        }
        let (naturalSize, transform, nominalFrameRate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let (dataRate, descriptions, characteristics) = try await track.load(.estimatedDataRate, .formatDescriptions, .mediaCharacteristics)
        var duration = try await track.load(.timeRange).duration
        if !duration.isValid || duration.seconds <= 0 {
            duration = try await asset.load(.duration)
        }

        var codec = ""
        var hdr = characteristics.contains(.containsHDRVideo)
        if let fd = descriptions.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(fd))
            if let transfer = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
                let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                if transfer == hlg || transfer == pq { hdr = true }
            }
        }

        let orientation = DisplayOrientation(
            transformA: Double(transform.a), b: Double(transform.b), c: Double(transform.c), d: Double(transform.d)
        )

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioDescription = "aucun"
        if let audio = audioTracks.first {
            let audioFormats = try await audio.load(.formatDescriptions)
            audioDescription = describeAudio(audioFormats.first)
            if audioTracks.count > 1 { audioDescription += " (première piste sur \(audioTracks.count))" }
        }

        return VideoInfo(
            url: url,
            name: name,
            codedWidth: Int(naturalSize.width.rounded()),
            codedHeight: Int(naturalSize.height.rounded()),
            transform: transform,
            orientation: orientation ?? .identity,
            orientationApproximated: orientation == nil,
            durationUs: duration.microseconds,
            frameRate: nominalFrameRate,
            bitrate: Int(dataRate.rounded()),
            codec: codec,
            isHDR: hdr,
            hasAudio: !audioTracks.isEmpty,
            audioDescription: audioDescription
        )
    }

    static func describeAudio(_ fd: CMFormatDescription?) -> String {
        guard let fd, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return "format inconnu" }
        let format: String
        switch asbd.mFormatID {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD:
            format = "AAC"
        case kAudioFormatLinearPCM: format = "PCM"
        case kAudioFormatAppleLossless: format = "ALAC"
        case kAudioFormatAC3: format = "AC-3"
        case kAudioFormatEnhancedAC3: format = "E-AC-3"
        case kAudioFormatOpus: format = "Opus"
        default: format = fourCC(asbd.mFormatID)
        }
        return "\(format), \(Int(asbd.mSampleRate)) Hz, \(asbd.mChannelsPerFrame) canal(aux)"
    }
}
