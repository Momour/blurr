package app.blurr

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer

class YuvPackerTest {

    private fun yVal(x: Int, y: Int) = (x * 7 + y * 13) % 200 + 20
    private fun uVal(x: Int, y: Int) = (x * 5 + y * 3) % 100 + 50
    private fun vVal(x: Int, y: Int) = (x * 11 + y * 2) % 100 + 100

    /** I420 attendu pour la zone (left, top, width, height) de l'image synthétique. */
    private fun expected(left: Int, top: Int, w: Int, h: Int): ByteArray {
        val out = ByteArray(YuvPacker.i420Size(w, h))
        var o = 0
        for (y in 0 until h) for (x in 0 until w) out[o++] = yVal(left + x, top + y).toByte()
        for (y in 0 until h / 2) for (x in 0 until w / 2) out[o++] = uVal(left / 2 + x, top / 2 + y).toByte()
        for (y in 0 until h / 2) for (x in 0 until w / 2) out[o++] = vVal(left / 2 + x, top / 2 + y).toByte()
        return out
    }

    private fun yPlane(width: Int, height: Int, rowStride: Int, pixelStride: Int = 1, hiByte: Boolean = false): PlaneView {
        val data = ByteArray(rowStride * height) { 0xEE.toByte() } // le remplissage doit être ignoré
        for (y in 0 until height) for (x in 0 until width) {
            val i = y * rowStride + x * pixelStride
            if (hiByte) {
                data[i] = 0x40
                data[i + 1] = yVal(x, y).toByte()
            } else {
                data[i] = yVal(x, y).toByte()
            }
        }
        return PlaneView(ByteBuffer.wrap(data), rowStride, pixelStride)
    }

    @Test
    fun planaireAvecPaddingDeLignes() {
        val w = 8
        val h = 6
        val cw = w / 2
        val ch = h / 2
        val u = ByteArray(6 * ch) { 0xEE.toByte() }
        val v = ByteArray(6 * ch) { 0xEE.toByte() }
        for (y in 0 until ch) for (x in 0 until cw) {
            u[y * 6 + x] = uVal(x, y).toByte()
            v[y * 6 + x] = vVal(x, y).toByte()
        }
        val out = ByteArray(YuvPacker.i420Size(w, h))
        YuvPacker.packI420(
            yPlane(w, h, rowStride = 12),
            PlaneView(ByteBuffer.wrap(u), 6, 1),
            PlaneView(ByteBuffer.wrap(v), 6, 1),
            0, 0, w, h, 0, out,
        )
        assertArrayEquals(expected(0, 0, w, h), out)
    }

    @Test
    fun semiPlanaireNv12() {
        val w = 8
        val h = 4
        val cw = w / 2
        val ch = h / 2
        val rowStride = 10
        val uv = ByteArray(rowStride * ch) { 0xEE.toByte() }
        for (y in 0 until ch) for (x in 0 until cw) {
            uv[y * rowStride + x * 2] = uVal(x, y).toByte()
            uv[y * rowStride + x * 2 + 1] = vVal(x, y).toByte()
        }
        // Comme MediaCodec : le plan V est une vue décalée d'un octet sur le même tampon.
        val uBuf = ByteBuffer.wrap(uv)
        val vBuf = ByteBuffer.wrap(uv, 1, uv.size - 1).slice()
        val out = ByteArray(YuvPacker.i420Size(w, h))
        YuvPacker.packI420(
            yPlane(w, h, rowStride = w),
            PlaneView(uBuf, rowStride, 2),
            PlaneView(vBuf, rowStride, 2),
            0, 0, w, h, 0, out,
        )
        assertArrayEquals(expected(0, 0, w, h), out)
    }

    @Test
    fun semiPlanaireNv21OrdreInverse() {
        val w = 4
        val h = 4
        val cw = w / 2
        val ch = h / 2
        val vu = ByteArray(cw * 2 * ch)
        for (y in 0 until ch) for (x in 0 until cw) {
            vu[y * cw * 2 + x * 2] = vVal(x, y).toByte()
            vu[y * cw * 2 + x * 2 + 1] = uVal(x, y).toByte()
        }
        val vBuf = ByteBuffer.wrap(vu)
        val uBuf = ByteBuffer.wrap(vu, 1, vu.size - 1).slice()
        val out = ByteArray(YuvPacker.i420Size(w, h))
        YuvPacker.packI420(
            yPlane(w, h, rowStride = w),
            PlaneView(uBuf, cw * 2, 2),
            PlaneView(vBuf, cw * 2, 2),
            0, 0, w, h, 0, out,
        )
        assertArrayEquals(expected(0, 0, w, h), out)
    }

