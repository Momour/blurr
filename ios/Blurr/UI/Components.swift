import AVKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Vidéo reçue du sélecteur de Photos, copiée dans le dossier d'import de l'application.
struct PickedMovie: Transferable {
    let url: URL
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Le fichier reçu est provisoire : il faut le copier avant de rendre la main.
            let name = received.file.lastPathComponent
            let copy = try ImportStore.copy(received.file, preferredName: name)
            return PickedMovie(url: copy, name: name)
        }
    }
}

/// Lecture de la vidéo produite.
struct PlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// Textes de licence de blurr et des composants embarqués.
struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [(title: String, detail: String, file: String)] = [
        ("blurr", "GNU General Public License v3.0 ou ultérieure. Code source : github.com/Momour/blurr", "license-blurr-GPL-3.0"),
        ("YuNet (face_detection_yunet_2023mar.onnx)", "OpenCV Zoo, licence MIT, © 2020 Shiqi Yu. Modèle embarqué sans modification.", "license-yunet-MIT"),
        ("OpenCV 4.14.0", "Licence Apache 2.0. Exécution du détecteur et traitement des images.", "license-opencv-Apache-2.0"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.file) { entry in
                    NavigationLink {
                        ScrollView {
                            Text(Self.text(entry.file))
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle(entry.title)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.headline)
                            Text(entry.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("La bibliothèque OpenCV pour iOS intègre ses propres composants tiers (libjpeg-turbo, libpng, zlib, Protobuf, etc.), dont l'inventaire des licences reste à faire. Voir THIRD_PARTY.md dans le dépôt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Licences")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private static func text(_ file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Texte de licence introuvable dans l'application."
        }
        return content
    }
}
