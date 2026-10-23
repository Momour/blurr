import Foundation

/// Orientation d'affichage d'une piste vidéo : matrice entière M = [a c; b d] (rotations par quarts de tour et
/// symétries) telle que, en coordonnées centrées sur l'image, x' = a x + c y et y' = b x + d y, (x, y) étant un point
/// de l'image codée et (x', y') le même point dans l'image affichée (redressée).
///
/// Sur iOS, c'est la partie linéaire de `AVAssetTrack.preferredTransform` (convention vecteur ligne : x' = a x + c y +
/// tx, y' = b x + d y + ty). Une vidéo filmée en portrait est en général codée en paysage avec a = 0, b = 1, c = -1,
/// d = 0 : l'image codée doit être tournée d'un quart de tour dans le sens horaire pour être affichée.
public struct DisplayOrientation: Equatable, Sendable, CustomStringConvertible {
    public let a: Int
    public let b: Int
    public let c: Int
    public let d: Int

    public static let identity = DisplayOrientation(a: 1, b: 0, c: 0, d: 1)

    public init(a: Int, b: Int, c: Int, d: Int) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    /// Orientation la plus proche d'une transformation quelconque (coefficients arrondis à -1, 0 ou 1). Renvoie nil
    /// si la transformation n'est pas un quart de tour ou une symétrie (vidéo retouchée avec un angle arbitraire).
    public init?(transformA ta: Double, b tb: Double, c tc: Double, d td: Double) {
        func snap(_ v: Double) -> Int? {
            if abs(v) < 0.01 { return 0 }
            if abs(v - 1) < 0.01 { return 1 }
            if abs(v + 1) < 0.01 { return -1 }
            return nil
        }
        // Une mise à l'échelle uniforme ne change pas l'orientation : on normalise par la norme de la première colonne.
        let scale = (ta * ta + tb * tb).squareRoot()
        guard scale > 1e-9 else { return nil }
        guard let a = snap(ta / scale), let b = snap(tb / scale), let c = snap(tc / scale), let d = snap(td / scale) else {
            return nil
        }
        let candidate = DisplayOrientation(a: a, b: b, c: c, d: d)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    /// Matrice orthogonale entière (déterminant +1 ou -1, une seule valeur non nulle par ligne et par colonne).
    public var isValid: Bool {
        let det = a * d - b * c
        return (det == 1 || det == -1) && (a == 0) == (d == 0) && (b == 0) == (c == 0) && (a == 0) != (b == 0)
    }

    /// Vrai si l'image affichée a la largeur et la hauteur de l'image codée échangées (quart de tour).
    public var swapsAxes: Bool { a == 0 }

    /// Vrai si l'orientation comporte une symétrie (vidéo en miroir).
    public var isMirrored: Bool { a * d - b * c == -1 }

    /// Rotation horaire en degrés appliquée après l'éventuelle symétrie horizontale (pour le journal et le rendu :
    /// image affichée = rotation(symétrie(image codée))).
    public var rotationDegrees: Int {
        // Partie rotation R = M * F, F = symétrie horizontale [-1 0; 0 1], si M est une symétrie ; sinon R = M.
        let (r00, r10): (Int, Int) = isMirrored ? (-a, -b) : (a, b)
        switch (r00, r10) {
        case (1, 0): return 0
        case (0, 1): return 90
        case (-1, 0): return 180
        default: return 270
        }
    }

    public func displaySize(codedWidth: Int, codedHeight: Int) -> (width: Int, height: Int) {
        swapsAxes ? (codedHeight, codedWidth) : (codedWidth, codedHeight)
    }

    /// Convertit des ellipses [cx, cy, rx, ry, ...] normalisées dans l'image affichée en ellipses normalisées dans
    /// l'image codée (les ellipses restent alignées sur les axes : les demi-axes sont échangés par un quart de tour).
    public func toCoded(_ display: [Float], codedWidth: Int, codedHeight: Int) -> [Float] {
        if self == .identity || display.isEmpty { return display }
        let size = displaySize(codedWidth: codedWidth, codedHeight: codedHeight)
        let dw = Float(size.width)
        let dh = Float(size.height)
        let cw = Float(codedWidth)
        let ch = Float(codedHeight)
        var out = [Float](repeating: 0, count: display.count)
        var i = 0
        while i + 3 < display.count {
            // Point centré, en pixels de l'image affichée, puis transformation inverse (M orthogonale : M^-1 = M^T).
            let xd = (display[i] - 0.5) * dw
            let yd = (display[i + 1] - 0.5) * dh
            let xc = Float(a) * xd + Float(b) * yd
            let yc = Float(c) * xd + Float(d) * yd
            out[i] = xc / cw + 0.5
            out[i + 1] = yc / ch + 0.5
            if swapsAxes {
                out[i + 2] = display[i + 3] * dh / cw
                out[i + 3] = display[i + 2] * dw / ch
            } else {
                out[i + 2] = display[i + 2]
                out[i + 3] = display[i + 3]
            }
            i += 4
        }
        return out
    }

    /// Position normalisée dans l'image affichée d'un point normalisé de l'image codée.
    public func toDisplay(x: Float, y: Float, codedWidth: Int, codedHeight: Int) -> (x: Float, y: Float) {
        let size = displaySize(codedWidth: codedWidth, codedHeight: codedHeight)
        let xc = (x - 0.5) * Float(codedWidth)
        let yc = (y - 0.5) * Float(codedHeight)
        let xd = Float(a) * xc + Float(c) * yc
        let yd = Float(b) * xc + Float(d) * yc
        return (xd / Float(size.width) + 0.5, yd / Float(size.height) + 0.5)
    }

    public var description: String {
        "rotation \(rotationDegrees)°" + (isMirrored ? " avec symétrie" : "")
    }
}
