import AVFoundation
import BlurrCore
import CoreVideo
import XCTest
@testable import Blurr

/// Pont Objective-C++ vers le moteur C++ : rendu et détection sur des tampons d'images réels (simulateur iOS).
final class EngineTests: XCTestCase {

    private func makeBuffer(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let (b, g, r) = fill(x, y)
                let p = y * bpr + x * 4
                base[p] = b
                base[p + 1] = g
                base[p + 2] = r
                base[p + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let p = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return [base[p], base[p + 1], base[p + 2], base[p + 3]]
    }

    func testMasqueNoirCouvreLaBoiteEtLaisseLeResteIntact() {
        let buffer = makeBuffer(width: 200, height: 200) { _, _ in (200, 200, 200) }
        let renderer = BLRMaskRenderer(width: 200, height: 200, black: true)
        // Boîte de visage 0,4..0,6 ; ellipse x 1,6.
        let ellipses: [Float] = [0.5, 0.5, 0.1 * 1.6, 0.1 * 1.6]
        let drawn = ellipses.withUnsafeBufferPointer { renderer.apply(pixelBuffer: buffer, ellipses: $0.baseAddress, count: 1) }
        XCTAssertEqual(drawn, 1)
        for (x, y) in [(80, 80), (119, 119), (100, 100), (80, 119)] {
            XCTAssertEqual(Array(pixel(buffer, x, y).prefix(3)), [0, 0, 0], "(\(x), \(y))")
            XCTAssertEqual(pixel(buffer, x, y)[3], 255)
        }
        XCTAssertEqual(pixel(buffer, 5, 5), [200, 200, 200, 255])
        XCTAssertEqual(renderer.maskedFrames, 1)
    }

    func testFlouEffaceUnDamierFin() {
        let buffer = makeBuffer(width: 400, height: 400) { x, y in ((x + y) / 2 % 2 == 0) ? (255, 255, 255) : (0, 0, 0) }
        let renderer = BLRMaskRenderer(width: 400, height: 400, black: false)
        let ellipses: [Float] = [0.5, 0.5, 0.125 * 1.6, 0.125 * 1.6]
        _ = ellipses.withUnsafeBufferPointer { renderer.apply(pixelBuffer: buffer, ellipses: $0.baseAddress, count: 1) }
        var values: [Double] = []
        for y in stride(from: 175, to: 225, by: 3) {
            for x in stride(from: 175, to: 225, by: 3) { values.append(Double(pixel(buffer, x, y)[1])) }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let std = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
        XCTAssertLessThan(std, 3.0)
        XCTAssertEqual(mean, 127.5, accuracy: 10)
        // Coin éloigné : intact.
        XCTAssertEqual(pixel(buffer, 0, 0), [255, 255, 255, 255])
    }

    func testImageSansEllipseInchangee() {
        let buffer = makeBuffer(width: 64, height: 48) { x, y in (UInt8(x * 3), UInt8(y * 5), 77) }
        let renderer = BLRMaskRenderer(width: 64, height: 48, black: false)
        XCTAssertEqual(renderer.apply(pixelBuffer: buffer, ellipses: nil, count: 0), 0)
        XCTAssertEqual(pixel(buffer, 10, 20), [30, 100, 77, 255])
        XCTAssertEqual(renderer.frames, 1)
        XCTAssertEqual(renderer.maskedFrames, 0)
    }

    func testModeleEmbarqueEtVersionOpenCV() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: Pipeline.modelPath), Pipeline.modelPath)
        XCTAssertTrue(BLREngineInfo.openCVVersion().hasPrefix("4."), BLREngineInfo.openCVVersion())
        XCTAssertNoThrow(try BLRFaceDetector(modelPath: Pipeline.modelPath, scoreThreshold: 0.5))
        XCTAssertThrowsError(try BLRFaceDetector(modelPath: "/inexistant.onnx", scoreThreshold: 0.5))
    }

    func testExceptionObjectiveCConvertieEnErreur() {
        XCTAssertThrowsError(try BLREngineInfo.catchingExceptions {
            NSException(name: .invalidArgumentException, reason: "test", userInfo: nil).raise()
        })
        XCTAssertNoThrow(try BLREngineInfo.catchingExceptions {})
    }

    /// Détection sur le visage de test, puis même image codée tournée d'un quart de tour : les boîtes renvoyées
    /// (repère affiché) doivent coïncider. Vérifie la cohérence entre le redressement C++ et DisplayOrientation.
    func testDetectionDuVisageEtRedressement() async throws {
        guard let face = SyntheticVideo.faceImage() else {
            throw XCTSkip("Image de test absente (Fixtures/face.jpg, téléchargée par la compilation).")
        }
        var spec = SyntheticVideo.Spec(face: face)
        spec.portrait = true
        spec.frames = 1
        spec.audio = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("detect-\(UUID().uuidString).mov")
        try SyntheticVideo.make(spec, at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try await VideoProbe.read(url: url, name: "test.mov")
        XCTAssertEqual(info.orientation.rotationDegrees, 90)
        XCTAssertEqual(info.displayWidth, 640)
        XCTAssertEqual(info.displayHeight, 360)

        // Lecture du tampon codé (portrait stocké en paysage) par le lecteur de l'application.
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = try FrameReading.addVideoOutput(to: reader, track: track, copiesSampleData: false)
        try FrameReading.start(reader)
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let pb = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertEqual(CVPixelBufferGetWidth(pb), 360)
        let detector = try BLRFaceDetector(modelPath: Pipeline.modelPath, scoreThreshold: 0.5)
        let data = try XCTUnwrap(detector.detect(pixelBuffer: pb, maxSide: 1280, mirrored: info.orientation.isMirrored,
                                                 rotation: Int32(info.orientation.rotationDegrees)))
        reader.cancelReading()
        let found = FaceParsing.boxes(from: data)
        let best = try XCTUnwrap(found.max { $0.score < $1.score }, "aucun visage détecté")
        XCTAssertGreaterThan(best.score, 0.7)
        // Position attendue dans l'image affichée : rectangle du visage dessiné sur l'image 0.
        let r = SyntheticVideo.faceRect(spec, frame: 0)
        XCTAssertEqual(best.x + best.w / 2, Float(r.midX / 640), accuracy: 0.08)
        XCTAssertEqual(best.y + best.h / 2, Float(r.midY / 360), accuracy: 0.12)
    }
}

