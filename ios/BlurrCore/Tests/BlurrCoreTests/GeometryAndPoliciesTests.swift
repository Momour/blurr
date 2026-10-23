import XCTest
@testable import BlurrCore

/// Portage de `BlurGeometryTest.kt` et de `PoliciesTest.kt` (Android v0.2), hors éléments propres à Android
/// (shaders GLSL, nom de dossier MediaStore).
final class GeometryAndPoliciesTests: XCTestCase {

    // ------------------------------------------------------------------ géométrie du flou

    func testCoinsDeLaBoiteEntierementCouverts() {
        // Ellipse = boîte x 1,6 : les coins de la boîte sont au rayon normalisé racine(2) / 1,6.
        let corner = Float(2).squareRoot() / 1.6
        XCTAssertEqual(BlurGeometry.coverage(corner), 1)
        XCTAssertEqual(BlurGeometry.coverage(0), 1)
        XCTAssertEqual(BlurGeometry.coverage(1), 0)
        XCTAssertEqual(BlurGeometry.coverage(1.2), 0)
        XCTAssertEqual(BlurGeometry.coverage((BlurGeometry.edgeStart + 1) / 2), 0.5, accuracy: 1e-5)
    }

    func testNiveauProportionnelALaTailleDuVisage() {
        // Ellipse de 128 px de diamètre : cellules de 128 / 8 = 16 px, niveau 4.
        XCTAssertEqual(BlurGeometry.level(64, 50), 4, accuracy: 1e-5)
        XCTAssertEqual(BlurGeometry.level(128, 100), 5, accuracy: 1e-5)
        XCTAssertEqual(BlurGeometry.level(30, 64), 4, accuracy: 1e-5)
    }

    func testNiveauBorne() {
        XCTAssertEqual(BlurGeometry.level(2, 2), BlurGeometry.minLevel)
        XCTAssertEqual(BlurGeometry.level(1e7, 1e7), Float(BlurGeometry.maxLevels - 1))
        XCTAssertTrue(BlurGeometry.lowerLevel(BlurGeometry.level(1e7, 1e7)) + 1 <= BlurGeometry.maxLevels)
        XCTAssertEqual(BlurGeometry.level(0, 0), BlurGeometry.minLevel)
    }

    func testCinqCellulesSurLaBoiteDuVisage() {
        // Boîte de 100 px, ellipse x 1,6 : demi-axe 80 px. Taille de cellule 2^niveau = 100 / 5 = 20 px.
        let level = BlurGeometry.level(80, 80)
        XCTAssertEqual(pow(2.0, Double(level)), 20.0, accuracy: 1e-3)
    }

    func testTaillesDeLaPyramide() {
        XCTAssertEqual(BlurGeometry.levelSize(1920, 1), 960)
        XCTAssertEqual(BlurGeometry.levelSize(1080, 1), 540)
        XCTAssertEqual(BlurGeometry.levelSize(1080, 2), 270)
        XCTAssertEqual(BlurGeometry.levelSize(1080, 4), 68) // 1080 -> 540 -> 270 -> 135 -> 68
        XCTAssertEqual(BlurGeometry.levelSize(1080, 11), 1)
        XCTAssertEqual(BlurGeometry.levelSize(1920, 0), 1920)
    }

    func testControleIgnoreLesVisagesDansUneZoneMasquee() {
        let ellipses: [Float] = [0.5, 0.5, 0.1, 0.1]
        XCTAssertTrue(Verification.isInside(FaceBox(x: 0.45, y: 0.45, w: 0.1, h: 0.1, score: 0.9), ellipses))
        XCTAssertFalse(Verification.isInside(FaceBox(x: 0.8, y: 0.8, w: 0.1, h: 0.1, score: 0.9), ellipses))
        XCTAssertFalse(Verification.isInside(FaceBox(x: 0.45, y: 0.45, w: 0.1, h: 0.1, score: 0.9), []))
    }

    func testSeuilEtEchantillonnageDuControle() {
        XCTAssertEqual(Verification.threshold(for: Sensitivity.normal.params), 0.85)
        XCTAssertEqual(Verification.threshold(for: Sensitivity.high.params), 0.7)
        XCTAssertEqual(Verification.threshold(for: Sensitivity.max.params), 0.6)
        // 18 s à 60 i/s : 1 080 images, une sur 1.
        XCTAssertTrue(Verification.sampling(durationUs: 18_000_000, frameRate: 60) == (1080, 1))
        // 10 min à 30 i/s : 18 000 images, une sur 30 (600 images relues).
        XCTAssertTrue(Verification.sampling(durationUs: 600_000_000, frameRate: 30) == (18_000, 30))
        // Cadence inconnue : 30 i/s supposées.
        XCTAssertTrue(Verification.sampling(durationUs: 1_000_000, frameRate: 0) == (30, 1))
    }

    // ------------------------------------------------------------------ encodage et noms

    func testDebitDeLaSourceReprisTelQuelDansLaPlage() {
        XCTAssertEqual(EncodingPolicy.videoBitrate(width: 1920, height: 1080, frameRate: 30, sourceBitrate: 12_000_000), 12_000_000)
    }

