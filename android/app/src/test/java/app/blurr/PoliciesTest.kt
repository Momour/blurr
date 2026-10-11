package app.blurr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PoliciesTest {

    @Test
    fun debitDeLaSourceReprisTelQuelDansLaPlage() {
        assertEquals(12_000_000, EncodingPolicy.videoBitrate(1920, 1080, 30f, 12_000_000))
    }

    @Test
    fun debitBorne() {
        assertEquals(EncodingPolicy.MAX_BITRATE, EncodingPolicy.videoBitrate(3840, 2160, 60f, 400_000_000))
        assertEquals(EncodingPolicy.MIN_BITRATE, EncodingPolicy.videoBitrate(640, 360, 30f, 300_000))
    }

    @Test
    fun debitEstimeQuandLaSourceNeLeDonnePas() {
        // 1920 x 1080 x 30 x 0,10 = 6 220 800
        assertEquals(6_220_800, EncodingPolicy.videoBitrate(1920, 1080, 30f, 0))
        // Cadence inconnue : 30 i/s supposées.
        assertEquals(6_220_800, EncodingPolicy.videoBitrate(1920, 1080, 0f, 0))
    }

    @Test
    fun tailleEstimee() {
        // (8 000 000 + 320 000) / 8 x 10 s = 10 400 000 octets
        assertEquals(10_400_000L, EncodingPolicy.estimatedOutputBytes(10_000_000L, 8_000_000))
        assertEquals(0L, EncodingPolicy.estimatedOutputBytes(0L, 8_000_000))
    }

    @Test
    fun nomDeSortie() {
        assertEquals("vacances_blurr.mp4", MediaStoreSaver.outputName("vacances.MOV"))
        assertEquals("c_blurr.mp4", MediaStoreSaver.outputName("a/b/c.mp4"))
        assertEquals("sans_extension_blurr.mp4", MediaStoreSaver.outputName("sans_extension"))
        assertEquals("video_blurr.mp4", MediaStoreSaver.outputName(""))
        assertEquals("video_blurr.mp4", MediaStoreSaver.outputName(".."))
        // ':', '*' et '?' deviennent chacun '_' ; le suffixe "_blurr" s'y ajoute.
        assertEquals("a_b___blurr.mp4", MediaStoreSaver.outputName("a:b*?.mp4"))
        assertEquals("a.b.c_blurr.mp4", MediaStoreSaver.outputName("a.b.c.mp4"))
    }

    @Test
    fun nomDeSortieLongTronque() {
        val name = MediaStoreSaver.outputName("x".repeat(300) + ".mp4")
        assertTrue(name.length <= 80 + "_blurr.mp4".length)
        assertTrue(name.endsWith("_blurr.mp4"))
    }

    @Test
    fun resumeDesDetections() {
        val d = Detections()
        d.add(0L, emptyList())
        d.add(33_333L, listOf(FaceBox(0.1f, 0.1f, 0.1f, 0.1f, 0.9f), FaceBox(0.5f, 0.5f, 0.1f, 0.1f, 0.8f)))
        d.add(66_666L, listOf(FaceBox(0.1f, 0.1f, 0.1f, 0.1f, 0.9f)))
        assertEquals(3, d.size)
        assertEquals(3, d.totalFaces)
        assertEquals(2, d.framesWithFaces)
        d.clear()
        assertEquals(0, d.size)
    }

    @Test
    fun dimensionsAffichees() {
        val portrait = VideoInfo("v.mp4", "video/avc", 1920, 1080, 90, 1_000_000L, 30f, 0, false, true)
        assertEquals(1080, portrait.displayWidth)
        assertEquals(1920, portrait.displayHeight)
        val paysage = portrait.copy(rotation = 180)
        assertEquals(1920, paysage.displayWidth)
        assertEquals(1080, paysage.displayHeight)
    }
}

class OrientationTest {

    @Test
    fun rotationAppliqueeQuandLeDecodeurNeTournePas() {
        // Vidéo 1920 x 1080 à tourner de 90 : le décodeur livre 1920 x 1080.
        assertEquals(90, Orientation.rotationToApply(90, 1920, 1080, 1920, 1080))
        assertEquals(270, Orientation.rotationToApply(270, 1920, 1080, 1920, 1080))
    }

    @Test
    fun rotationIgnoreeQuandLeDecodeurARedresseDeja() {
        // Le décodeur a livré 1080 x 1920 alors que le fichier est codé en 1920 x 1080.
        assertEquals(0, Orientation.rotationToApply(90, 1080, 1920, 1920, 1080))
        assertEquals(0, Orientation.rotationToApply(270, 1080, 1920, 1920, 1080))
    }

    @Test
    fun casSansAmbiguite() {
        assertEquals(0, Orientation.rotationToApply(0, 1080, 1920, 1920, 1080))
        assertEquals(180, Orientation.rotationToApply(180, 1920, 1080, 1920, 1080))
        assertEquals(90, Orientation.rotationToApply(90, 1080, 1080, 1080, 1080)) // carré : indécidable, on applique
        assertEquals(90, Orientation.rotationToApply(90, 1080, 1920, 0, 0)) // dimensions annoncées inconnues
    }
}
