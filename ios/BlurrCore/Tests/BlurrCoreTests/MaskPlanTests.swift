import XCTest
@testable import BlurrCore

/// Portage des 20 tests de `MaskPlanTest.kt` (Android v0.2).
final class MaskPlanTests: XCTestCase {

    private let frameUs: Int64 = 33_333

    /// Paramètres de test : confirmation à 0,8, une seule détection suffit, prolongation par les scores >= 0,3.
    private let params = TrackingParams(keepThreshold: 0.3, confirmThreshold: 0.8, minHits: 1, maxGapUs: 300_000)

    private func box(_ x: Float, _ y: Float, _ w: Float = 0.1, _ h: Float = 0.1, score: Float = 0.9) -> FaceBox {
        FaceBox(x: x, y: y, w: w, h: h, score: score)
    }

    /// n images à 30 i/s, avec des visages aux indices donnés.
    private func detections(_ n: Int, _ withFace: [Int: [FaceBox]], firstPts: Int64 = 0) -> Detections {
        let d = Detections()
        for i in 0..<n { d.add(ptsUs: firstPts + Int64(i) * frameUs, faces: withFace[i] ?? []) }
        return d
    }

    private func build(_ d: Detections, p: TrackingParams? = nil, scale: Float = 1.6, margin: Int = 0, union: Int = 0) -> MaskPlan {
        MaskPlan.build(detections: d, params: p ?? params, maskScale: scale, marginFrames: margin, aspect: 1, unionFrames: union)
    }

    private func masked(_ plan: MaskPlan, _ i: Int) -> Bool { !plan.lookup(Int64(i) * frameUs).isEmpty }

    private func with(_ p: TrackingParams, minHits: Int? = nil, maxGapUs: Int64? = nil) -> TrackingParams {
        var q = p
        if let m = minHits { q.minHits = m }
        if let g = maxGapUs { q.maxGapUs = g }
        return q
    }

    func testGeometrieDeLEllipse() {
        let d = detections(1, [0: [box(0.4, 0.3, 0.2, 0.2)]])
        let e = build(d).lookup(0)
        XCTAssertEqual(e.count, 4)
        XCTAssertEqual(e[0], 0.5, accuracy: 1e-5) // centre x
        XCTAssertEqual(e[1], 0.4, accuracy: 1e-5) // centre y
        XCTAssertEqual(e[2], 0.16, accuracy: 1e-5) // demi-axe x = 0,2 x 1,6 / 2
        XCTAssertEqual(e[3], 0.16, accuracy: 1e-5)
    }

    func testDetectionIsoleeDeScoreMoyenEcartee() {
        // Score 0,6 : au-dessus du seuil de conservation, sous le seuil de confirmation.
        let d = detections(5, [2: [box(0.1, 0.1, score: 0.6)]])
        let plan = build(d, margin: 3)
        for i in 0..<5 { XCTAssertFalse(masked(plan, i), "image \(i)") }
        XCTAssertEqual(plan.stats.tracks, 1)
        XCTAssertEqual(plan.stats.confirmedTracks, 0)
    }

    func testPisteConfirmeeMasqueeAussiSurSesDetectionsFaibles() {
        // Le même visage : score 0,45 sur les images 0 à 3, 0,9 sur l'image 4, puis 0,45.
        var faces: [Int: [FaceBox]] = [:]
        for i in 0..<8 { faces[i] = [box(0.3 + Float(i) * 0.005, 0.3, score: i == 4 ? 0.9 : 0.45)] }
        let plan = build(detections(8, faces))
        for i in 0..<8 { XCTAssertTrue(masked(plan, i), "image \(i)") }
        XCTAssertEqual(plan.stats.tracks, 1)
        XCTAssertEqual(plan.stats.confirmedTracks, 1)
    }

    func testNombreMinimalDeDetections() {
        let d = detections(3, [1: [box(0.1, 0.1, score: 0.95)]])
        XCTAssertTrue(masked(build(d, p: with(params, minHits: 1)), 1))
        XCTAssertFalse(masked(build(d, p: with(params, minHits: 2)), 1))
    }

    func testScoresSousLeSeuilDeConservationIgnores() {
        // 0,2 < 0,3 : ne prolonge pas la piste et ne compte pas comme détection.
        let faces: [Int: [FaceBox]] = [0: [box(0.3, 0.3, score: 0.9)], 1: [box(0.3, 0.3, score: 0.2)]]
        let plan = build(detections(2, faces))
        XCTAssertTrue(masked(plan, 0))
        XCTAssertFalse(masked(plan, 1))
    }

