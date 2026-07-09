import SwiftUI

@main
struct AssetStudioApp: App {
    @State private var controller = EngineController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
        }
        .windowStyle(.automatic)
    }
}
