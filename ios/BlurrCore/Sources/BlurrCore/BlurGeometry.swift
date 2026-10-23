import Foundation

/// Paramètres géométriques du rendu (portage de `BlurGeometry.kt`, Android v0.2). Le rendu lui-même est en C++
/// (`Blurr/Engine/MaskRenderer.cpp`, portage du rendu de la version PC) ; ces valeurs y sont reprises à l'identique.
///
/// Flou : l'image est réduite en pyramide (chaque niveau est la moyenne de blocs 2 x 2 du niveau précédent), puis la
/// zone du visage est reconstruite à partir du niveau dont les cellules mesurent environ 1/`cellsPerEllipse` du
/// diamètre de l'ellipse, avec une interpolation B-spline cubique. Le contenu flouté ne dépend que des moyennes de
/// ces cellules : environ 5 cellules sur la plus grande dimension de la boîte du visage.
public enum BlurGeometry {
    /// Cellules sur le diamètre de l'ellipse : 8 cellules / 1,6 = 5 cellules sur la plus grande dimension de la boîte.
    public static let cellsPerEllipse: Float = 8
    /// Niveau minimal de la pyramide (cellules de 2 px), pour que même un très petit visage soit flouté.
    public static let minLevel: Float = 1
    /// Nombre maximal de niveaux de pyramide.
    public static let maxLevels = 12
    /// Bord adouci de l'ellipse : opacité 1 jusqu'au rayon normalisé `edgeStart`, 0 au rayon 1. Les coins de la boîte
    /// du visage sont au rayon racine(2) / 1,6 = 0,884 : ils restent entièrement couverts.
    public static let edgeStart: Float = 0.92
    /// Marge ajoutée aux demi-axes, en pixels de sortie.
    public static let edgePadPx: Float = 1.5

    /// Niveau de pyramide (fractionnaire) pour une ellipse de demi-axes `rxPx` x `ryPx` pixels.
    public static func level(_ rxPx: Float, _ ryPx: Float) -> Float {
        let diameter = 2 * max(rxPx, ryPx)
        let l = Float(log(Double(diameter / cellsPerEllipse)) / log(2.0))
        return min(max(minLevel, l), Float(maxLevels - 1))
    }

    /// Niveau entier inférieur (le supérieur est `lowerLevel` + 1).
    public static func lowerLevel(_ level: Float) -> Int { Int(level.rounded(.down)) }

    /// Opacité du masque au rayon normalisé `r` (0 au centre, 1 sur l'ellipse) : 1 - smoothstep(edgeStart, 1, r).
    public static func coverage(_ r: Float) -> Float {
        let t = min(max((r - edgeStart) / (1 - edgeStart), 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// Taille du niveau `k` de la pyramide d'une image de `size` pixels (division par 2 arrondie au supérieur).
    public static func levelSize(_ size: Int, _ k: Int) -> Int {
        var s = size
        for _ in 0..<max(0, k) { s = max(1, (s + 1) / 2) }
        return s
    }
}
