import XCTest
@testable import BlurrCore

final class OrientationTests: XCTestCase {

    /// Transformations de `AVAssetTrack.preferredTransform` observées sur iPhone.
    private let portrait = DisplayOrientation(a: 0, b: 1, c: -1, d: 0) // filmé debout
    private let portraitUpsideDown = DisplayOrientation(a: 0, b: -1, c: 1, d: 0)
    private let landscapeLeft = DisplayOrientation.identity
    private let landscapeRight = DisplayOrientation(a: -1, b: 0, c: 0, d: -1)

    func testRotations() {
        XCTAssertEqual(landscapeLeft.rotationDegrees, 0)
        XCTAssertEqual(portrait.rotationDegrees, 90)
        XCTAssertEqual(landscapeRight.rotationDegrees, 180)
        XCTAssertEqual(portraitUpsideDown.rotationDegrees, 270)
        XCTAssertFalse(portrait.isMirrored)
        XCTAssertTrue(portrait.swapsAxes)
        XCTAssertTrue(portrait.displaySize(codedWidth: 1920, codedHeight: 1080) == (1080, 1920))
    }

    func testSymetries() {
        let mirror = DisplayOrientation(a: -1, b: 0, c: 0, d: 1)
        XCTAssertTrue(mirror.isValid)
        XCTAssertTrue(mirror.isMirrored)
        XCTAssertEqual(mirror.rotationDegrees, 0)
        let transpose = DisplayOrientation(a: 0, b: 1, c: 1, d: 0)
        XCTAssertTrue(transpose.isValid)
        XCTAssertTrue(transpose.isMirrored)
        XCTAssertFalse(DisplayOrientation(a: 1, b: 1, c: 0, d: 1).isValid)
        XCTAssertFalse(DisplayOrientation(a: 0, b: 0, c: 0, d: 0).isValid)
    }

    func testDepuisUneTransformation() {
        XCTAssertEqual(DisplayOrientation(transformA: 0, b: 1, c: -1, d: 0), portrait)
        XCTAssertEqual(DisplayOrientation(transformA: 1, b: 0, c: 0, d: 1), .identity)
        // Mise à l'échelle uniforme : même orientation.
        XCTAssertEqual(DisplayOrientation(transformA: 0, b: 2, c: -2, d: 0), portrait)
        // Erreur d'arrondi d'une transformation calculée.
        XCTAssertEqual(DisplayOrientation(transformA: 6.1e-17, b: 1, c: -1, d: 6.1e-17), portrait)
        // Rotation de 45 degrés : non prise en charge.
        XCTAssertNil(DisplayOrientation(transformA: 0.7071, b: 0.7071, c: -0.7071, d: 0.7071))
    }

    func testCoinAfficheEnHautAGaucheVientDuCoinCodeEnBasAGauche() {
        // Portrait : l'image codée est tournée d'un quart de tour horaire. Son coin bas gauche devient le coin haut
        // gauche de l'image affichée.
        let e = portrait.toCoded([0, 0, 0.1, 0.2], codedWidth: 1920, codedHeight: 1080)
        XCTAssertEqual(e[0], 0, accuracy: 1e-6)
        XCTAssertEqual(e[1], 1, accuracy: 1e-6)
        // Demi-axes échangés : 0,2 de la hauteur affichée (1920) = 0,2 de la largeur codée.
        XCTAssertEqual(e[2], 0.2, accuracy: 1e-6)
        XCTAssertEqual(e[3], 0.1, accuracy: 1e-6)
    }

    func testAllerRetour() {
        let all = [
            portrait, portraitUpsideDown, landscapeLeft, landscapeRight,
            DisplayOrientation(a: -1, b: 0, c: 0, d: 1), DisplayOrientation(a: 1, b: 0, c: 0, d: -1),
            DisplayOrientation(a: 0, b: 1, c: 1, d: 0), DisplayOrientation(a: 0, b: -1, c: -1, d: 0),
        ]
        for o in all {
            XCTAssertTrue(o.isValid, "\(o)")
            let coded = o.toCoded([0.3, 0.7, 0.05, 0.08], codedWidth: 1280, codedHeight: 720)
            let back = o.toDisplay(x: coded[0], y: coded[1], codedWidth: 1280, codedHeight: 720)
            XCTAssertEqual(back.x, 0.3, accuracy: 1e-5, "\(o)")
            XCTAssertEqual(back.y, 0.7, accuracy: 1e-5, "\(o)")
            // Taille en pixels conservée.
            let ds = o.displaySize(codedWidth: 1280, codedHeight: 720)
            let rxPx = o.swapsAxes ? coded[3] * 720 : coded[2] * 1280
            XCTAssertEqual(rxPx, 0.05 * Float(ds.width), accuracy: 1e-3, "\(o)")
        }
    }

    func testIdentiteSansCopie() {
        let e: [Float] = [0.5, 0.5, 0.1, 0.1]
        XCTAssertEqual(DisplayOrientation.identity.toCoded(e, codedWidth: 100, codedHeight: 50), e)
    }
}
