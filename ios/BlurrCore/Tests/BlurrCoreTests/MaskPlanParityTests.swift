import Foundation
import XCTest
@testable import BlurrCore

/// Parité du plan de masquage avec la version PC (Python), elle-même alignée sur Android v0.2 : mêmes détections
/// synthétiques (`Fixtures/maskplan-parity.json`, produit par `ios/Tools/make_parity_fixture.py`), mêmes pistes,
/// mêmes images masquées, mêmes ellipses, pour les trois sensibilités.
final class MaskPlanParityTests: XCTestCase {

    private struct Fixture: Decodable {
        let schema: String
        let aspect: Double
        let mask_scale: Double
        let margin_frames: Int
        let union_frames: Int
        let times: [Int64]
        let faces: [[[String]]]
        let plans: [String: Plan]

        struct Plan: Decodable {
            let stats: [Int]
            let ellipses: [[String]]
        }
    }

    private func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "maskplan-parity", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testPlanIdentiqueALaVersionPC() throws {
        let fx = try loadFixture()
        XCTAssertEqual(fx.schema, "blurr-maskplan-parity/1")
        let d = Detections()
        for (i, t) in fx.times.enumerated() {
            let boxes = fx.faces[i].map { v in
                FaceBox(x: Float(v[0])!, y: Float(v[1])!, w: Float(v[2])!, h: Float(v[3])!, score: Float(v[4])!)
            }
            d.add(ptsUs: t, faces: boxes)
        }
        XCTAssertGreaterThan(d.totalFaces, 500)

        for s in Sensitivity.allCases {
            let expected = try XCTUnwrap(fx.plans[s.rawValue], s.rawValue)
            let plan = MaskPlan.build(
                detections: d, params: s.params, maskScale: Float(fx.mask_scale), marginFrames: fx.margin_frames,
                aspect: Float(fx.aspect), unionFrames: fx.union_frames
            )
            XCTAssertEqual([plan.stats.tracks, plan.stats.confirmedTracks, plan.stats.maskedFrames], expected.stats, s.rawValue)
            XCTAssertEqual(plan.frameCount, expected.ellipses.count)
            var maxDiff: Float = 0
            for i in 0..<plan.frameCount {
                let got = plan.ellipses(at: i)
                let want = expected.ellipses[i].map { Float($0)! }
                XCTAssertEqual(got.count, want.count, "\(s.rawValue), image \(i)")
                if got.count != want.count { continue }
                for k in got.indices { maxDiff = max(maxDiff, abs(got[k] - want[k])) }
            }
            XCTAssertLessThanOrEqual(maxDiff, 1e-5, "\(s.rawValue) : écart maximal \(maxDiff)")
        }
    }
}
