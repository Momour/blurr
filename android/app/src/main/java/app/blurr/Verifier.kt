package app.blurr

import android.content.Context
import android.net.Uri
import java.io.File
import kotlin.math.max

/**
 * Passe 3 : relit la vidéo PRODUITE et cherche des visages encore détectables (seuil strict).
 *
 * Ce contrôle ne remplace pas la vérification visuelle : il ne voit pas les visages que le détecteur n'a déjà pas
 * trouvés dans la vidéo d'origine. Il sert à repérer une erreur du traitement lui-même (masques décalés dans le temps,
 * mal placés ou absents), qui laisserait des visages détectables dans le fichier de sortie.
 */
object Verifier {

    /** Seuil volontairement strict : on ne signale que des visages nets, pas de simples restes de masque. */
    const val SCORE_THRESHOLD = 0.6f

    private const val MAX_SAMPLES = 600
    private const val ANALYSIS_SIDE = 1280

    class Result(
        val sampledFrames: Int,
        val framesWithFaces: Int,
        val faces: Int,
        val maxScore: Float,
        val outputFrameEstimate: Int,
    )

    fun run(
        context: Context,
        file: File,
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
        var lastReportMs = 0L

        YuNetDetector(context, SCORE_THRESHOLD).use { detector ->
            val source = CodecFrameSource(context, uri, info, ANALYSIS_SIDE, stride)
            source.run { ptsUs, bgr ->
                if (isCancelled()) {
                    false
                } else {
                    val found = detector.detect(bgr)
                    sampled++
                    if (found.isNotEmpty()) {
                        withFaces++
                        faces += found.size
                        maxScore = max(maxScore, found.maxOf { it.score })
                        AppLog.i("Contrôle : ${found.size} visage(s) encore détectable(s) à ${ptsUs / 1000} ms (score ${"%.2f".format(found.maxOf { it.score })})")
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
        AppLog.i("Contrôle terminé : $sampled images relues (une sur $stride), $withFaces avec visage détectable, $faces visages")
        return Result(sampled, withFaces, faces, maxScore, estimate)
    }
}
