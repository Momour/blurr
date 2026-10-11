package app.blurr

import android.media.Image
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import kotlin.math.max
import kotlin.math.roundToInt

class FrameFormatException(message: String) : Exception(message)

/**
 * Transforme une image décodée (YUV) en image BGR redressée et réduite, prête pour le détecteur.
 * Les matrices sont réutilisées d'un appel à l'autre : la Mat renvoyée n'est valable que jusqu'au prochain appel.
 */
class FramePreprocessor(
    private val maxSide: Int,
    private val rotation: Int,
    /** Dimensions codées annoncées par le fichier (avant rotation), 0 si inconnues. */
    private val codedWidth: Int = 0,
    private val codedHeight: Int = 0,
) : AutoCloseable {

    private var loggedFirst = false
    private var packed = ByteArray(0)
    private var yuv = Mat()
    private var bgr = Mat()
    private var small = Mat()
    private var upright = Mat()

    /** Image YUV_420_888 ou P010 issue de MediaCodec, non redressée. */
    fun process(image: Image): Mat {
        val format = image.format
        if (format != YUV_420_888 && format != YCBCR_P010) {
            throw FrameFormatException("Format d'image non pris en charge par l'analyse : $format")
        }
        val crop = image.cropRect
        val w = crop.width() and 1.inv()
        val h = crop.height() and 1.inv()
        if (w <= 0 || h <= 0) throw FrameFormatException("Image vide : ${crop.width()}x${crop.height()}")
        val planes = image.planes
        if (planes.size < 3) throw FrameFormatException("Image à ${planes.size} plans")

        val size = YuvPacker.i420Size(w, h)
        if (packed.size < size) packed = ByteArray(size)
        YuvPacker.packI420(
            PlaneView(planes[0].buffer, planes[0].rowStride, planes[0].pixelStride),
            PlaneView(planes[1].buffer, planes[1].rowStride, planes[1].pixelStride),
            PlaneView(planes[2].buffer, planes[2].rowStride, planes[2].pixelStride),
            crop.left, crop.top, w, h,
            if (format == YCBCR_P010) 1 else 0,
            packed,
        )
        if (yuv.rows() != h * 3 / 2 || yuv.cols() != w) {
            yuv.release()
            yuv = Mat(h * 3 / 2, w, CvType.CV_8UC1)
        }
        yuv.put(0, 0, packed, 0, size)
        Imgproc.cvtColor(yuv, bgr, Imgproc.COLOR_YUV2BGR_I420)
        val applied = Orientation.rotationToApply(rotation, w, h, codedWidth, codedHeight)
        if (!loggedFirst) {
            loggedFirst = true
            AppLog.i(
                "Première image décodée : ${w}x$h (format $format), dimensions annoncées ${codedWidth}x$codedHeight, " +
                    "rotation du fichier $rotation, rotation appliquée $applied" +
                    if (applied != rotation) " (le décodeur livre déjà des images redressées)" else "",
            )
        }
        return finish(bgr, applied)
    }

    /** Image BGR déjà complète (chemin de repli) ; [rotationToApply] vaut 0 si elle est déjà debout. */
    fun processBgr(source: Mat, rotationToApply: Int): Mat = finish(source, rotationToApply)

    private fun finish(source: Mat, rotationDegrees: Int): Mat {
        var current = source
        val longSide = max(source.cols(), source.rows())
        if (longSide > maxSide) {
            val scale = maxSide.toDouble() / longSide
            val nw = max(2, (source.cols() * scale).roundToInt())
            val nh = max(2, (source.rows() * scale).roundToInt())
            Imgproc.resize(source, small, Size(nw.toDouble(), nh.toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)
            current = small
        }
        return when (rotationDegrees) {
            90 -> rotate(current, Core.ROTATE_90_CLOCKWISE)
            180 -> rotate(current, Core.ROTATE_180)
            270 -> rotate(current, Core.ROTATE_90_COUNTERCLOCKWISE)
            else -> current
        }
    }

    private fun rotate(src: Mat, code: Int): Mat {
        Core.rotate(src, upright, code)
        return upright
    }

    override fun close() {
        yuv.release()
        bgr.release()
        small.release()
        upright.release()
    }

    companion object {
        /** android.graphics.ImageFormat.YUV_420_888 */
        const val YUV_420_888 = 35

        /** android.graphics.ImageFormat.YCBCR_P010 (API 33) : 10 bits sur 16, poids fort en tête. */
        const val YCBCR_P010 = 54
    }
}

/** Décision de rotation, sans dépendance Android : testable sur JVM. */
object Orientation {
    /**
     * Rotation horaire à appliquer à une image décodée de [width] x [height].
     *
     * En sortie mémoire (sans surface), MediaCodec ne tourne pas les images : on applique [rotation]. Si pourtant le
     * format de l'image est l'inverse du format codé annoncé par le fichier (paysage contre portrait), le décodeur
     * a déjà redressé l'image et la tourner une seconde fois la coucherait : on n'applique alors rien.
     */
    fun rotationToApply(rotation: Int, width: Int, height: Int, codedWidth: Int, codedHeight: Int): Int {
        if (rotation % 180 == 0) return rotation
        if (codedWidth <= 0 || codedHeight <= 0 || width == height || codedWidth == codedHeight) return rotation
        val frameIsLandscape = width > height
        val codedIsLandscape = codedWidth > codedHeight
        return if (frameIsLandscape != codedIsLandscape) 0 else rotation
    }
}