    func testDebitBorne() {
        XCTAssertEqual(EncodingPolicy.videoBitrate(width: 3840, height: 2160, frameRate: 60, sourceBitrate: 400_000_000), EncodingPolicy.maxBitrate)
        XCTAssertEqual(EncodingPolicy.videoBitrate(width: 640, height: 360, frameRate: 30, sourceBitrate: 300_000), EncodingPolicy.minBitrate)
    }

    func testDebitEstimeQuandLaSourceNeLeDonnePas() {
        // 1920 x 1080 x 30 x 0,10 = 6 220 800
        XCTAssertEqual(EncodingPolicy.videoBitrate(width: 1920, height: 1080, frameRate: 30, sourceBitrate: 0), 6_220_800)
        // Cadence inconnue : 30 i/s supposées.
        XCTAssertEqual(EncodingPolicy.videoBitrate(width: 1920, height: 1080, frameRate: 0, sourceBitrate: 0), 6_220_800)
    }

    func testTailleEstimee() {
        // (8 000 000 + 320 000) / 8 x 10 s = 10 400 000 octets
        XCTAssertEqual(EncodingPolicy.estimatedOutputBytes(durationUs: 10_000_000, videoBitrate: 8_000_000), 10_400_000)
        XCTAssertEqual(EncodingPolicy.estimatedOutputBytes(durationUs: 0, videoBitrate: 8_000_000), 0)
        XCTAssertEqual(EncodingPolicy.requiredFreeBytes(durationUs: 10_000_000, videoBitrate: 8_000_000), 20_800_000 + 52_428_800)
    }

    func testNomDeSortie() {
        XCTAssertEqual(OutputNaming.outputName("vacances.MOV"), "vacances_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName("a/b/c.mp4"), "c_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName("sans_extension"), "sans_extension_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName(""), "video_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName(".."), "video_blurr.mp4")
        // ':', '*' et '?' deviennent chacun '_' ; le suffixe "_blurr" s'y ajoute.
        XCTAssertEqual(OutputNaming.outputName("a:b*?.mp4"), "a_b___blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName("a.b.c.mp4"), "a.b.c_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName("IMG_1234.MOV"), "IMG_1234_blurr.mp4")
        XCTAssertEqual(OutputNaming.outputName("été à Alger.mov"), "été à Alger_blurr.mp4")
    }

    func testNomDeSortieLongTronque() {
        let name = OutputNaming.outputName(String(repeating: "x", count: 300) + ".mp4")
        XCTAssertTrue(name.count <= 80 + "_blurr.mp4".count)
        XCTAssertTrue(name.hasSuffix("_blurr.mp4"))
    }

    func testNomUnique() {
        let existing: Set<String> = ["a_blurr.mp4", "a_blurr (2).mp4"]
        XCTAssertEqual(OutputNaming.uniqueName("a_blurr.mp4") { existing.contains($0) }, "a_blurr (3).mp4")
        XCTAssertEqual(OutputNaming.uniqueName("b_blurr.mp4") { existing.contains($0) }, "b_blurr.mp4")
    }

    func testResumeDesDetections() {
        let d = Detections()
        d.add(ptsUs: 0, faces: [])
        d.add(ptsUs: 33_333, faces: [FaceBox(x: 0.1, y: 0.1, w: 0.1, h: 0.1, score: 0.9), FaceBox(x: 0.5, y: 0.5, w: 0.1, h: 0.1, score: 0.8)])
        d.add(ptsUs: 66_666, faces: [FaceBox(x: 0.1, y: 0.1, w: 0.1, h: 0.1, score: 0.9)])
        XCTAssertEqual(d.size, 3)
        XCTAssertEqual(d.totalFaces, 3)
        XCTAssertEqual(d.framesWithFaces, 2)
        d.clear()
        XCTAssertEqual(d.size, 0)
    }

    func testBilanSignaleUneVideoSansMasque() {
        let report = ProcessingReport(
            analyzedFrames: 100, framesWithFaces: 10, detections: 12,
            plan: MaskPlan.Stats(tracks: 3, confirmedTracks: 0, maskedFrames: 0), exportedFrames: 100,
            verifiedFrames: 100, flaggedFrames: 0, flaggedTimes: [], audio: "copié sans ré-encodage", hdrConverted: false
        )
        XCTAssertTrue(report.needsAttention)
        XCTAssertTrue(report.lines().contains { $0.hasPrefix("ATTENTION : aucun visage confirmé") })
        XCTAssertFalse(report.frameMismatch)
    }

    func testBilanSignaleLesInstantsDuControle() {
        let report = ProcessingReport(
            analyzedFrames: 1080, framesWithFaces: 900, detections: 4000,
            plan: MaskPlan.Stats(tracks: 800, confirmedTracks: 400, maskedFrames: 916), exportedFrames: 1080,
            verifiedFrames: 1080, flaggedFrames: 2, flaggedTimes: [11.633, 72.5], audio: "aucun", hdrConverted: true
        )
        let text = report.lines().joined(separator: "\n")
        XCTAssertTrue(text.contains("0:11.633"))
        XCTAssertTrue(text.contains("1:12.500"))
        XCTAssertTrue(text.contains("Vidéo HDR convertie en SDR."))
        XCTAssertTrue(report.needsAttention)
    }
}