    func testTrouInterpole() {
        // Détections aux images 0 et 4, rien entre : la boîte suit le déplacement de 0,1 à 0,25.
        let faces: [Int: [FaceBox]] = [0: [box(0.1, 0.5)], 4: [box(0.25, 0.5)]]
        let plan = build(detections(5, faces), p: with(params, maxGapUs: 200_000), scale: 1)
        for i in 0..<5 { XCTAssertTrue(masked(plan, i), "image \(i)") }
        let mid = plan.lookup(2 * frameUs)
        XCTAssertEqual(mid.count, 4)
        XCTAssertEqual(mid[0], 0.225, accuracy: 1e-4) // centre x : 0,15 -> 0,30, à mi-chemin
    }

    func testTrouTropLongNonComble() {
        // 10 images d'écart (333 ms) au-delà de 300 ms : deux pistes, rien entre elles.
        let faces: [Int: [FaceBox]] = [0: [box(0.1, 0.5)], 10: [box(0.1, 0.5)]]
        let plan = build(detections(11, faces))
        XCTAssertEqual(plan.stats.tracks, 2)
        XCTAssertTrue(masked(plan, 0))
        XCTAssertTrue(masked(plan, 10))
        for i in 1...9 { XCTAssertFalse(masked(plan, i), "image \(i)") }
    }

    func testDetectionLointaineNeRejointPasLaPiste() {
        // Une détection faible loin du visage confirmé forme sa propre piste, non confirmée.
        let faces: [Int: [FaceBox]] = [
            0: [box(0.1, 0.1, score: 0.9)],
            1: [box(0.1, 0.1, score: 0.9), box(0.7, 0.7, score: 0.5)],
        ]
        let plan = build(detections(2, faces))
        XCTAssertEqual(plan.stats.tracks, 2)
        XCTAssertEqual(plan.stats.confirmedTracks, 1)
        XCTAssertEqual(plan.lookup(frameUs).count, 4)
    }

    func testMargeEnImagesAvantEtApres() {
        let d = detections(11, [5: [box(0.1, 0.1)]])
        let plan = build(d, margin: 3)
        for i in 0..<11 { XCTAssertEqual(masked(plan, i), (2...8).contains(i), "image \(i)") }
    }

    func testSansMargeSeuleLImageDetecteeEstMasquee() {
        let d = detections(5, [2: [box(0.1, 0.1)]])
        let plan = build(d)
        for i in 0..<5 { XCTAssertEqual(masked(plan, i), i == 2) }
    }

    func testDeuxVisagesSimultanes() {
        let d = detections(1, [0: [box(0.1, 0.1), box(0.6, 0.6)]])
        XCTAssertEqual(build(d).lookup(0).count, 8)
    }

    func testUnionAvecLesImagesVoisines() {
        // Visage en mouvement rapide : sur l'image 1, la boîte couvre aussi les positions des images 0 et 2.
        var faces: [Int: [FaceBox]] = [:]
        for i in 0..<3 { faces[i] = [box(0.2 + Float(i) * 0.05, 0.5)] }
        let e = build(detections(3, faces), scale: 1, union: 1).lookup(frameUs)
        XCTAssertEqual(e.count, 4)
        XCTAssertEqual(e[0], 0.3, accuracy: 1e-4) // centre de [0,2 ; 0,4]
        XCTAssertEqual(e[2], 0.1, accuracy: 1e-4) // demi-largeur 0,2 / 2
    }

    func testToleranceTemporelle() {
        let d = detections(3, [1: [box(0.1, 0.1)]])
        let plan = build(d)
        // Un léger écart d'horodatage retombe sur l'image la plus proche.
        XCTAssertFalse(plan.lookup(frameUs + 8_000).isEmpty)
        XCTAssertFalse(plan.lookup(frameUs - 8_000).isEmpty)
        // Très loin de toute image analysée : rien.
        XCTAssertEqual(plan.lookup(60_000_000).count, 0)
        XCTAssertEqual(plan.lookup(-60_000_000).count, 0)
    }

    func testOrdreDePresentationRetabliSiLaSourceLivreDansUnAutreOrdre() {
        let d = Detections()
        d.add(ptsUs: 2 * frameUs, faces: [box(0.7, 0.7)])
        d.add(ptsUs: 0, faces: [box(0.1, 0.1)])
        d.add(ptsUs: frameUs, faces: [])
        let plan = build(d, p: with(params, maxGapUs: 10_000), scale: 1)
        XCTAssertEqual(plan.lookup(0)[0], 0.15, accuracy: 1e-5)
        XCTAssertEqual(plan.lookup(frameUs).count, 0)
        XCTAssertEqual(plan.lookup(2 * frameUs)[0], 0.75, accuracy: 1e-5)
    }

