// swift-tools-version:5.9
// Moteur de blurr sans dépendance Apple : modèle, suivi des détections, plan de masquage, règles d'encodage.
// Compilable et testable sur macOS, iOS et Linux (`swift test`).
import PackageDescription

let package = Package(
    name: "BlurrCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "BlurrCore", targets: ["BlurrCore"]),
    ],
    targets: [
        .target(name: "BlurrCore"),
        .testTarget(name: "BlurrCoreTests", dependencies: ["BlurrCore"], resources: [.copy("Fixtures")]),
    ]
)
