package app.blurr

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MaskPlanTest {

    private val frameUs = 33_333L

    /** Paramètres de test : confirmation à 0,8, une seule détection suffit, prolongation par les scores >= 0,3. */
    private val params = TrackingParams(keepThreshold = 0.3f, confirmThreshold = 0.8f, minHits = 1, maxGapUs = 300_000L)

    private fun box(x: Float, y: Float, w: Float = 0.1f, h: Float = 0.1f, score: Float = 0.9f) = FaceBox(x, y, w, h, score)

    /** n images à 30 i/s, avec des visages aux indices donnés. */
    private fun detections(n: Int, withFace: Map<Int, List<FaceBox>>, firstPts: Long = 0L): Detections {
        val d = Detections()
        for (i in 0 until n) d.add(firstPts + i * frameUs, withFace[i] ?: emptyList())
        return d
    }

    private fun build(
        d: Detections,
        p: TrackingParams = params,
        scale: Float = 1.6f,
        margin: Int = 0,
        union: Int = 0,
    ) = MaskPlan.build(d, p, scale, margin, aspect = 1f, unionFrames = union)

    private fun masked(plan: MaskPlan, i: Int) = plan.lookup(i * frameUs).isNotEmpty()

    @Test
    fun geometrieDeLEllipse() {
        val d = detections(1, mapOf(0 to listOf(box(0.4f, 0.3f, 0.2f, 0.2f))))
        val e = build(d).lookup(0L)
        assertEquals(4, e.size)
        assertEquals(0.5f, e[0], 1e-5f) // centre x
        assertEquals(0.4f, e[1], 1e-5f) // centre y
        assertEquals(0.16f, e[2], 1e-5f) // demi-axe x = 0,2 x 1,6 / 2
        assertEquals(0.16f, e[3], 1e-5f)
    }

    @Test
    fun detectionIsoleeDeScoreMoyenEcartee() {
        // Score 0,6 : au-dessus du seuil de conservation, sous le seuil de confirmation.
        val d = detections(5, mapOf(2 to listOf(box(0.1f, 0.1f, score = 0.6f))))
        val plan = build(d, margin = 3)
        for (i in 0 until 5) assertEquals("image $i", false, masked(plan, i))
        assertEquals(1, plan.stats.tracks)
        assertEquals(0, plan.stats.confirmedTracks)
    }

    @Test
    fun pisteConfirmeeMasqueeAussiSurSesDetectionsFaibles() {
        // Le même visage : score 0,5 sur les images 0 à 3, 0,9 sur l'image 4, puis 0,4.
        val faces = (0 until 8).associateWith { i -> listOf(box(0.3f + i * 0.005f, 0.3f, score = if (i == 4) 0.9f else 0.45f)) }
        val plan = build(detections(8, faces))
        for (i in 0 until 8) assertTrue("image $i", masked(plan, i))
        assertEquals(1, plan.stats.tracks)
        assertEquals(1, plan.stats.confirmedTracks)
    }

    @Test
    fun nombreMinimalDeDetections() {
        val d = detections(3, mapOf(1 to listOf(box(0.1f, 0.1f, score = 0.95f))))
        assertTrue(masked(build(d, params.copy(minHits = 1)), 1))
        assertEquals(false, masked(build(d, params.copy(minHits = 2)), 1))
    }

    @Test
    fun scoresSousLeSeuilDeConservationIgnores() {
        // 0,2 < 0,3 : ne prolonge pas la piste et ne compte pas comme détection.
        val faces = mapOf(0 to listOf(box(0.3f, 0.3f, score = 0.9f)), 1 to listOf(box(0.3f, 0.3f, score = 0.2f)))
        val plan = build(detections(2, faces))
        assertTrue(masked(plan, 0))
        assertEquals(false, masked(plan, 1))
    }

    @Test
    fun trouInterpole() {
        // Détections aux images 0 et 4, rien entre : la boîte suit le déplacement de 0,1 à 0,25 (1,5 taille de visage).
        val faces = mapOf(0 to listOf(box(0.1f, 0.5f)), 4 to listOf(box(0.25f, 0.5f)))
        val plan = build(detections(5, faces), p = params.copy(maxGapUs = 200_000L), scale = 1f)
        for (i in 0 until 5) assertTrue("image $i", masked(plan, i))
        val mid = plan.lookup(2 * frameUs)
        assertEquals(4, mid.size)
        assertEquals(0.225f, mid[0], 1e-4f) // centre x : 0,15 -> 0,30, à mi-chemin
    }

    @Test
    fun trouTropLongNonComble() {
        // 10 images d'écart (333 ms) au-delà de 300 ms : deux pistes, rien entre elles.
        val faces = mapOf(0 to listOf(box(0.1f, 0.5f)), 10 to listOf(box(0.1f, 0.5f)))
        val plan = build(detections(11, faces))
        assertEquals(2, plan.stats.tracks)
        assertTrue(masked(plan, 0))
        assertTrue(masked(plan, 10))
        for (i in 1..9) assertEquals("image $i", false, masked(plan, i))
    }

    @Test
    fun detectionLointaineNeRejointPasLaPiste() {
        // Une détection faible loin du visage confirmé forme sa propre piste, non confirmée.
        val faces = mapOf(
            0 to listOf(box(0.1f, 0.1f, score = 0.9f)),
            1 to listOf(box(0.1f, 0.1f, score = 0.9f), box(0.7f, 0.7f, score = 0.5f)),
        )
        val plan = build(detections(2, faces))
        assertEquals(2, plan.stats.tracks)
        assertEquals(1, plan.stats.confirmedTracks)
        assertEquals(4, plan.lookup(frameUs).size)
    }

    @Test
    fun margeEnImagesAvantEtApres() {
        val d = detections(11, mapOf(5 to listOf(box(0.1f, 0.1f))))
        val plan = build(d, margin = 3)
        for (i in 0 until 11) assertEquals("image $i", i in 2..8, masked(plan, i))
    }

    @Test
    fun sansMargeSeuleLImageDetecteeEstMasquee() {
        val d = detections(5, mapOf(2 to listOf(box(0.1f, 0.1f))))
        val plan = build(d)
        for (i in 0 until 5) assertEquals(i == 2, masked(plan, i))
    }

    @Test
    fun deuxVisagesSimultanes() {
        val d = detections(1, mapOf(0 to listOf(box(0.1f, 0.1f), box(0.6f, 0.6f))))
        assertEquals(8, build(d).lookup(0L).size)
    }

    @Test
    fun unionAvecLesImagesVoisines() {
        // Visage en mouvement rapide : sur l'image 1, la boîte couvre aussi les positions des images 0 et 2.
        val faces = (0 until 3).associateWith { i -> listOf(box(0.2f + i * 0.05f, 0.5f)) }
        val e = build(detections(3, faces), scale = 1f, union = 1).lookup(frameUs)
        assertEquals(4, e.size)
        assertEquals(0.3f, e[0], 1e-4f) // centre de [0,2 ; 0,4]
        assertEquals(0.1f, e[2], 1e-4f) // demi-largeur 0,2 / 2
    }

    @Test
    fun toleranceTemporelle() {
        val d = detections(3, mapOf(1 to listOf(box(0.1f, 0.1f))))
        val plan = build(d)
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
        d.add(2 * frameUs, listOf(box(0.7f, 0.7f)))
        d.add(0L, listOf(box(0.1f, 0.1f)))
        d.add(frameUs, emptyList())
        val plan = build(d, p = params.copy(maxGapUs = 10_000L), scale = 1f)
        assertEquals(0.15f, plan.lookup(0L)[0], 1e-5f)
        assertEquals(0, plan.lookup(frameUs).size)
        assertEquals(0.75f, plan.lookup(2 * frameUs)[0], 1e-5f)
    }

    @Test
    fun calageDeLHorlogeSurLaPremiereImageExportee() {
        // L'analyse part à 66 666 us (premier échantillon du fichier), l'export à 0.
        val d = detections(4, mapOf(0 to listOf(box(0.1f, 0.1f))), firstPts = 66_666L)
        val plan = build(d)
        val shift = plan.alignTo(0L)
        assertEquals(66_666L, shift)
        assertEquals(66_666L, plan.appliedShiftUs)
        assertTrue(plan.lookup(0L).isNotEmpty())
        assertEquals(0, plan.lookup(2 * frameUs).size)
        // Contrôle du fichier produit : décalage explicite, sans toucher à celui de l'export.
        assertTrue(plan.lookupShifted(1_000L, plan.shiftFor(1_000L)).isNotEmpty())
        assertEquals(66_666L, plan.appliedShiftUs)
    }

    @Test
    fun decalageAbsurdeIgnore() {
        val d = detections(2, mapOf(0 to listOf(box(0.1f, 0.1f))), firstPts = 0L)
        val plan = build(d)
        assertEquals(0L, plan.alignTo(10_000_000L)) // 10 s : au-delà de la limite de 2 s
        assertTrue(plan.lookup(0L).isNotEmpty())
    }

    @Test
    fun planVide() {
        val plan = MaskPlan.build(Detections(), params, 1.6f, 5)
        assertEquals(0, plan.frameCount)
        assertEquals(0L, plan.alignTo(123L))
        assertArrayEquals(FloatArray(0), plan.lookup(0L), 0f)
    }

    @Test
    fun toleranceSAdapteAuxCadencesLentes() {
        // 5 i/s (200 ms entre images) : la tolérance doit couvrir la moitié de l'écart, au minimum.
        val d = Detections()
        for (i in 0 until 4) d.add(i * 200_000L, if (i == 1) listOf(box(0.1f, 0.1f)) else emptyList())
        val plan = build(d)
        assertTrue(plan.lookup(200_000L + 90_000L).isNotEmpty())
    }

    @Test
    fun distanceTientCompteDuFormatDeLImage() {
        // En 16/9, un écart horizontal normalisé de 0,05 vaut 0,089 en unités de hauteur.
        val a = box(0.1f, 0.1f, 0.05f, 0.09f)
        val b = box(0.15f, 0.1f, 0.05f, 0.09f)
        val d = MaskPlan.distance(a, b, 16f / 9f)
        assertEquals(0.0889f / 0.0894f, d, 1e-2f)
    }

    @Test
    fun preReglagesOrdonnes() {
        val n = Sensitivity.NORMAL.params
        val h = Sensitivity.HIGH.params
        val m = Sensitivity.MAX.params
        assertTrue(n.confirmThreshold > h.confirmThreshold && h.confirmThreshold > m.confirmThreshold)
        assertTrue(n.keepThreshold >= h.keepThreshold && h.keepThreshold >= m.keepThreshold)
        assertTrue(m.keepThreshold <= m.confirmThreshold)
    }
}
