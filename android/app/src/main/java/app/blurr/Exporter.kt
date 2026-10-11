package app.blurr

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.TransformationRequest
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/**
 * Passe 2 : ré-encode la vidéo avec [MaskEffect] (flou ou masque noir, Media3 Transformer). Le son est conservé,
 * les métadonnées de la source (GPS compris) ne sont pas recopiées. Toutes les méthodes doivent être appelées depuis
 * le thread principal.
 */
@UnstableApi
class Exporter(context: Context) {

    interface Callback {
        fun onProgress(fraction: Float)
        fun onCompleted(output: File, result: ExportResult)
        fun onError(error: ExportException)
    }

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val progressHolder = ProgressHolder()

    private var transformer: Transformer? = null
    private var outputFile: File? = null
    private var poller: Runnable? = null

    val isRunning: Boolean get() = transformer != null

    fun start(uri: Uri, info: VideoInfo, plan: MaskPlan, style: MaskStyle, hdrMode: Int, callback: Callback) {
        check(Looper.myLooper() === Looper.getMainLooper()) { "L'export doit être démarré depuis le thread principal" }
        check(transformer == null) { "Un export est déjà en cours" }

        val dir = File(appContext.cacheDir, EXPORT_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { if (it.name.startsWith("blurr-")) it.delete() }
        val output = File(dir, "blurr-${System.currentTimeMillis()}.mp4")
        outputFile = output

        val effects = Effects(emptyList<AudioProcessor>(), listOf<Effect>(MaskEffect(plan, style)))
        val item = EditedMediaItem.Builder(MediaItem.fromUri(uri)).setEffects(effects).build()

        // Une séquence "audio + vidéo" fabrique une piste audio muette si la source n'a pas de son : on ne la déclare
        // donc que si la source en possède une.
        val trackTypes = if (info.hasAudio) setOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO) else setOf(C.TRACK_TYPE_VIDEO)
        val sequence = EditedMediaItemSequence.Builder(trackTypes).addItem(item).build()
        val composition = Composition.Builder(sequence).setHdrMode(hdrMode).build()

        val bitrate = EncodingPolicy.videoBitrate(info.displayWidth, info.displayHeight, info.frameRate, info.bitrate)
        val encoderFactory = DefaultEncoderFactory.Builder(appContext)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
            .setEnableFallback(true)
            .build()

        val listener = object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                finish()
                AppLog.i(
                    "Export terminé : ${exportResult.fileSizeBytes} octets, ${exportResult.width}x${exportResult.height}, " +
                        "${exportResult.videoFrameCount} images, ${exportResult.videoMimeType}, " +
                        "encodeur ${exportResult.videoEncoderName}, vidéo ${conversion(exportResult.videoConversionProcess)}, " +
                        "audio ${conversion(exportResult.audioConversionProcess)}",
                )
                callback.onCompleted(output, exportResult)
            }

            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                finish()
                output.delete()
                callback.onError(exportException)
            }

            override fun onFallbackApplied(
                composition: Composition,
                originalTransformationRequest: TransformationRequest,
                fallbackTransformationRequest: TransformationRequest,
            ) {
                AppLog.i("Repli automatique de Transformer : $originalTransformationRequest -> $fallbackTransformationRequest")
            }
        }

        val built = Transformer.Builder(appContext)
            .setEncoderFactory(encoderFactory)
            .setMuxerFactory(NoMetadataMuxerFactory())
            // Pas de limite de délai entre deux échantillons : un encodeur lent sur du 4K ne doit pas être pris pour un blocage.
            .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
            .addListener(listener)
            .build()
        transformer = built

        AppLog.i("Export : débit visé ${bitrate / 1000} kb/s, son ${if (info.hasAudio) "conservé" else "absent de la source"}")
        built.start(composition, output.absolutePath)
        startPolling(callback)
    }

    /** Interrompt l'export en cours et supprime le fichier partiel. */
    fun cancel() {
        val t = transformer ?: return
        stopPolling()
        transformer = null
        try {
            t.cancel()
        } catch (e: Exception) {
            AppLog.e("Annulation de l'export", e)
        }
        outputFile?.delete()
        outputFile = null
    }

    private fun finish() {
        stopPolling()
        transformer = null
    }

    private fun startPolling(callback: Callback) {
        val r = object : Runnable {
            override fun run() {
                val t = transformer ?: return
                if (t.getProgress(progressHolder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    callback.onProgress(progressHolder.progress / 100f)
                }
                handler.postDelayed(this, POLL_MS)
            }
        }
        poller = r
        handler.postDelayed(r, POLL_MS)
    }

    private fun stopPolling() {
        poller?.let { handler.removeCallbacks(it) }
        poller = null
    }

    private fun conversion(value: Int): String = when (value) {
        ExportResult.CONVERSION_PROCESS_NA -> "sans objet"
        ExportResult.CONVERSION_PROCESS_TRANSCODED -> "ré-encodée"
        ExportResult.CONVERSION_PROCESS_TRANSMUXED -> "copiée sans ré-encodage"
        ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED -> "copiée puis ré-encodée"
        else -> "inconnu ($value)"
    }

    private companion object {
        const val EXPORT_DIR = "export"
        const val POLL_MS = 300L
    }
}
