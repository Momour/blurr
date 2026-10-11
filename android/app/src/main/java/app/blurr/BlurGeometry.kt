package app.blurr

import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Paramètres géométriques du rendu de [MaskEffect], sans dépendance Android (testables sur JVM et reproduits à
 * l'identique dans le shader).
 *
 * Flou : l'image est réduite en pyramide (chaque niveau est la moyenne exacte de blocs 2 x 2 du niveau précédent),
 * puis la zone du visage est reconstruite à partir du niveau dont les cellules mesurent environ 1/[CELLS_PER_ELLIPSE]
 * du diamètre de l'ellipse, avec une interpolation B-spline cubique (résultat lisse, sans effet de mosaïque). Le
 * contenu flouté ne dépend que des moyennes de ces cellules : environ 5 cellules sur la plus grande dimension de la
 * boîte du visage, ce qui efface yeux, nez et bouche quelle que soit la taille du visage.
 */
object BlurGeometry {

    /** Cellules sur le diamètre de l'ellipse : 8 cellules / 1,6 = 5 cellules sur la plus grande dimension de la boîte. */
    const val CELLS_PER_ELLIPSE = 8f

    /** Niveau minimal de la pyramide (cellules de 2 px), pour que même un très petit visage soit flouté. */
    const val MIN_LEVEL = 1f

    /** Nombre maximal de niveaux de pyramide. */
    const val MAX_LEVELS = 12

    /**
     * Bord adouci de l'ellipse : opacité 1 jusqu'au rayon normalisé [EDGE_START], 0 au rayon 1.
     * Les coins de la boîte du visage sont au rayon 1 / 1,6 x racine(2) = 0,884 : ils restent entièrement couverts.
     */
    const val EDGE_START = 0.92f

    /** Marge ajoutée aux demi-axes, en pixels de sortie. */
    const val EDGE_PAD_PX = 1.5f

    /** Niveau de pyramide (fractionnaire) pour une ellipse de demi-axes [rxPx] x [ryPx] pixels. */
    fun level(rxPx: Float, ryPx: Float): Float {
        val diameter = 2f * max(rxPx, ryPx)
        val l = (ln((diameter / CELLS_PER_ELLIPSE).toDouble()) / ln(2.0)).toFloat()
        return min(max(MIN_LEVEL, l), (MAX_LEVELS - 1).toFloat())
    }

    /** Niveau entier inférieur utilisé par le shader (le supérieur est [lowerLevel] + 1). */
    fun lowerLevel(level: Float): Int = floor(level).toInt()

    /** Opacité du masque au rayon normalisé [r] (0 au centre, 1 sur l'ellipse) : 1 - smoothstep(EDGE_START, 1, r). */
    fun coverage(r: Float): Float {
        val t = ((r - EDGE_START) / (1f - EDGE_START)).coerceIn(0f, 1f)
        return 1f - t * t * (3f - 2f * t)
    }

    /** Taille du niveau [k] de la pyramide d'une image de [size] pixels (division par 2 arrondie au supérieur). */
    fun levelSize(size: Int, k: Int): Int {
        var s = size
        repeat(k) { s = max(1, (s + 1) / 2) }
        return s
    }
}
