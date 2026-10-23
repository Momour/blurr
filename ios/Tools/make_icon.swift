// Génère l'icône de l'application (PNG 1024 x 1024) à partir du dessin vectoriel de l'icône Android
// (android/app/src/main/res/drawable/ic_launcher_foreground.xml) : aucune image n'est versionnée dans le dépôt.
// Usage (macOS) : swift make_icon.swift <sortie.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Contexte graphique indisponible")
}

// Fond plein (une icône iOS ne doit pas être transparente).
ctx.setFillColor(color(0x0F172A))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Dessin Android : repère 108 x 108, origine en haut à gauche. Agrandi de 1,35 autour du centre : sur iOS, l'icône
// occupe tout le carré (pas de zone de sécurité d'icône adaptative).
let unit = CGFloat(size) / 108 * 1.35
func rect(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> CGRect {
    // Conversion vers le repère CoreGraphics (origine en bas à gauche), centre en (54, 54).
    let x = CGFloat(size) / 2 + (cx - 54 - rx) * unit
    let y = CGFloat(size) / 2 - (cy - 54 + ry) * unit
    return CGRect(x: x, y: y, width: 2 * rx * unit, height: 2 * ry * unit)
}
// Visage : disque clair de rayon 24 centré en (54, 54).
ctx.setFillColor(color(0xF1F5F9))
ctx.fillEllipse(in: rect(cx: 54, cy: 54, rx: 24, ry: 24))
// Masque : ellipse sombre 17 x 12 centrée en (54, 53).
ctx.setFillColor(color(0x0F172A))
ctx.fillEllipse(in: rect(cx: 54, cy: 53, rx: 17, ry: 12))

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Écriture de l'icône impossible")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Écriture de l'icône impossible") }
print("Icône écrite : \(output)")
