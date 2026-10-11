package app.blurr

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Plan de masquage : pour chaque image analysée, la liste des ellipses à noircir, en coordonnées normalisées
 * (origine en haut à gauche, repère d'affichage).
 *
 * Deux protections contre les détections manquées :
 *  - chaque ellipse est agrandie ([build] : maskScale) ;
 *  - chaque détection est propagée aux [build] : marginFrames images voisines, avant et après (union des ellipses).
 *
 * Aucune dépendance Android : testable sur JVM.
 */
class MaskPlan private constructor(
    private val ptsUs: LongArray,
    /** Par image : [cx, cy, rx, ry, cx, cy, rx, ry, ...]. */
    private val ellipses: Array<FloatArray>,
    private val toleranceUs: Long,
) {
    private var shiftUs = 0L

    val frameCount: Int get() = ptsUs.size
    val firstPtsUs: Long get() = if (ptsUs.isEmpty()) 0L else ptsUs[0]

    /** Décalage appliqué entre l'horloge de l'export et celle de l'analyse (microsecondes). */
    val appliedShiftUs: Long get() = shiftUs

    /**
     * Cale l'horloge de l'export sur celle de l'analyse à partir de la première image rendue :
     * les deux passes énumèrent les mêmes images dans le même ordre, un éventuel décalage constant
     * (liste d'édition du conteneur, retard de présentation) est donc corrigé ici.
     */
    fun alignTo(firstExportPtsUs: Long): Long {
        if (ptsUs.isEmpty()) return 0L
        val shift = ptsUs[0] - firstExportPtsUs
        shiftUs = if (abs(shift) <= MAX_SHIFT_US) shift else 0L
        return shiftUs
    }

    /** Ellipses à appliquer à l'image d'horodatage [exportPtsUs] ; tableau vide si aucune image analysée n'est assez proche. */
    fun lookup(exportPtsUs: Long): FloatArray {
        if (ptsUs.isEmpty()) return EMPTY
        val t = exportPtsUs + shiftUs
        var lo = 0
        var hi = ptsUs.size - 1
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (ptsUs[mid] < t) lo = mid + 1 else hi = mid
        }
        var best = lo
        if (lo > 0 && abs(ptsUs[lo - 1] - t) <= abs(ptsUs[lo] - t)) best = lo - 1
        return if (abs(ptsUs[best] - t) <= toleranceUs) ellipses[best] else EMPTY
    }

    companion object {
        const val MAX_SHIFT_US = 2_000_000L
        val EMPTY = FloatArray(0)

        fun build(detections: Detections, maskScale: Float, marginFrames: Int): MaskPlan {
            val n = detections.size
            if (n == 0) return MaskPlan(LongArray(0), emptyArray(), 0L)

            // Ordre de présentation garanti, même si la source a livré les images dans un autre ordre.
            val order = (0 until n).sortedBy { detections.ptsUs(it) }
            val times = LongArray(n) { detections.ptsUs(order[it]) }
            val own = Array(n) { i ->
                val faces = detections.faces(order[i])
                FloatArray(faces.size * 4).also { out ->
                    faces.forEachIndexed { k, box -> writeEllipse(box, maskScale, out, k * 4) }
                }
            }

            val k = max(0, marginFrames)
            val merged = Array(n) { i ->
                val from = max(0, i - k)
                val to = min(n - 1, i + k)
                var total = 0
                for (j in from..to) total += own[j].size
                if (total == 0) {
                    EMPTY
                } else {
                    val out = FloatArray(total)
                    var o = 0
                    for (j in from..to) {
                        System.arraycopy(own[j], 0, out, o, own[j].size)
                        o += own[j].size
                    }
                    out
                }
            }

            return MaskPlan(times, merged, toleranceFor(times))
        }

        /** Ellipse centrée sur la boîte, de demi-axes (w, h) x scale / 2 : couvre la boîte d'origine à 100 % pour scale >= 1,42. */
        fun writeEllipse(box: FaceBox, scale: Float, out: FloatArray, at: Int) {
            out[at] = box.x + box.w / 2f
            out[at + 1] = box.y + box.h / 2f
            out[at + 2] = box.w * scale / 2f
            out[at + 3] = box.h * scale / 2f
        }

        private fun toleranceFor(times: LongArray): Long {
            if (times.size < 2) return 200_000L
            val diffs = LongArray(times.size - 1) { times[it + 1] - times[it] }
            diffs.sort()
            val median = diffs[diffs.size / 2]
            return max(120_000L, (median * 5) / 2)
        }
    }
}
