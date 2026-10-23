import BlurrCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Écran unique : choisir une vidéo, régler la détection, lancer le masquage, lire, enregistrer ou partager.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showPlayer = false
    @State private var showLicenses = false

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if model.info != nil {
                    settingsSections
                }
                statusSection
                if let result = model.result {
                    resultSection(result)
                }
                Section {
                    Button("Copier le journal (diagnostic)") { model.copyLog() }
                    Button("Licences") { showLicenses = true }
                } footer: {
                    Text("Le journal contient le modèle de l'appareil, la version d'iOS, les caractéristiques techniques de la vidéo et les étapes du traitement. Il ne contient ni image ni position.")
                }
            }
            .navigationTitle("blurr")
        }
        .onChange(of: pickerItem) { _, item in loadFromPhotos(item) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie]) { result in loadFromFiles(result) }
        .sheet(isPresented: $showPlayer) {
            if let url = model.result?.url { PlayerView(url: url) }
        }
        .sheet(isPresented: $showLicenses) { LicensesView() }
        .alert(
            model.notice ?? "",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    // ------------------------------------------------------------------ sections

    private var sourceSection: some View {
        Section {
            Text("Floute les visages d'une vidéo. Tout est traité sur ce téléphone ; l'application n'utilise pas Internet.")
                .font(.callout)
            PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
                Label("Choisir une vidéo", systemImage: "photo.on.rectangle")
            }
            .disabled(model.isBusy)
            Button {
                showFiles = true
            } label: {
                Label("Choisir dans Fichiers", systemImage: "folder")
            }
            .disabled(model.isBusy)
            if model.phase == .loading {
                HStack {
                    ProgressView()
                    Text("Lecture de la vidéo…").foregroundStyle(.secondary)
                }
            }
            if let info = model.info {
                Text(info.summary).font(.callout).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var settingsSections: some View {
        Section {
            Picker("Précision", selection: $model.analysisMaxSide) {
                Text("Rapide").tag(960)
                Text("Standard").tag(1280)
                Text("Précise").tag(1920)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Précision de l'analyse")
        } footer: {
            Text("\(model.analysisMaxSide) px sur le grand côté. Plus précis = plus lent.")
        }
        .disabled(model.isBusy)

        Section {
            Picker("Sensibilité", selection: $model.sensitivity) {
                ForEach(Sensitivity.allCases, id: \.self) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Sensibilité")
        } footer: {
            Text(model.sensitivity.help)
        }
        .disabled(model.isBusy)

        Section {
            Picker("Rendu", selection: $model.style) {
                ForEach(MaskStyle.allCases, id: \.self) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            Toggle("Conserver le son", isOn: $model.keepAudio)
            Toggle("Contrôler le résultat", isOn: $model.verify)
        } header: {
            Text("Rendu")
        } footer: {
            Text(model.style == .blur
                 ? "Flou fort, proportionnel à la taille du visage. Le masque noir protège davantage."
                 : "Ellipse noire opaque : protection la plus sûre.")
        }
        .disabled(model.isBusy)

        Section {
            Button {
                model.start()
            } label: {
                Label("Masquer les visages", systemImage: "eye.slash")
                    .font(.headline)
            }
            .disabled(model.isBusy || model.info == nil)
        } footer: {
            Text("Laissez l'application ouverte et l'écran allumé pendant le traitement : iOS l'interrompt si l'application passe en arrière-plan.")
        }
    }

    private var statusSection: some View {
        Section {
            if case .processing = model.phase {
                ProgressView(value: model.progress)
                Button("Annuler", role: .destructive) { model.cancel() }
            }
            Text(model.status)
                .foregroundStyle(model.statusIsError ? Color.red : Color.primary)
                .textSelection(.enabled)
        }
    }

    private func resultSection(_ result: PipelineOutput) -> some View {
        Section {
            let size = ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)
            Text("Fichier : \(result.fileName) (\(size)), traité en \(Int(result.seconds.rounded())) s. Copie disponible dans Fichiers > Sur mon iPhone > blurr.")
                .font(.callout)
            ForEach(Array(result.report.lines().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(line.hasPrefix("ATTENTION") ? Color.red : Color.primary)
            }
            Button {
                showPlayer = true
            } label: {
                Label("Lire la vidéo", systemImage: "play.rectangle")
            }
            Button {
                model.saveToPhotos()
            } label: {
                Label(model.savedToPhotos ? "Enregistrée dans Photos" : "Enregistrer dans Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(model.savedToPhotos)
            ShareLink(item: result.url) {
                Label("Partager", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                model.deleteResult()
            } label: {
                Label("Supprimer ce fichier de l'application", systemImage: "trash")
            }
        } header: {
            Text("Résultat")
        }
    }

    // ------------------------------------------------------------------ import

    private func loadFromPhotos(_ item: PhotosPickerItem?) {
        guard let item else { return }
        model.beginLoading()
        Task {
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw BlurrError("Vidéo indisponible.")
                }
                model.videoImported(url: movie.url, name: movie.name)
            } catch {
                model.loadingFailed(error)
            }
            pickerItem = nil
        }
    }

    private func loadFromFiles(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            model.loadingFailed(error)
        case .success(let url):
            model.beginLoading()
            let model = self.model
            Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let copy = try ImportStore.copy(url)
                    await model.videoImported(url: copy, name: url.lastPathComponent)
                } catch {
                    await model.loadingFailed(error)
                }
            }
        }
    }
}
