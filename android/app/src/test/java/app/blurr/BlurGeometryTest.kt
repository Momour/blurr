package app.blurr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sqrt

class BlurGeometryTest {

    @Test
    fun coinsDeLaBoiteEntierementCouverts() {
        // Ellipse = boîte x 1,6 : les coins de la boîte sont au rayon normalisé racine(2) / 1,6.
        val corner = sqrt(2f) / 1.6f
        assertEquals(1f, BlurGeometry.coverage(corner), 0f)
        assertEquals(1f, BlurGeometry.coverage(0f), 0f)
        assertEquals(0f, BlurGeometry.coverage(1f), 0f)
        assertEquals(0f, BlurGeometry.coverage(1.2f), 0f)
        val mid = BlurGeometry.coverage((BlurGeometry.EDGE_START + 1f) / 2f)
        assertEquals(0.5f, mid, 1e-5f)
    }

    @Test
    fun niveauProportionnelALaTailleDuVisage() {
        // Ellipse de 128 px de diamètre : cellules de 128 / 8 = 16 px, niveau 4.
        assertEquals(4f, BlurGeometry.level(64f, 50f), 1e-5f)
        // Deux fois plus grand : un niveau de plus.
        assertEquals(5f, BlurGeometry.level(128f, 100f), 1e-5f)
        // Le plus grand des deux demi-axes compte.
        assertEquals(4f, BlurGeometry.level(30f, 64f), 1e-5f)
    }

    @Test
    fun niveauBorne() {
        assertEquals(BlurGeometry.MIN_LEVEL, BlurGeometry.level(2f, 2f), 0f)
        assertEquals((BlurGeometry.MAX_LEVELS - 1).toFloat(), BlurGeometry.level(1e7f, 1e7f), 0f)
        assertTrue(BlurGeometry.lowerLevel(BlurGeometry.level(1e7f, 1e7f)) + 1 <= BlurGeometry.MAX_LEVELS)
    }

    @Test
    fun cinqCellulesSurLaBoiteDuVisage() {
        // Boîte de 100 px, ellipse x 1,6 : demi-axe 80 px. Taille de cellule 2^niveau = 100 / 5 = 20 px.
        val level = BlurGeometry.level(80f, 80f)
        val cell = Math.pow(2.0, level.toDouble())
        assertEquals(20.0, cell, 1e-3)
    }

    @Test
    fun taillesDeLaPyramide() {
        assertEquals(960, BlurGeometry.levelSize(1920, 1))
        assertEquals(540, BlurGeometry.levelSize(1080, 1))
        assertEquals(270, BlurGeometry.levelSize(1080, 2))
        assertEquals(68, BlurGeometry.levelSize(1080, 4)) // 1080 -> 540 -> 270 -> 135 -> 68
        assertEquals(1, BlurGeometry.levelSize(1080, 11))
        assertEquals(1920, BlurGeometry.levelSize(1920, 0))
    }

    @Test
    fun shaderAlignéSurLesConstantes() {
        assertTrue(MaskShaders.COVERAGE.contains("smoothstep(${BlurGeometry.EDGE_START}, 1.0, r)"))
        assertTrue(MaskShaders.BLUR_FRAGMENT_SHADER.contains("float coverage()"))
        assertTrue(MaskShaders.BLACK_FRAGMENT_SHADER.contains("float coverage()"))
        assertTrue(MaskShaders.COPY_FRAGMENT_SHADER.contains("precision highp float"))
    }

    @Test
    fun controleIgnoreLesVisagesDansUneZoneMasquee() {
        val ellipses = floatArrayOf(0.5f, 0.5f, 0.1f, 0.1f)
        assertTrue(Verifier.isInside(FaceBox(0.45f, 0.45f, 0.1f, 0.1f, 0.9f), ellipses))
        assertFalse(Verifier.isInside(FaceBox(0.8f, 0.8f, 0.1f, 0.1f, 0.9f), ellipses))
        assertFalse(Verifier.isInside(FaceBox(0.45f, 0.45f, 0.1f, 0.1f, 0.9f), FloatArray(0)))
    }
}
