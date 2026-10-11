package app.blurr

/** Métadonnées utiles d'une vidéo, lues avant tout traitement. */
data class VideoInfo(
    val name: String,
    val mime: String,
    val codedWidth: Int,
    val codedHeight: Int,
    /** Rotation horaire (0, 90, 180 ou 270) à appliquer aux images décodées pour les afficher debout. */
    val rotation: Int,
    val durationUs: Long,
    /** Cadence annoncée, 0 si inconnue. */
    val frameRate: Float,
    /** Débit annoncé en bits par seconde, 0 si inconnu. */
    val bitrate: Int,
    val isHdr: Boolean,
    /** Le fichier contient au moins une piste audio (sinon l'export ne doit pas fabriquer de piste muette). */
    val hasAudio: Boolean,
) {
    val displayWidth: Int get() = if (rotation % 180 == 0) codedWidth else codedHeight
    val displayHeight: Int get() = if (rotation % 180 == 0) codedHeight else codedWidth
}

/**
 * Boîte de visage en coordonnées normalisées [0, 1], origine en haut à gauche,
 * dans le repère d'affichage (image redressée). Indépendante de la résolution d'analyse.
 */
data class FaceBox(val x: Float, val y: Float, val w: Float, val h: Float, val score: Float)

/** Détections brutes, image par image, dans l'ordre de présentation. */
class Detections {
    private val times = ArrayList<Long>()
    private val perFrame = ArrayList<List<FaceBox>>()

    val size: Int get() = times.size
    fun add(ptsUs: Long, faces: List<FaceBox>) {
        times.add(ptsUs)
        perFrame.add(faces)
    }

    fun ptsUs(i: Int): Long = times[i]
    fun faces(i: Int): List<FaceBox> = perFrame[i]
    fun clear() {
        times.clear()
        perFrame.clear()
    }

    val totalFaces: Int get() = perFrame.sumOf { it.size }
    val framesWithFaces: Int get() = perFrame.count { it.isNotEmpty() }
}

/** Rendu appliqué aux zones à masquer. */
enum class MaskStyle {
    /** Flou fort, proportionnel à la taille du visage (défaut). */
    BLUR,

    /** Ellipse noire opaque : protection la plus sûre (aucune information du visage ne subsiste). */
    BLACK,
}

/**
 * Filtrage temporel des détections (voir [MaskPlan]) :
 *  - le détecteur garde toute détection de score >= [keepThreshold] ;
 *  - les détections sont reliées d'une image à l'autre en pistes ;
 *  - une piste n'est masquée que si l'une de ses détections atteint [confirmThreshold] et si elle compte au moins
 *    [minHits] détections. Une détection isolée de score moyen (faux positif typique) n'est donc jamais masquée,
 *    tandis qu'un visage confirmé reste masqué sur les images où son score retombe (profil, flou de bougé).
 */
data class TrackingParams(
    val keepThreshold: Float,
    val confirmThreshold: Float,
    val minHits: Int,
    /** Trou maximal (sans détection) comblé par interpolation à l'intérieur d'une piste. */
    val maxGapUs: Long = 300_000L,
)

/**
 * Préréglages de sensibilité. Valeurs choisies sur une seule vidéo de test (retransmission de football,
 * 1080p 60 i/s) : elles ne sont pas mesurées sur le jeu de test de l'étape 1.
 */
enum class Sensitivity(val params: TrackingParams) {
    /** Moins de faux masques ; les très petits visages (moins de ~20 px) peuvent rester visibles. */
    NORMAL(TrackingParams(keepThreshold = 0.5f, confirmThreshold = 0.85f, minHits = 2)),

    /** Compromis par défaut. */
    HIGH(TrackingParams(keepThreshold = 0.4f, confirmThreshold = 0.7f, minHits = 2)),

    /** Moins de visages manqués, davantage de faux masques (proche du comportement de la v0.1). */
    MAX(TrackingParams(keepThreshold = 0.3f, confirmThreshold = 0.5f, minHits = 1)),
}

/** Réglages de traitement. */
data class Options(
    /** Plus grand côté de l'image envoyée au détecteur, en pixels. */
    val analysisMaxSide: Int = 1280,
    val sensitivity: Sensitivity = Sensitivity.HIGH,
    val style: MaskStyle = MaskStyle.BLUR,
    /** Agrandissement de la boîte détectée (l'ellipse inscrite dans une boîte 1,6x couvre 100 % de la boîte d'origine). */
    val maskScale: Float = 1.6f,
    /** Chaque piste est prolongée de ce nombre d'images avant sa première et après sa dernière détection. */
    val marginFrames: Int = 5,
) {
    val tracking: TrackingParams get() = sensitivity.params
}
