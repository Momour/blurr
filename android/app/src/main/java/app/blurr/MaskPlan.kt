package app.blurr

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Plan de masquage : pour chaque image analysée, la liste des ellipses à masquer, en coordonnées normalisées
 * (origine en haut à gauche, repère d'affichage).
 *
 * Construction ([build]) :
 *  1. les détections sont reliées d'une image à l'autre en pistes (plus proche voisin, centre à environ une taille
 *     de visage, davantage après un trou, taille comparable) ;
 *  2. seules les pistes confirmées sont masquées : au moins une détection de score >= confirmThreshold et au moins
 *     minHits détections (voir [TrackingParams]). Les détections isolées de score moyen sont écartées ;
 *  3. à l'intérieur d'une piste, les images sans détection (trou d'au plus maxGapUs) reçoivent une boîte interpolée ;
 *  4. chaque piste est prolongée de marginFrames images avant et après ;
 *  5. sur chaque image, la boîte d'une piste couvre aussi ses boîtes des images voisines (unionFrames), puis devient
 *     une ellipse agrandie de maskScale.
 *
 * Aucune dépendance Android : testable sur JVM.
 */
class MaskPlan private constructor(
    private val ptsUs: LongArray,
    /** Par image : [cx, cy, rx, ry, cx, cy, rx, ry, ...]. */
    private val ellipses: Array<FloatArray>,
    private val toleranceUs: Long,
    val stats: Stats,
) {
    /** Bilan du filtrage, pour le journal et l'écran de fin. */
    data class Stats(
        val tracks: Int,
        val confirmedTracks: Int,
        val maskedFrames: Int,
    ) {
        val rejectedTracks: Int get() = tracks - confirmedTracks
    }

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
        shiftUs = shiftFor(firstExportPtsUs)
        return shiftUs
    }

    /** Décalage qui cale une horloge dont la première image est à [firstPtsUs] sur celle de l'analyse. */
    fun shiftFor(firstPtsUs: Long): Long {
        if (ptsUs.isEmpty()) return 0L
        val shift = ptsUs[0] - firstPtsUs
        return if (abs(shift) <= MAX_SHIFT_US) shift else 0L
    }

    /** Ellipses à appliquer à l'image d'horodatage [exportPtsUs] ; tableau vide si aucune image analysée n'est assez proche. */
    fun lookup(exportPtsUs: Long): FloatArray = lookupShifted(exportPtsUs, shiftUs)

    /** Comme [lookup], avec un décalage explicite (contrôle du fichier produit, qui a sa propre horloge). */
    fun lookupShifted(ptsUs: Long, shift: Long): FloatArray {
        if (this.ptsUs.isEmpty()) return EMPTY
        val t = ptsUs + shift
        var lo = 0
        var hi = this.ptsUs.size - 1
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (this.ptsUs[mid] < t) lo = mid + 1 else hi = mid
        }
        var best = lo
        if (lo > 0 && abs(this.ptsUs[lo - 1] - t) <= abs(this.ptsUs[lo] - t)) best = lo - 1
        return if (abs(this.ptsUs[best] - t) <= toleranceUs) ellipses[best] else EMPTY
    }

    companion object {
        const val MAX_SHIFT_US = 2_000_000L
        val EMPTY = FloatArray(0)

        /**
         * Distance maximale entre deux centres d'une même piste, en tailles de visage : [GATE] entre deux images
         * proches, plus [GATE_PER_S] par seconde écoulée (un visage peut se déplacer pendant un trou de détection).
         */
        const val GATE = 1.0f
        const val GATE_PER_S = 6.0f

        /** Rapport de surfaces admis entre deux boîtes d'une même piste. */
        const val MIN_AREA_RATIO = 0.4f
        const val MAX_AREA_RATIO = 2.5f

        /**
         * @param aspect rapport largeur / hauteur de l'image affichée (les coordonnées sont normalisées séparément
         *   en x et en y : il faut ce rapport pour mesurer des distances).
         * @param unionFrames la boîte d'une piste sur une image couvre aussi ses boîtes des [unionFrames] images
         *   voisines (mouvement rapide, léger désaccord d'horodatage entre analyse et export).
         */
        fun build(
            detections: Detections,
            params: TrackingParams,
            maskScale: Float,
            marginFrames: Int,
            aspect: Float = 1f,
            unionFrames: Int = 1,
        ): MaskPlan {
            val n = detections.size
            if (n == 0) return MaskPlan(LongArray(0), emptyArray(), 0L, Stats(0, 0, 0))

            // Ordre de présentation garanti, même si la source a livré les images dans un autre ordre.
            val order = (0 until n).sortedBy { detections.ptsUs(it) }
            val times = LongArray(n) { detections.ptsUs(order[it]) }
            val faces = Array(n) { i -> detections.faces(order[i]).filter { it.score >= params.keepThreshold } }

            val tracks = track(times, faces, params.maxGapUs, if (aspect > 0f) aspect else 1f)
            val confirmed = tracks.filter { t ->
                t.hits.size >= max(1, params.minHits) && t.hits.any { it.box.score >= params.confirmThreshold }
            }

            // Boîtes par image et par piste (interpolation dans les trous, marge aux extrémités).
            val spans = confirmed.map { boxesOf(it, times, max(0, marginFrames)) }
            val u = max(0, unionFrames)
            // Première passe : nombre d'ellipses par image ; seconde passe : remplissage.
            val counts = IntArray(n)
            for (span in spans) {
                for (i in max(0, span.start - u)..min(n - 1, span.end + u)) counts[i]++
            }
            val merged = Array(n) { i -> if (counts[i] == 0) EMPTY else FloatArray(counts[i] * 4) }
            val filled = IntArray(n)
            val unionBox = FloatArray(4)
            for (span in spans) {
                for (i in max(0, span.start - u)..min(n - 1, span.end + u)) {
                    if (!span.unionAround(i, u, unionBox)) continue
                    val box = FaceBox(unionBox[0], unionBox[1], unionBox[2] - unionBox[0], unionBox[3] - unionBox[1], 1f)
                    writeEllipse(box, maskScale, merged[i], filled[i] * 4)
                    filled[i]++
                }
            }
            // Une image dont toutes les fenêtres étaient vides garde des zéros en fin de tableau : on les retire.
            for (i in 0 until n) {
                if (filled[i] != counts[i]) merged[i] = if (filled[i] == 0) EMPTY else merged[i].copyOf(filled[i] * 4)
            }
            val stats = Stats(tracks.size, confirmed.size, merged.count { it.isNotEmpty() })
            return MaskPlan(times, merged, toleranceFor(times), stats)
        }

        /** Ellipse centrée sur la boîte, de demi-axes (w, h) x scale / 2 : couvre la boîte d'origine à 100 % pour scale >= 1,42. */
        fun writeEllipse(box: FaceBox, scale: Float, out: FloatArray, at: Int) {
            out[at] = box.x + box.w / 2f
            out[at + 1] = box.y + box.h / 2f
            out[at + 2] = box.w * scale / 2f
            out[at + 3] = box.h * scale / 2f
        }

        // ------------------------------------------------------------------ suivi

        class Hit(val frame: Int, val box: FaceBox)

        class Track {
            val hits = ArrayList<Hit>()
            val last: Hit get() = hits[hits.size - 1]
        }

        /** Relie les détections en pistes, image par image, par appariement glouton du plus proche voisin. */
        fun track(times: LongArray, faces: Array<List<FaceBox>>, maxGapUs: Long, aspect: Float): List<Track> {
            val all = ArrayList<Track>()
            val active = ArrayList<Track>()
            for (i in times.indices) {
                active.removeAll { times[i] - times[it.last.frame] > maxGapUs }
                val dets = faces[i]
                if (dets.isEmpty()) continue

                class Pair(val dist: Float, val track: Int, val det: Int)
                val pairs = ArrayList<Pair>()
                for ((ti, t) in active.withIndex()) {
                    val b = t.last.box
                    val gate = GATE + GATE_PER_S * (times[i] - times[t.last.frame]) / 1_000_000f
                    for ((di, d) in dets.withIndex()) {
                        val dist = distance(b, d, aspect)
                        val ratio = (d.w * d.h) / (b.w * b.h)
                        if (dist <= gate && ratio in MIN_AREA_RATIO..MAX_AREA_RATIO) pairs.add(Pair(dist, ti, di))
                    }
                }
                pairs.sortBy { it.dist }
                val usedTracks = BooleanArray(active.size)
                val usedDets = BooleanArray(dets.size)
                for (p in pairs) {
                    if (usedTracks[p.track] || usedDets[p.det]) continue
                    usedTracks[p.track] = true
                    usedDets[p.det] = true
                    active[p.track].hits.add(Hit(i, dets[p.det]))
                }
                for ((di, d) in dets.withIndex()) {
                    if (usedDets[di]) continue
                    val t = Track()
                    t.hits.add(Hit(i, d))
                    all.add(t)
                    active.add(t)
                }
            }
            return all
        }

        /** Distance entre centres rapportée à la taille moyenne des deux boîtes (unités proportionnelles aux pixels). */
        fun distance(a: FaceBox, b: FaceBox, aspect: Float): Float {
            val dx = ((a.x + a.w / 2f) - (b.x + b.w / 2f)) * aspect
            val dy = (a.y + a.h / 2f) - (b.y + b.h / 2f)
            val size = ((a.w * aspect + a.h) / 2f + (b.w * aspect + b.h) / 2f) / 2f
            return if (size > 0f) hypot(dx, dy) / size else Float.MAX_VALUE
        }

        /** Boîtes [x0, y0, x1, y1] d'une piste, des images [start] à [end] incluses (null : pas de boîte). */
        class Span(val start: Int, val end: Int, private val boxes: Array<FloatArray?>) {
            fun at(frame: Int): FloatArray? = if (frame in start..end) boxes[frame - start] else null

            /** Boîte englobant les boîtes des images [frame] - [u] à [frame] + [u] ; false si aucune. */
            fun unionAround(frame: Int, u: Int, out: FloatArray): Boolean {
                var any = false
                for (j in frame - u..frame + u) {
                    val b = at(j) ?: continue
                    if (!any) {
                        b.copyInto(out)
                        any = true
                    } else {
                        out[0] = min(out[0], b[0]); out[1] = min(out[1], b[1])
                        out[2] = max(out[2], b[2]); out[3] = max(out[3], b[3])
                    }
                }
                return any
            }
        }

        private fun boxesOf(t: Track, times: LongArray, margin: Int): Span {
            val n = times.size
            val hits = t.hits
            val first = hits[0]
            val last = t.last
            val start = max(0, first.frame - margin)
            val end = min(n - 1, last.frame + margin)
            val out = arrayOfNulls<FloatArray>(end - start + 1)
            fun corners(b: FaceBox) = floatArrayOf(b.x, b.y, b.x + b.w, b.y + b.h)
            for (k in 0 until hits.size - 1) {
                val a = hits[k]
                val b = hits[k + 1]
                val ca = corners(a.box)
                val cb = corners(b.box)
                val span = (times[b.frame] - times[a.frame]).toFloat()
                for (f in a.frame until b.frame) {
                    val w = if (span > 0f) (times[f] - times[a.frame]) / span else 0f
                    out[f - start] = FloatArray(4) { ca[it] + (cb[it] - ca[it]) * w }
                }
            }
            out[last.frame - start] = corners(last.box)
            for (f in start until first.frame) out[f - start] = corners(first.box)
            for (f in last.frame + 1..end) out[f - start] = corners(last.box)
            return Span(start, end, out)
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
