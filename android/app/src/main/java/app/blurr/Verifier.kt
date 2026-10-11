package app.blurr

import android.content.Context
import android.net.Uri
import java.io.File
import kotlin.math.max

/**
 * Passe 3 : relit la vidéo PRODUITE et cherche des visages encore détectables HORS des zones masquées.
 *
 * Un visage flouté peut rester détectable (le détecteur reconnaît parfois une tache de la forme d'un visage) : les
 * détections situées dans une ellipse du plan sont donc ignorées. Une détection hors de toute ellipse, avec un score
 * au moins égal au seuil de confirmation des pistes, signale une erreur du traitement (masques décalés dans le temps,
 * mal placés ou absents).
 *
 * Ce contrôle ne remplace pas la vérification visuelle : il ne voit pas les visages que le détecteur n'a déjà pas
 * trouvés dans la vidéo d'origine.
 */
object Verifier {

    /** Seuil minimal : on ne signale que des visages nets. Le seuil effectif est au moins celui de confirmation. */
    const val SCORE_THRESHOLD = 0.6f

    private const val MAX_SAMPLES = 600

    class Result(
        val sampledFrames: Int,
        /** Images où un visage reste détectable hors de toute zone masquée. */
        val framesWithFaces: Int,
        val faces: Int,
        val maxScore: Float,
        val outputFrameEstimate: Int,
        /** Détections situées dans une zone masquée (normal avec le flou), pour le journal. */
        val insideMask: Int,
    )

    fun run(
        context: Context,
        file: File,
        plan: MaskPlan,
        options: Options,
        onProgress: (Float) -> Unit,
        isCancelled: () -> Boolean,
    ): Result {
        val uri = Uri.fromFile(file)
        val info = VideoProbe.read(context, uri)
        val fps = if (info.frameRate in 1f..240f) info.frameRate else 30f
        val estimate = max(1, (info.durationUs / 1_000_000.0 * fps).toInt())
        val stride = max(1, estimate / MAX_SAMPLES)

        var sampled = 0
        var withFaces = 0
        var faces = 0
        var maxScore = 0f
        var insideMask = 0
        var lastReportMs = 0L
        var shift = Long.MIN_VALUE
        val threshold = max(SCORE_THRESHOLD, options.tracking.confirmThreshold)

        YuNetDetector(context, threshold).use { detector ->
            // Même résolution que l'analyse : les scores sont comparables à ceux qui ont servi au masquage.
            val source = CodecFrameSource(context, uri, info, options.analysisMaxSide, stride)
            source.run { ptsUs, bgr ->
                if (isCancelled()) {
                    false
                } else {
                    if (shift == Long.MIN_VALUE) shift = plan.shiftFor(ptsUs)
                    val ellipses = plan.lookupShifted(ptsUs, shift)
                    val found = detector.detect(bgr)
                    val outside = found.filter { !isInside(it, ellipses) }
                    insideMask += found.size - outside.size
                    sampled++
                    if (outside.isNotEmpty()) {
                        withFaces++
                        faces += outside.size
                        maxScore = max(maxScore, outside.maxOf { it.score })
                        AppLog.i("Contrôle : ${outside.size} visage(s) détectable(s) hors masque à ${ptsUs / 1000} ms (score ${"%.2f".format(outside.maxOf { it.score })})")
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastReportMs >= 250) {
                        lastReportMs = now
                        val fraction = if (info.durationUs > 0) (ptsUs.toFloat() / info.durationUs).coerceIn(0f, 1f) else 0f
                        onProgress(fraction)
                    }
                    true
                }
            }
        }
        AppLog.i(
            "Contrôle terminé : $sampled images relues (une sur $stride), seuil $threshold, $withFaces avec visage détectable " +
                "hors masque ($faces visages), $insideMask détections dans une zone masquée",
        )
        return Result(sampled, withFaces, faces, maxScore, estimate, insideMask)
    }

    /** Le centre de la boîte est-il dans l'une des ellipses [cx, cy, rx, ry, ...] ? */
    fun isInside(box: FaceBox, ellipses: FloatArray): Boolean {
        val x = box.x + box.w / 2f
        val y = box.y + box.h / 2f
        var i = 0
        while (i + 3 < ellipses.size) {
            val dx = (x - ellipses[i]) / ellipses[i + 2]
            val dy = (y - ellipses[i + 1]) / ellipses[i + 3]
            if (dx * dx + dy * dy <= 1f) return true
            i += 4
        }
        return false
    }
}
