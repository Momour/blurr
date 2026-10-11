package app.blurr

import java.nio.ByteBuffer
import java.util.Arrays

/**
 * Vue d'un plan d'image : équivalent de android.media.Image.Plane, sans dépendance Android
 * pour pouvoir être testé sur JVM.
 */
class PlaneView(val buffer: ByteBuffer, val rowStride: Int, val pixelStride: Int)

/**
 * Convertit les plans d'une image YUV 4:2:0 (planaire, semi-planaire NV12/NV21, strides quelconques,
 * zone de rognage) en un tableau I420 contigu, prêt pour cv::cvtColor.
 */
object YuvPacker {

    fun i420Size(width: Int, height: Int): Int = width * height * 3 / 2

    /**
     * @param sampleByteOffset 0 pour du 8 bits ; 1 pour du 10 bits stocké sur 16 bits poids fort en tête
     *   (P010, petit-boutiste) : on garde l'octet de poids fort, soit les 8 bits de tête de chaque échantillon.
     */
    fun packI420(
        y: PlaneView,
        u: PlaneView,
        v: PlaneView,
        cropLeft: Int,
        cropTop: Int,
        width: Int,
        height: Int,
        sampleByteOffset: Int,
        out: ByteArray,
    ) {
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) { "dimensions paires attendues : ${width}x$height" }
        require(out.size >= i420Size(width, height)) { "tableau de sortie trop petit" }
        val chromaW = width / 2
        val chromaH = height / 2
        copyPlane(y, cropLeft, cropTop, width, height, sampleByteOffset, out, 0, 0)
        copyPlane(u, cropLeft / 2, cropTop / 2, chromaW, chromaH, sampleByteOffset, out, width * height, 128.toByte())
        copyPlane(v, cropLeft / 2, cropTop / 2, chromaW, chromaH, sampleByteOffset, out, width * height + chromaW * chromaH, 128.toByte())
    }

    private fun copyPlane(
        plane: PlaneView,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        sampleByteOffset: Int,
        dst: ByteArray,
        dstStart: Int,
        fill: Byte,
    ) {
        val buf = plane.buffer.duplicate() // ne modifie pas la position du tampon d'origine
        val base = buf.position()
        val limit = buf.limit()
        var o = dstStart
        if (plane.pixelStride == 1 && sampleByteOffset == 0) {
            for (r in 0 until height) {
                val start = base + (top + r) * plane.rowStride + left
                val available = limit - start
                when {
                    available >= width -> {
                        buf.position(start)
                        buf.get(dst, o, width)
                    }
                    available > 0 -> {
                        buf.position(start)
                        buf.get(dst, o, available)
                        Arrays.fill(dst, o + available, o + width, fill)
                    }
                    else -> Arrays.fill(dst, o, o + width, fill)
                }
                o += width
            }
        } else {
            for (r in 0 until height) {
                val rowStart = base + (top + r) * plane.rowStride + left * plane.pixelStride + sampleByteOffset
                for (c in 0 until width) {
                    val index = rowStart + c * plane.pixelStride
                    dst[o++] = if (index in 0 until limit) buf.get(index) else fill
                }
            }
        }
    }
}
