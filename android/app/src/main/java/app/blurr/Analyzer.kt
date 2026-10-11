package app.blurr

import android.content.Context
import android.net.Uri
import org.opencv.core.Mat

/** Passe 1 : décode toute la vidéo et détecte les visages image par image. */
object Analyzer {

    class Cancelled : Exception("Analyse annulée")

    class Result(
        val detections: Detections,
        val frames: Int,
        val avgDetectMs: Double,
        val usedFallback: Boolean,
        val source: String,
    )

    fun run(
        context: Context,
        uri: Uri,
        info: VideoInfo,
        options: Options,
        detector: YuNetDetector,
        onProgress: (fraction: Float, frames: Int, msPerFrame: Double) -> Unit,
        isCancelled: () -> Boolean,
    ): Result {
        val detections = Detections()
        var detectNs = 0L
        var frames = 0
        var lastReportMs = 0L

        val onFrame: (Long, Mat) -> Boolean = { ptsUs, bgr ->
            if (isCancelled()) {
                false
            } else {
                val t0 = System.nanoTime()
                val faces = detector.detect(bgr)
                detectNs += System.nanoTime() - t0
                frames++
                detections.add(ptsUs, faces)

                val now = System.currentTimeMillis()
                if (now - lastReportMs >= 250) {
                    lastReportMs = now
                    val fraction = if (info.durationUs > 0) (ptsUs.toFloat() / info.durationUs).coerceIn(0f, 1f) else 0f
                    onProgress(fraction, frames, detectNs / 1e6 / frames)
                }
                true
            }
        }

        var usedFallback = false
        var source: FrameSource = CodecFrameSource(context, uri, info, options.analysisMaxSide)
        try {
            source.run(onFrame)
        } catch (e: Exception) {
            if (isCancelled()) throw Cancelled()
            AppLog.e("Décodage direct impossible, repli sur MediaMetadataRetriever", e)
            usedFallback = true
            detections.clear()
            detectNs = 0
            frames = 0
            source = RetrieverFrameSource(context, uri, info, options.analysisMaxSide)
            source.run(onFrame)
        }
        if (isCancelled()) throw Cancelled()

        val avg = if (frames > 0) detectNs / 1e6 / frames else 0.0
        AppLog.i("Analyse terminée : $frames images, ${detections.totalFaces} détections, ${"%.1f".format(avg)} ms/image (${source.description})")
        return Result(detections, frames, avg, usedFallback, source.description)
    }
}
