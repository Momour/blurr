import Foundation

/// Boîte de visage en coordonnées normalisées [0, 1], origine en haut à gauche, dans le repère d'affichage
/// (image redressée). Indépendante de la résolution d'analyse. Portage de `Model.kt` (Android v0.2).
public struct FaceBox: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float
    public var score: Float

    public init(x: Float, y: Float, w: Float, h: Float, score: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.score = score
    }
}

/// Détections brutes, image par image, dans l'ordre où elles ont été ajoutées (ordre de présentation en pratique).
public final class Detections {
    private var times: [Int64] = []
    private var perFrame: [[FaceBox]] = []

    public init() {}

    public var size: Int { times.count }

    public func add(ptsUs: Int64, faces: [FaceBox]) {
        times.append(ptsUs)
        perFrame.append(faces)
    }

    public func ptsUs(_ i: Int) -> Int64 { times[i] }
    public func faces(_ i: Int) -> [FaceBox] { perFrame[i] }

    public func clear() {
        times.removeAll()
        perFrame.removeAll()
    }

    public var totalFaces: Int { perFrame.reduce(0) { $0 + $1.count } }
    public var framesWithFaces: Int { perFrame.reduce(0) { $0 + ($1.isEmpty ? 0 : 1) } }
}

/// Rendu appliqué aux zones à masquer.
public enum MaskStyle: String, CaseIterable, Sendable {
    /// Flou fort, proportionnel à la taille du visage (défaut).
    case blur
    /// Ellipse noire opaque : protection la plus sûre (aucune information du visage ne subsiste).
    case black

    public var label: String {
        switch self {
        case .blur: return "Flou"
        case .black: return "Masque noir"
        }
    }
}

/// Filtrage temporel des détections (voir `MaskPlan`) :
///  - le détecteur garde toute détection de score >= `keepThreshold` ;
///  - les détections sont reliées d'une image à l'autre en pistes ;
///  - une piste n'est masquée que si l'une de ses détections atteint `confirmThreshold` et si elle compte au moins
///    `minHits` détections.
public struct TrackingParams: Equatable, Sendable {
    public var keepThreshold: Float
    public var confirmThreshold: Float
    public var minHits: Int
    /// Trou maximal (sans détection) comblé par interpolation à l'intérieur d'une piste.
    public var maxGapUs: Int64

    public init(keepThreshold: Float, confirmThreshold: Float, minHits: Int, maxGapUs: Int64 = 300_000) {
        self.keepThreshold = keepThreshold
        self.confirmThreshold = confirmThreshold
        self.minHits = minHits
        self.maxGapUs = maxGapUs
    }
}

/// Préréglages de sensibilité, identiques à Android v0.2 et à la version PC. Valeurs choisies sur une seule vidéo
/// de test (retransmission de football, 1080p 60 i/s) : elles ne sont pas mesurées sur le jeu de test de l'étape 1.
public enum Sensitivity: String, CaseIterable, Sendable {
    case normal
    case high
    case max

    public var params: TrackingParams {
        switch self {
        case .normal: return TrackingParams(keepThreshold: 0.5, confirmThreshold: 0.85, minHits: 2)
        case .high: return TrackingParams(keepThreshold: 0.4, confirmThreshold: 0.7, minHits: 2)
        case .max: return TrackingParams(keepThreshold: 0.3, confirmThreshold: 0.5, minHits: 1)
        }
    }

    public var label: String {
        switch self {
        case .normal: return "Normale"
        case .high: return "Élevée"
        case .max: return "Maximale"
        }
    }

    public var help: String {
        switch self {
        case .normal: return "Moins de faux masques ; les visages de moins de ~20 px restent souvent visibles."
        case .high: return "Compromis entre visages manqués et faux masques."
        case .max: return "Moins de visages manqués, davantage de faux masques."
        }
    }
}

/// Plus grand côté de l'image envoyée au détecteur : rapide, standard (défaut), précis.
public let analysisSizes: [Int] = [960, 1280, 1920]

/// Réglages d'un traitement.
public struct Options: Equatable, Sendable {
    /// Plus grand côté de l'image envoyée au détecteur, en pixels.
    public var analysisMaxSide: Int
    public var sensitivity: Sensitivity
    public var style: MaskStyle
    /// Agrandissement de la boîte détectée (l'ellipse inscrite dans une boîte 1,6x couvre 100 % de la boîte).
    public var maskScale: Float
    /// Chaque piste est prolongée de ce nombre d'images avant sa première et après sa dernière détection.
    public var marginFrames: Int
    /// La boîte d'une piste sur une image couvre aussi ses boîtes des images voisines.
    public var unionFrames: Int
    /// Recopier le son de la source.
    public var keepAudio: Bool

    public init(
        analysisMaxSide: Int = 1280,
        sensitivity: Sensitivity = .high,
        style: MaskStyle = .blur,
        maskScale: Float = 1.6,
        marginFrames: Int = 5,
        unionFrames: Int = 1,
        keepAudio: Bool = true
    ) {
        self.analysisMaxSide = analysisMaxSide
        self.sensitivity = sensitivity
        self.style = style
        self.maskScale = maskScale
        self.marginFrames = marginFrames
        self.unionFrames = unionFrames
        self.keepAudio = keepAudio
    }

    public var tracking: TrackingParams { sensitivity.params }

    public func describe() -> String {
        let t = tracking
        return "analyse \(analysisMaxSide) px, sensibilité \(sensitivity.label) (seuil \(t.keepThreshold), "
            + "confirmation \(t.confirmThreshold), \(t.minHits) détection(s) min.), rendu \(style.label), "
            + "masque x\(maskScale), marge \(marginFrames) images, son \(keepAudio ? "conservé" : "coupé")"
    }
}

/// Taille de l'image analysée : plus grand côté ramené à `maxSide` pixels au plus, arrondi au plus proche
/// (demi vers le haut, comme `roundToInt` de Kotlin), 2 pixels au minimum. Identique à Android et à la version PC.
public func analysisSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
    let longSide = max(width, height)
    if longSide <= maxSide || longSide <= 0 { return (width, height) }
    let scale = Double(maxSide) / Double(longSide)
    let w = Int((Double(width) * scale + 0.5).rounded(.down))
    let h = Int((Double(height) * scale + 0.5).rounded(.down))
    return (max(2, w), max(2, h))
}
