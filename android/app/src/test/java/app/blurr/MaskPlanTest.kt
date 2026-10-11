package app.blurr

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MaskPlanTest {

    private val frameUs = 33_333L

    private fun box(x: Float, y: Float, w: Float, h: Float) = FaceBox(x, y, w, h, 0.9f)

    /** n images à 30 i/s, avec des visages aux indices donnés. */
    private fun detections(n: Int, withFace: Map<Int, List<FaceBox>>, firstPts: Long = 0L): Detections {
        val d = Detections()
        for (i in 0 until n) d.add(firstPts + i * frameUs, withFace[i] ?: emptyList())
        return d
    }

    @Test
    fun geometrieDeLEllipse() {
        val d = detections(1, mapOf(0 to listOf(box(0.4f, 0.3f, 0.2f, 0.2f))))
        val plan = MaskPlan.build(d, maskScale = 1.6f, marginFrames = 0)
        val e = plan.lookup(0L)
        assertEquals(4, e.size)
        assertEquals(0.5f, e[0], 1e-5f) // centre x
        assertEquals(0.4f, e[1], 1e-5f) // centre y
        assertEquals(0.16f, e[2], 1e-5f) // demi-axe x = 0,2 x 1,6 / 2
        assertEquals(0.16f, e[3], 1e-5f)
    }

    @Test
    fun margeEnImagesAvantEtApres() {
        val d = detections(11, mapOf(5 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f))))
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 3)
        for (i in 0 until 11) {
            val masked = plan.lookup(i * frameUs).isNotEmpty()
            assertEquals("image $i", i in 2..8, masked)
        }
    }

    @Test
    fun sansMargeSeuleLImageDetecteeEstMasquee() {
        val d = detections(5, mapOf(2 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f))))
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 0)
        for (i in 0 until 5) assertEquals(i == 2, plan.lookup(i * frameUs).isNotEmpty())
    }

    @Test
    fun uniondesEllipsesSurLaFenetre() {
        val d = detections(
            3,
            mapOf(
                0 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f)),
                1 to listOf(box(0.6f, 0.6f, 0.1f, 0.1f), box(0.3f, 0.3f, 0.1f, 0.1f)),
            ),
        )
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 1)
        assertEquals(12, plan.lookup(frameUs).size) // 1 + 2 visages = 3 ellipses = 12 valeurs
        assertEquals(12, plan.lookup(0L).size)
        assertEquals(8, plan.lookup(2 * frameUs).size) // fenêtre i-1..i+1 : images 1 et 2 seulement
    }

    @Test
    fun toleranceTemporelle() {
        val d = detections(3, mapOf(1 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f))))
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 0)
        // Un léger écart d'horodatage retombe sur l'image la plus proche.
        assertTrue(plan.lookup(frameUs + 8_000L).isNotEmpty())
        assertTrue(plan.lookup(frameUs - 8_000L).isNotEmpty())
        // Très loin de toute image analysée : rien.
        assertEquals(0, plan.lookup(60_000_000L).size)
        assertEquals(0, plan.lookup(-60_000_000L).size)
    }

    @Test
    fun ordreDePresentationRetabliSiLaSourceLivreDansUnAutreOrdre() {
        val d = Detections()
        d.add(2 * frameUs, listOf(box(0.7f, 0.7f, 0.1f, 0.1f)))
        d.add(0L, listOf(box(0.1f, 0.1f, 0.1f, 0.1f)))
        d.add(frameUs, emptyList())
        val plan = MaskPlan.build(d, 1.0f, marginFrames = 0)
        assertEquals(0.15f, plan.lookup(0L)[0], 1e-5f)
        assertEquals(0, plan.lookup(frameUs).size)
        assertEquals(0.75f, plan.lookup(2 * frameUs)[0], 1e-5f)
    }

    @Test
    fun calageDeLHorlogeSurLaPremiereImageExportee() {
        // L'analyse part à 66 666 us (premier échantillon du fichier), l'export à 0.
        val d = detections(4, mapOf(0 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f))), firstPts = 66_666L)
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 0)
        val shift = plan.alignTo(0L)
        assertEquals(66_666L, shift)
        assertEquals(66_666L, plan.appliedShiftUs)
        assertTrue(plan.lookup(0L).isNotEmpty())
        assertEquals(0, plan.lookup(2 * frameUs).size)
    }

    @Test
    fun decalageAbsurdeIgnore() {
        val d = detections(2, mapOf(0 to listOf(box(0.1f, 0.1f, 0.1f, 0.1f))), firstPts = 0L)
        val plan = MaskPlan.build(d, 1.6f, marginFrames = 0)
        assertEquals(0L, plan.alignTo(10_000_000L)) // 10 s : au-delà de la limite de 2 s
        assertTrue(plan.lookup(0L).isNotEmpty())
    }

    @Test
    fun planVide() {
        val plan = MaskPlan.build(Detections(), 1.6f, 5)
        assertEquals(0, plan.frameCount)
        assertEquals(0L, plan.alignTo(123L))
        assertArrayEquals(FloatArray(0), plan.lookup(0L), 0f)
    }

    @Test
    fun toleranceSAdapteAuxCadencesLentes() {
        // 5 i/s (200 ms entre images) : la tolérance doit couvrir la moitié de l'écart, au minimum.
        val d = Detections()
        for (i in 0 until 4) d.add(i * 200_000L, if (i == 1) listOf(box(0.1f, 0.1f, 0.1f, 0.1f)) else emptyList())
        val plan = MaskPlan.build(d, 1.6f, 0)
        assertTrue(plan.lookup(200_000L + 90_000L).isNotEmpty())
    }
}
