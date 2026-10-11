package app.blurr

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc

/** Source d'images pour l'analyse. [run] appelle [onFrame] pour chaque image ; renvoyer false interrompt. */
interface FrameSource {
    /** Nom du décodeur ou du mode, pour le journal. */
    val description: String

    fun run(onFrame: (ptsUs: Long, bgr: Mat) -> Boolean)
}

/**
 * Chemin principal : MediaExtractor + MediaCodec en sortie mémoire (sans surface).
 * Donne l'horodatage de présentation exact de chaque image, y compris sur les vidéos à cadence variable.
 */
class CodecFrameSource(
    private val context: Context,
    private val uri: Uri,
    private val info: VideoInfo,
    private val maxSide: Int,
    /** Ne livre qu'une image sur [stride] (les autres sont décodées puis ignorées, sans conversion). */
    private val stride: Int = 1,
) : FrameSource {

    override var description: String = "MediaCodec"
        private set

    override fun run(onFrame: (Long, Mat) -> Boolean) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val pre = FramePreprocessor(maxSide, info.rotation, info.codedWidth, info.codedHeight)
        try {
            extractor.setDataSource(context, uri, null)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)

            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            description = "MediaCodec ${decoder.name}"
            decoder.configure(format, null, null, 0)
            decoder.start()

            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var frameIndex = 0
            var lastOutputMs = System.currentTimeMillis()

            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val input = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                when {
                    outIndex >= 0 -> {
                        lastOutputMs = System.currentTimeMillis()
                        var keepGoing = true
                        if (bufferInfo.size > 0) {
                            val wanted = frameIndex % stride == 0
                            frameIndex++
                            if (wanted) {
                                val image = decoder.getOutputImage(outIndex)
                                    ?: throw FrameFormatException("getOutputImage a renvoyé null (sortie du décodeur non exploitable)")
                                try {
                                    keepGoing = onFrame(bufferInfo.presentationTimeUs, pre.process(image))
                                } finally {
                                    image.close()
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(outIndex, false)
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        if (!keepGoing) return
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        AppLog.i("Format de sortie du décodeur : ${decoder.outputFormat}")
                    }
                    else -> {
                        if (System.currentTimeMillis() - lastOutputMs > STALL_MS) {
                            throw IllegalStateException("Le décodeur ne produit plus d'images depuis ${STALL_MS / 1000} s")
                        }
                    }
                }
            }
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
            pre.close()
        }
    }

    private companion object {
        const val TIMEOUT_US = 5_000L
        const val STALL_MS = 15_000L
    }
}

/**
 * Chemin de repli, plus lent et moins précis : MediaMetadataRetriever image par image.
 * Les horodatages sont ceux demandés (pas ceux du fichier) ; la fenêtre temporelle du plan de masques absorbe l'écart.
 */
class RetrieverFrameSource(
    private val context: Context,
    private val uri: Uri,
    private val info: VideoInfo,
    private val maxSide: Int,
) : FrameSource {

    override val description: String = "MediaMetadataRetriever (repli)"

    override fun run(onFrame: (Long, Mat) -> Boolean) {
        val retriever = MediaMetadataRetriever()
        val pre = FramePreprocessor(maxSide, 0)
        val rgba = Mat()
        val bgr = Mat()
        try {
            retriever.setDataSource(context, uri)
            val fps = if (info.frameRate in 1f..240f) info.frameRate else 30f
            val stepUs = (1_000_000f / fps).toLong().coerceAtLeast(1_000L)
            val expectLandscape = info.displayWidth >= info.displayHeight

            var t = 0L
            while (t <= info.durationUs) {
                val frame = retriever.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST)
                if (frame != null) {
                    val argb = if (frame.config == Bitmap.Config.ARGB_8888) frame else frame.copy(Bitmap.Config.ARGB_8888, false)
                    Utils.bitmapToMat(argb, rgba)
                    Imgproc.cvtColor(rgba, bgr, Imgproc.COLOR_RGBA2BGR)
                    // Selon la version d'Android, l'image est déjà redressée ou non : on compare au format attendu.
                    val isLandscape = bgr.cols() >= bgr.rows()
                    val rotationToApply = if (info.rotation != 0 && isLandscape != expectLandscape) info.rotation else 0
                    val keepGoing = onFrame(t, pre.processBgr(bgr, rotationToApply))
                    if (argb !== frame) argb.recycle()
                    frame.recycle()
                    if (!keepGoing) return
                }
                t += stepUs
            }
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
            rgba.release()
            bgr.release()
            pre.close()
        }
    }
}