    func testCalageDeLHorlogeSurLaPremiereImageExportee() {
        // L'analyse part à 66 666 us (premier échantillon du fichier), l'export à 0.
        let d = detections(4, [0: [box(0.1, 0.1)]], firstPts: 66_666)
        let plan = build(d)
        let shift = plan.alignTo(0)
        XCTAssertEqual(shift, 66_666)
        XCTAssertEqual(plan.appliedShiftUs, 66_666)
        XCTAssertFalse(plan.lookup(0).isEmpty)
        XCTAssertEqual(plan.lookup(2 * frameUs).count, 0)
        // Contrôle du fichier produit : décalage explicite, sans toucher à celui de l'export.
        XCTAssertFalse(plan.lookupShifted(1_000, shift: plan.shiftFor(1_000)).isEmpty)
        XCTAssertEqual(plan.appliedShiftUs, 66_666)
    }

    func testDecalageAbsurdeIgnore() {
        let d = detections(2, [0: [box(0.1, 0.1)]], firstPts: 0)
        let plan = build(d)
        XCTAssertEqual(plan.alignTo(10_000_000), 0) // 10 s : au-delà de la limite de 2 s
        XCTAssertFalse(plan.lookup(0).isEmpty)
    }

    func testPlanVide() {
        let plan = MaskPlan.build(detections: Detections(), params: params, maskScale: 1.6, marginFrames: 5)
        XCTAssertEqual(plan.frameCount, 0)
        XCTAssertEqual(plan.alignTo(123), 0)
        XCTAssertEqual(plan.lookup(0), [])
    }

    func testToleranceSAdapteAuxCadencesLentes() {
        // 5 i/s (200 ms entre images) : la tolérance doit couvrir la moitié de l'écart, au minimum.
        let d = Detections()
        for i in 0..<4 { d.add(ptsUs: Int64(i) * 200_000, faces: i == 1 ? [box(0.1, 0.1)] : []) }
        let plan = build(d)
        XCTAssertFalse(plan.lookup(200_000 + 90_000).isEmpty)
    }

    func testDistanceTientCompteDuFormatDeLImage() {
        // En 16/9, un écart horizontal normalisé de 0,05 vaut 0,089 en unités de hauteur.
        let a = box(0.1, 0.1, 0.05, 0.09)
        let b = box(0.15, 0.1, 0.05, 0.09)
        let d = MaskPlan.distance(a, b, aspect: 16.0 / 9.0)
        XCTAssertEqual(d, 0.0889 / 0.0894, accuracy: 1e-2)
    }

    func testPreReglagesOrdonnes() {
        let n = Sensitivity.normal.params
        let h = Sensitivity.high.params
        let m = Sensitivity.max.params
        XCTAssertTrue(n.confirmThreshold > h.confirmThreshold && h.confirmThreshold > m.confirmThreshold)
        XCTAssertTrue(n.keepThreshold >= h.keepThreshold && h.keepThreshold >= m.keepThreshold)
        XCTAssertTrue(m.keepThreshold <= m.confirmThreshold)
    }

    // ------------------------------------------------------------------ propres à iOS

    func testPreReglagesIdentiquesAAndroid() {
        XCTAssertEqual(Sensitivity.normal.params, TrackingParams(keepThreshold: 0.5, confirmThreshold: 0.85, minHits: 2))
        XCTAssertEqual(Sensitivity.high.params, TrackingParams(keepThreshold: 0.4, confirmThreshold: 0.7, minHits: 2))
        XCTAssertEqual(Sensitivity.max.params, TrackingParams(keepThreshold: 0.3, confirmThreshold: 0.5, minHits: 1))
        let o = Options()
        XCTAssertEqual(o.analysisMaxSide, 1280)
        XCTAssertEqual(o.sensitivity, .high)
        XCTAssertEqual(o.style, .blur)
        XCTAssertEqual(o.maskScale, 1.6)
        XCTAssertEqual(o.marginFrames, 5)
        XCTAssertEqual(o.unionFrames, 1)
    }

    func testTailleDAnalyseCommeAndroid() {
        XCTAssertTrue(analysisSize(width: 1920, height: 1080, maxSide: 1280) == (1280, 720))
        XCTAssertTrue(analysisSize(width: 1080, height: 1920, maxSide: 960) == (540, 960))
        XCTAssertTrue(analysisSize(width: 640, height: 360, maxSide: 1280) == (640, 360))
        // 3840 x 2160 -> 1920 x 1080 ; 1366 x 768 à 960 : 768 x 0,7028 = 539,7 -> 540.
        XCTAssertTrue(analysisSize(width: 3840, height: 2160, maxSide: 1920) == (1920, 1080))
        XCTAssertTrue(analysisSize(width: 1366, height: 768, maxSide: 960) == (960, 540))
    }
}
