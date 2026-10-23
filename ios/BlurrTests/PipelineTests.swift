import AVFoundation
import BlurrCore
import XCTest
@testable import Blurr

/// Chaîne complète (analyse, export, contrôle) sur des vidéos fabriquées en code, dans le simulateur iOS.
final class PipelineTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var outputDir: URL { dir.appendingPathComponent("sortie", isDirectory: true) }

    private func source(_ spec: SyntheticVideo.Spec) async throws -> VideoInfo {
        let url = dir.appendingPathComponent("source-\(UUID().uuidString).mov")
        try SyntheticVideo.make(spec, at: url)
        return try await VideoProbe.read(url: url, name: "IMG_0001.MOV")
    }

    private func process(_ info: VideoInfo, options: Options = Options(), verify: Bool = true, cancel: CancelToken = CancelToken()) async throws -> PipelineOutput {
        try await Pipeline.process(info: info, options: options, verify: verify, outputDirectory: outputDir, cancel: cancel) { _, _, _ in }
    }

    private func assertNoLocation(_ url: URL, file: StaticString = #filePath, line: UInt = #line) async throws {
        let metadata = try await AVURLAsset(url: url).load(.metadata)
        for item in metadata {
            let id = item.identifier?.rawValue ?? ""
            XCTAssertFalse(id.lowercased().contains("location"), "métadonnée de position : \(id)", file: file, line: line)
        }
    }

    func testChaineCompleteAvecVisage() async throws {
        guard let face = SyntheticVideo.faceImage() else {
            throw XCTSkip("Image de test absente (Fixtures/face.jpg, téléchargée par la compilation).")
        }
        let spec = SyntheticVideo.Spec(frames: 60, face: face)
        let info = try await source(spec)
        XCTAssertEqual(info.displayWidth, 640)
        XCTAssertEqual(info.frameRate, 30, accuracy: 0.5)
        let out = try await process(info)

        XCTAssertEqual(out.fileName, "IMG_0001_blurr.mp4")
        XCTAssertEqual(out.report.analyzedFrames, 60)
        XCTAssertEqual(out.report.exportedFrames, 60)
        XCTAssertGreaterThanOrEqual(out.report.plan.confirmedTracks, 1)
        XCTAssertGreaterThanOrEqual(out.report.plan.maskedFrames, 55)
        XCTAssertEqual(out.report.verifiedFrames, 60)
        XCTAssertEqual(out.report.flaggedFrames, 0, "instants signalés : \(out.report.flaggedTimes)")
        XCTAssertEqual(out.report.audio, "copié sans ré-encodage")
        XCTAssertFalse(out.report.needsAttention)

        let produced = try await VideoProbe.read(url: out.url, name: out.fileName)
        XCTAssertEqual(produced.displayWidth, 640)
        XCTAssertEqual(produced.displayHeight, 360)
        XCTAssertEqual(produced.codec, "avc1")
        XCTAssertTrue(produced.hasAudio)
        XCTAssertEqual(Double(produced.durationUs) / 1e6, 2.0, accuracy: 0.1)

        // Centre du visage (à l'intérieur de l'ellipse) : texture effacée. Bas de l'image, loin du visage : conservé
        // (à la compression près).
        let srcFrame = try await SyntheticVideo.frame(of: info.url, at: 1.0)
        let outFrame = try await SyntheticVideo.frame(of: out.url, at: 1.0)
        let faceCore = SyntheticVideo.faceRect(spec, frame: 30).insetBy(dx: 80, dy: 80)
        let before = SyntheticVideo.stats(srcFrame, faceCore)
        let after = SyntheticVideo.stats(outFrame, faceCore)
        XCTAssertLessThan(after.std, before.std * 0.5, "écart type avant \(before.std), après \(after.std)")
        let background = CGRect(x: 0, y: 310, width: 640, height: 50)
        XCTAssertEqual(SyntheticVideo.stats(srcFrame, background).mean, SyntheticVideo.stats(outFrame, background).mean, accuracy: 8)
        try await assertNoLocation(out.url)

        // Même source, masque noir : le centre du visage est noir.
        let black = try await process(info, options: Options(style: .black), verify: false)
        let blackFrame = try await SyntheticVideo.frame(of: black.url, at: 1.0)
        let dark = SyntheticVideo.stats(blackFrame, faceCore)
        XCTAssertLessThan(dark.mean, 20, "luminance moyenne \(dark.mean)")
        XCTAssertGreaterThanOrEqual(black.report.plan.confirmedTracks, 1)
    }

    func testVideoPortraitTransformationConservee() async throws {
        let face = SyntheticVideo.faceImage()
        var spec = SyntheticVideo.Spec(frames: 30, face: face)
        spec.portrait = true
        let info = try await source(spec)
        XCTAssertEqual(info.orientation.rotationDegrees, 90)
        XCTAssertEqual(info.codedWidth, 360)
        let out = try await process(info)
        let produced = try await VideoProbe.read(url: out.url, name: out.fileName)
        XCTAssertEqual(produced.orientation, info.orientation)
        XCTAssertEqual(produced.displayWidth, 640)
        XCTAssertEqual(produced.displayHeight, 360)
        XCTAssertEqual(out.report.exportedFrames, 30)
        if face != nil {
            XCTAssertGreaterThanOrEqual(out.report.plan.confirmedTracks, 1)
            XCTAssertEqual(out.report.flaggedFrames, 0, "instants signalés : \(out.report.flaggedTimes)")
            // Le flou est au bon endroit dans l'image affichée (masques convertis dans le repère codé).
            let srcFrame = try await SyntheticVideo.frame(of: info.url, at: 0.5)
            let outFrame = try await SyntheticVideo.frame(of: out.url, at: 0.5)
            let faceCore = SyntheticVideo.faceRect(spec, frame: 15).insetBy(dx: 80, dy: 80)
            let before = SyntheticVideo.stats(srcFrame, faceCore)
            let after = SyntheticVideo.stats(outFrame, faceCore)
            XCTAssertLessThan(after.std, before.std * 0.5, "écart type avant \(before.std), après \(after.std)")
        }
    }

    func testSansVisageNiSonAvecMasqueNoir() async throws {
        let info = try await source(SyntheticVideo.Spec(frames: 20, face: nil, audio: false))
        XCTAssertFalse(info.hasAudio)
        let out = try await process(info, options: Options(style: .black))
        XCTAssertEqual(out.report.plan.confirmedTracks, 0)
        XCTAssertTrue(out.report.needsAttention)
        XCTAssertEqual(out.report.audio, "aucun")
        let produced = try await VideoProbe.read(url: out.url, name: out.fileName)
        XCTAssertFalse(produced.hasAudio)
        XCTAssertEqual(out.report.exportedFrames, 20)
    }

    func testSonCoupeSurDemande() async throws {
        let info = try await source(SyntheticVideo.Spec(frames: 15, face: nil, audio: true))
        XCTAssertTrue(info.hasAudio)
        let out = try await process(info, options: Options(keepAudio: false), verify: false)
        XCTAssertEqual(out.report.audio, "coupé")
        XCTAssertNil(out.report.verifiedFrames)
        let produced = try await VideoProbe.read(url: out.url, name: out.fileName)
        XCTAssertFalse(produced.hasAudio)
    }

    func testAnnulationNeLaisseAucunFichier() async throws {
        let info = try await source(SyntheticVideo.Spec(frames: 30, face: nil, audio: true))
        let token = CancelToken()
        token.cancel()
        do {
            _ = try await process(info, cancel: token)
            XCTFail("le traitement aurait dû être annulé")
        } catch is CancelledError {
            // attendu
        }
        let produced = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
        XCTAssertTrue(produced.isEmpty, "\(produced)")
    }

    func testNomUniqueQuandLeFichierExisteDeja() async throws {
        let info = try await source(SyntheticVideo.Spec(frames: 10, face: nil, audio: false))
        let first = try await process(info, verify: false)
        let second = try await process(info, verify: false)
        XCTAssertEqual(first.fileName, "IMG_0001_blurr.mp4")
        XCTAssertEqual(second.fileName, "IMG_0001_blurr (2).mp4")
    }
}
