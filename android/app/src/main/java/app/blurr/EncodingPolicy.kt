package app.blurr

/** Règles de réglage de l'encodage de sortie. Aucune dépendance Android : testable sur JVM. */
object EncodingPolicy {
    const val MIN_BITRATE = 2_000_000
    const val MAX_BITRATE = 80_000_000

    /** Bits par pixel et par image utilisés quand le débit de la source est inconnu. */
    private const val FALLBACK_BITS_PER_PIXEL = 0.10

    /**
     * Débit vidéo visé pour la sortie. Le fichier est ré-encodé : on reprend le débit de la source pour ne pas
     * perdre en qualité, ou, à défaut, une estimation fondée sur la définition et la cadence. Le résultat est borné
     * pour rester accepté par les encodeurs matériels (l'encodeur ramène lui-même la valeur à sa plage supportée).
     */
    fun videoBitrate(width: Int, height: Int, frameRate: Float, sourceBitrate: Int): Int {
        val fps = if (frameRate in 1f..240f) frameRate.toDouble() else 30.0
        val estimate = width.toDouble() * height.toDouble() * fps * FALLBACK_BITS_PER_PIXEL
        val base = if (sourceBitrate > 0) sourceBitrate.toDouble() else estimate
        return base.coerceIn(MIN_BITRATE.toDouble(), MAX_BITRATE.toDouble()).toInt()
    }

    /** Taille approximative du fichier de sortie en octets (débit vidéo + marge pour l'audio). */
    fun estimatedOutputBytes(durationUs: Long, videoBitrate: Int): Long {
        val seconds = durationUs / 1_000_000.0
        return ((videoBitrate + AUDIO_MARGIN_BITRATE) / 8.0 * seconds).toLong()
    }

    private const val AUDIO_MARGIN_BITRATE = 320_000
}
