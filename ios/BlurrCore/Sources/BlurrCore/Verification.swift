import Foundation

/// Règles du contrôle du fichier produit (portage de `Verifier.kt`, Android v0.2).
///
/// Un visage flouté peut rester détectable (le détecteur reconnaît parfois une tache de la forme d'un visage) : les
/// détections situées dans une ellipse du plan sont donc ignorées. Une détection hors de toute ellipse, avec un score
/// au moins égal au seuil de confirmation des pistes, signale une erreur du traitement (masques décalés dans le temps,
/// mal placés ou absents) ou un visage non confirmé à l'analyse.
public enum Verification {
    /// Seuil minimal : on ne signale que des visages nets. Le seuil effectif est au moins celui de confirmation.
    public static let scoreThreshold: Float = 0.6
    public static let maxSamples = 600

    public static func threshold(for params: TrackingParams) -> Float {
        max(scoreThreshold, params.confirmThreshold)
    }

    /// Nombre d'images estimé et pas d'échantillonnage (une image sur `stride`, 600 images relues au plus).
    public static func sampling(durationUs: Int64, frameRate: Float) -> (estimate: Int, stride: Int) {
        let fps = (frameRate >= 1 && frameRate <= 240) ? frameRate : 30
        let estimate = max(1, Int(Double(durationUs) / 1_000_000.0 * Double(fps)))
        return (estimate, max(1, estimate / maxSamples))
    }

    /// Le centre de la boîte est-il dans l'une des ellipses [cx, cy, rx, ry, ...] ?
    public static func isInside(_ box: FaceBox, _ ellipses: [Float]) -> Bool {
        let x = box.x + box.w / 2
        let y = box.y + box.h / 2
        var i = 0
        while i + 3 < ellipses.count {
            let dx = (x - ellipses[i]) / ellipses[i + 2]
            let dy = (y - ellipses[i + 1]) / ellipses[i + 3]
            if dx * dx + dy * dy <= 1 { return true }
            i += 4
        }
        return false
    }
}

/// Bilan d'un traitement, affiché sur l'écran de fin (portage du texte de fin d'Android v0.2).
public struct ProcessingReport: Sendable {
    public var analyzedFrames: Int
    public var framesWithFaces: Int
    public var detections: Int
    public var plan: MaskPlan.Stats
    public var exportedFrames: Int
    /// Nil si le contrôle n'a pas été effectué.
    public var verifiedFrames: Int?
    public var flaggedFrames: Int
    /// Instants (en secondes) des images signalées par le contrôle, 20 au plus.
    public var flaggedTimes: [Double]
    public var audio: String
    public var hdrConverted: Bool

    public init(
        analyzedFrames: Int, framesWithFaces: Int, detections: Int, plan: MaskPlan.Stats, exportedFrames: Int,
        verifiedFrames: Int?, flaggedFrames: Int, flaggedTimes: [Double], audio: String, hdrConverted: Bool
    ) {
        self.analyzedFrames = analyzedFrames
        self.framesWithFaces = framesWithFaces
        self.detections = detections
        self.plan = plan
        self.exportedFrames = exportedFrames
        self.verifiedFrames = verifiedFrames
        self.flaggedFrames = flaggedFrames
        self.flaggedTimes = flaggedTimes
        self.audio = audio
        self.hdrConverted = hdrConverted
    }

    /// Une vidéo à regarder de près : aucun masque, visage signalé par le contrôle ou écart d'images.
    public var needsAttention: Bool {
        plan.confirmedTracks == 0 || flaggedFrames > 0 || frameMismatch
    }

    public var frameMismatch: Bool {
        let tolerance = max(2, analyzedFrames / 50)
        return exportedFrames > 0 && abs(exportedFrames - analyzedFrames) > tolerance
    }

    public static func percent(_ part: Int, _ total: Int) -> String {
        guard total > 0 else { return "0" }
        return String(format: "%.0f", 100.0 * Double(part) / Double(total))
    }

    public static func clock(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = total - Double(m * 60)
        return String(format: "%d:%06.3f", m, s)
    }

    /// Lignes du bilan, en français.
    public func lines() -> [String] {
        var out: [String] = []
        out.append(
            "Détections brutes sur \(framesWithFaces) images sur \(analyzedFrames) (\(ProcessingReport.percent(framesWithFaces, analyzedFrames)) %). "
                + "\(plan.confirmedTracks) piste(s) de visage masquée(s), \(plan.rejectedTracks) piste(s) non confirmée(s) écartée(s) "
                + "(faux positifs probables). Images masquées : \(ProcessingReport.percent(plan.maskedFrames, analyzedFrames)) %."
        )
        if plan.confirmedTracks == 0 {
            out.append("ATTENTION : aucun visage confirmé, la vidéo n'a reçu aucun masque. Essayez la sensibilité maximale.")
        }
        if frameMismatch {
            out.append("Note : \(analyzedFrames) images analysées contre \(exportedFrames) exportées. Si les masques semblent décalés dans le temps, signalez-le avec le journal.")
        }
        if let verified = verifiedFrames {
            if flaggedFrames == 0 {
                out.append("Contrôle automatique : \(verified) images de la vidéo produite relues, aucun visage détectable hors des zones masquées.")
            } else {
                var line = "ATTENTION, contrôle automatique : un visage reste détectable hors des zones masquées sur \(flaggedFrames) des \(verified) images relues."
                if !flaggedTimes.isEmpty {
                    line += " Instants : " + flaggedTimes.map { ProcessingReport.clock($0) }.joined(separator: ", ") + "."
                }
                line += " Regardez attentivement ces passages."
                out.append(line)
            }
        } else {
            out.append("Contrôle automatique du résultat : non effectué.")
        }
        out.append("Son : \(audio).")
        if hdrConverted {
            out.append("Vidéo HDR convertie en SDR.")
        }
        out.append("Les coordonnées GPS et les métadonnées de la source ne sont pas recopiées.")
        out.append("Regardez la vidéo en entier avant de la diffuser : aucun détecteur ne trouve 100 % des visages (profils, petits visages, flou, contre-jour).")
        return out
    }
}
