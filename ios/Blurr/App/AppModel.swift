import AVFoundation
import BlurrCore
import SwiftUI
import UIKit

/// État de l'écran unique : vidéo choisie, réglages, traitement en cours, résultat.
@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case processing(Stage)
    }

    @Published var phase: Phase = .idle
    @Published var info: VideoInfo?
    @Published var status = "Choisissez une vidéo pour commencer."
    @Published var statusIsError = false
    @Published var progress: Double = 0
    @Published var result: PipelineOutput?
    @Published var savedToPhotos = false
    @Published var notice: String?

    // Réglages mémorisés entre deux sessions (mêmes valeurs par défaut qu'Android et la version PC).
    @Published var analysisMaxSide: Int { didSet { defaults.set(analysisMaxSide, forKey: Keys.analysisMaxSide) } }
    @Published var sensitivity: Sensitivity { didSet { defaults.set(sensitivity.rawValue, forKey: Keys.sensitivity) } }
    @Published var style: MaskStyle { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    @Published var keepAudio: Bool { didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) } }
    @Published var verify: Bool { didSet { defaults.set(verify, forKey: Keys.verify) } }

    private enum Keys {
        static let analysisMaxSide = "analysisMaxSide"
        static let sensitivity = "sensitivity"
        static let style = "style"
        static let keepAudio = "keepAudio"
        static let verify = "verify"
    }

    private let defaults = UserDefaults.standard
    private var cancelToken: CancelToken?
    private var task: Task<Void, Never>?
    private var loggedHeader = false

    init() {
        let d = UserDefaults.standard
        let side = d.integer(forKey: Keys.analysisMaxSide)
        analysisMaxSide = analysisSizes.contains(side) ? side : 1280
        sensitivity = d.string(forKey: Keys.sensitivity).flatMap(Sensitivity.init(rawValue:)) ?? .high
        style = d.string(forKey: Keys.style).flatMap(MaskStyle.init(rawValue:)) ?? .blur
        keepAudio = d.object(forKey: Keys.keepAudio) as? Bool ?? true
        verify = d.object(forKey: Keys.verify) as? Bool ?? true
    }

    var isBusy: Bool { phase != .idle }

    var options: Options {
        Options(
            analysisMaxSide: analysisSizes.contains(analysisMaxSide) ? analysisMaxSide : 1280,
            sensitivity: sensitivity,
            style: style,
            keepAudio: keepAudio
        )
    }

    // ------------------------------------------------------------------ choix de la vidéo

    func beginLoading() {
        guard !isBusy else { return }
        phase = .loading
        setStatus("Lecture de la vidéo…")
    }

    func loadingFailed(_ error: Error) {
        AppLog.e("Import de la vidéo impossible", error)
        phase = .idle
        setStatus("Import impossible : \(AppLog.describe(error))", error: true)
    }

    func videoImported(url: URL, name: String) {
        Task {
            do {
                let probed = try await VideoProbe.read(url: url, name: name)
                if !loggedHeader {
                    AppLog.i(DeviceInfo.header)
                    loggedHeader = true
                }
                AppLog.i(probed.logLine)
                info = probed
                result = nil
                savedToPhotos = false
                phase = .idle
                setStatus("Réglez la détection si besoin, puis lancez le masquage.")
            } catch {
                AppLog.e("Lecture de la vidéo impossible", error)
                info = nil
                phase = .idle
                setStatus("Vidéo illisible : \(AppLog.describe(error))", error: true)
            }
        }
    }

    // ------------------------------------------------------------------ traitement

    func start() {
        guard let info, !isBusy else { return }
        let token = CancelToken()
        cancelToken = token
        result = nil
        savedToPhotos = false
        progress = 0
        phase = .processing(.analysis)
        setStatus("Préparation de la détection…")
        UIApplication.shared.isIdleTimerDisabled = true
        let options = self.options
        let verify = self.verify

        task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let output = try await Pipeline.process(info: info, options: options, verify: verify, cancel: token) { stage, fraction, detail in
                    Task { @MainActor [weak self] in self?.showProgress(stage, fraction, detail) }
                }
                await MainActor.run { [weak self] in self?.finished(output) }
            } catch is CancelledError {
                await MainActor.run { [weak self] in self?.cancelled() }
            } catch {
                AppLog.e("Traitement échoué", error)
                await MainActor.run { [weak self] in self?.failed(error) }
            }
        }
    }

    func cancel() {
        guard case .processing = phase else { return }
        cancelToken?.cancel()
        setStatus("Annulation…")
    }

    /// L'application passe en arrière-plan : iOS suspend l'encodage, le traitement ne peut pas continuer.
    func enteredBackground() {
        guard case .processing = phase else { return }
        AppLog.i("Application passée en arrière-plan pendant le traitement : arrêt")
        cancelToken?.cancel()
        notice = "Le traitement a été interrompu parce que l'application est passée en arrière-plan. Relancez-le en gardant blurr à l'écran."
    }

    private func showProgress(_ stage: Stage, _ fraction: Double, _ detail: String?) {
        guard case .processing = phase else { return }
        phase = .processing(stage)
        progress = min(1, max(0, fraction))
        let percent = Int(progress * 100)
        setStatus(detail.map { "\(stage.label) : \(percent) % (\($0))" } ?? "\(stage.label) : \(percent) %")
    }

    private func finished(_ output: PipelineOutput) {
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
        result = output
        progress = 1
        setStatus(output.report.needsAttention ? "Terminé, à vérifier de près." : "Terminé.", error: output.report.needsAttention)
    }

    private func cancelled() {
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
        setStatus("Annulé.")
        AppLog.i("Annulé")
    }

    private func failed(_ error: Error) {
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
        setStatus("Échec : \(AppLog.describe(error))", error: true)
    }

    // ------------------------------------------------------------------ résultat

    func saveToPhotos() {
        guard let output = result else { return }
        Task {
            do {
                try await PhotoSaver.save(output.url, fileName: output.fileName)
                savedToPhotos = true
                notice = "Vidéo enregistrée dans Photos."
            } catch {
                AppLog.e("Enregistrement dans Photos impossible", error)
                notice = AppLog.describe(error)
            }
        }
    }

    func deleteResult() {
        guard let output = result else { return }
        do {
            try FileManager.default.removeItem(at: output.url)
            AppLog.i("Fichier supprimé : \(output.fileName)")
        } catch {
            AppLog.e("Suppression impossible", error)
        }
        result = nil
        savedToPhotos = false
        setStatus("Fichier supprimé de l'application.")
    }

    func copyLog() {
        UIPasteboard.general.string = AppLog.dump()
        notice = "Journal copié. Collez-le dans un message."
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }
}