    @Test
    fun rognageDecale() {
        val fullW = 16
        val fullH = 12
        val cw = fullW / 2
        val ch = fullH / 2
        val u = ByteArray(cw * ch)
        val v = ByteArray(cw * ch)
        for (y in 0 until ch) for (x in 0 until cw) {
            u[y * cw + x] = uVal(x, y).toByte()
            v[y * cw + x] = vVal(x, y).toByte()
        }
        val out = ByteArray(YuvPacker.i420Size(8, 6))
        YuvPacker.packI420(
            yPlane(fullW, fullH, rowStride = fullW),
            PlaneView(ByteBuffer.wrap(u), cw, 1),
            PlaneView(ByteBuffer.wrap(v), cw, 1),
            cropLeft = 4, cropTop = 2, width = 8, height = 6, sampleByteOffset = 0, out = out,
        )
        assertArrayEquals(expected(4, 2, 8, 6), out)
    }

    @Test
    fun p010GardeLOctetDePoidsFort() {
        val w = 4
        val h = 4
        val cw = w / 2
        val ch = h / 2
        // Chroma P010 : U et V sur 16 bits chacun, entrelacés, poids fort en second octet (petit-boutiste).
        val rowStride = cw * 4
        val uv = ByteArray(rowStride * ch)
        for (y in 0 until ch) for (x in 0 until cw) {
            val b = y * rowStride + x * 4
            uv[b] = 0x40
            uv[b + 1] = uVal(x, y).toByte()
            uv[b + 2] = 0x40
            uv[b + 3] = vVal(x, y).toByte()
        }
        val uBuf = ByteBuffer.wrap(uv)
        val vBuf = ByteBuffer.wrap(uv, 2, uv.size - 2).slice()
        val out = ByteArray(YuvPacker.i420Size(w, h))
        YuvPacker.packI420(
            yPlane(w, h, rowStride = w * 2, pixelStride = 2, hiByte = true),
            PlaneView(uBuf, rowStride, 4),
            PlaneView(vBuf, rowStride, 4),
            0, 0, w, h, sampleByteOffset = 1, out = out,
        )
        assertArrayEquals(expected(0, 0, w, h), out)
    }

    @Test
    fun tamponTronqueCompleteLaChromaAvec128() {
        val w = 4
        val h = 4
        val out = ByteArray(YuvPacker.i420Size(w, h))
        val shortU = ByteBuffer.wrap(ByteArray(2)) // 1 ligne de chroma sur 2
        val shortV = ByteBuffer.wrap(ByteArray(0))
        YuvPacker.packI420(
            yPlane(w, h, rowStride = w),
            PlaneView(shortU, 2, 1),
            PlaneView(shortV, 2, 1),
            0, 0, w, h, 0, out,
        )
        val uStart = w * h
        assertEquals(0, out[uStart].toInt())
        assertEquals(0, out[uStart + 1].toInt())
        assertEquals(128, out[uStart + 2].toInt() and 0xFF)
        assertEquals(128, out[uStart + 3].toInt() and 0xFF)
        val vStart = uStart + 4
        for (i in 0 until 4) assertEquals(128, out[vStart + i].toInt() and 0xFF)
    }

    @Test
    fun laPositionDuTamponDOrigineNEstPasModifiee() {
        val w = 4
        val h = 2
        val y = yPlane(w, h, rowStride = w)
        val before = y.buffer.position()
        val out = ByteArray(YuvPacker.i420Size(w, h))
        YuvPacker.packI420(
            y,
            PlaneView(ByteBuffer.wrap(ByteArray(2)), 2, 1),
            PlaneView(ByteBuffer.wrap(ByteArray(2)), 2, 1),
            0, 0, w, h, 0, out,
        )
        assertEquals(before, y.buffer.position())
    }

    @Test(expected = IllegalArgumentException::class)
    fun refuseLesDimensionsImpaires() {
        val out = ByteArray(64)
        YuvPacker.packI420(
            yPlane(5, 4, rowStride = 5),
            PlaneView(ByteBuffer.wrap(ByteArray(8)), 2, 1),
            PlaneView(ByteBuffer.wrap(ByteArray(8)), 2, 1),
            0, 0, 5, 4, 0, out,
        )
    }
}
