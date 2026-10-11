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

/** Réglages de traitement. */
data class Options(
    /** Plus grand côté de l'image envoyée au détecteur, en pixels. */
    val analysisMaxSide: Int = 1280,
    /** Seuil de score YuNet : plus bas = moins de visages manqués, plus de faux masques. */
    val scoreThreshold: Float = 0.4f,
    /** Agrandissement de la boîte détectée (l'ellipse inscrite dans une boîte 1,6x couvre 100 % de la boîte d'origine). */
    val maskScale: Float = 1.6f,
    /** Chaque masque est prolongé de ce nombre d'images avant et après chaque détection. */
    val marginFrames: Int = 5,
)
