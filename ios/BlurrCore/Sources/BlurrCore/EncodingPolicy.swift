import Foundation

/// Règles de réglage de l'encodage de sortie (portage de `EncodingPolicy.kt`, Android v0.2).
public enum EncodingPolicy {
    public static let minBitrate = 2_000_000
    public static let maxBitrate = 80_000_000

    /// Bits par pixel et par image utilisés quand le débit de la source est inconnu.
    static let fallbackBitsPerPixel = 0.10
    static let audioMarginBitrate = 320_000

    /// Débit vidéo visé pour la sortie : celui de la source pour ne pas perdre en qualité, ou, à défaut, une estimation
    /// fondée sur la définition et la cadence. Le résultat est borné à la plage des encodeurs matériels.
    public static func videoBitrate(width: Int, height: Int, frameRate: Float, sourceBitrate: Int) -> Int {
        let fps = (frameRate >= 1 && frameRate <= 240) ? Double(frameRate) : 30.0
        let estimate = Double(width) * Double(height) * fps * fallbackBitsPerPixel
        let base = sourceBitrate > 0 ? Double(sourceBitrate) : estimate
        return Int(min(max(base, Double(minBitrate)), Double(maxBitrate)))
    }

    /// Taille approximative du fichier de sortie en octets (débit vidéo + marge pour l'audio).
    public static func estimatedOutputBytes(durationUs: Int64, videoBitrate: Int) -> Int64 {
        let seconds = Double(durationUs) / 1_000_000.0
        return Int64(Double(videoBitrate + audioMarginBitrate) / 8.0 * seconds)
    }

    /// Espace disque à exiger avant de démarrer : copie de la source, fichier produit (deux fois, par prudence) et
    /// 50 Mo de marge.
    public static func requiredFreeBytes(durationUs: Int64, videoBitrate: Int) -> Int64 {
        estimatedOutputBytes(durationUs: durationUs, videoBitrate: videoBitrate) * 2 + 50 * 1024 * 1024
    }
}

/// Noms des fichiers produits.
public enum OutputNaming {
    /// "vacances.MOV" donne "vacances_blurr.mp4" ; les caractères interdits dans un nom de fichier sont remplacés.
    /// Portage de `MediaStoreSaver.outputName` (Android v0.2).
    public static func outputName(_ sourceName: String) -> String {
        let afterSlash = sourceName.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? sourceName
        let base: String
        if let dot = afterSlash.lastIndex(of: ".") {
            base = String(afterSlash[afterSlash.startIndex..<dot])
        } else {
            base = afterSlash
        }
        var cleaned = String(String.UnicodeScalarView(base.unicodeScalars.map { scalar -> Unicode.Scalar in
            if "\\/:*?\"<>|".unicodeScalars.contains(scalar) || scalar.properties.generalCategory == .control {
                return "_"
            }
            return scalar
        }))
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        cleaned = String(cleaned.prefix(80))
        if cleaned.isEmpty { cleaned = "video" }
        return "\(cleaned)_blurr.mp4"
    }

    /// Ajoute " (2)", " (3)"... avant l'extension tant que `exists` répond vrai (comme la version PC).
    public static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        if !exists(name) { return name }
        let ext: String
        let stem: String
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            stem = String(name[name.startIndex..<dot])
            ext = String(name[dot...])
        } else {
            stem = name
            ext = ""
        }
        var k = 2
        while true {
            let candidate = "\(stem) (\(k))\(ext)"
            if !exists(candidate) { return candidate }
            k += 1
        }
    }
}
