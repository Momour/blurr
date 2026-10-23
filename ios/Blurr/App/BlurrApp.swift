import SwiftUI

@main
struct BlurrApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Copies de vidéos importées lors d'une session précédente : inutiles.
        ImportStore.clear()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.enteredBackground() }
        }
    }
}
