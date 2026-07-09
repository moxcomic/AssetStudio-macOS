import SwiftUI

struct PreviewPane: View {
    @Environment(EngineController.self) private var controller

    var body: some View {
        if controller.selection == nil {
            ContentUnavailableView("No Selection", systemImage: "eye",
                description: Text("Select an asset to preview it"))
        } else {
            // Task 9 replaces this with real previews.
            ContentUnavailableView("Preview", systemImage: "hourglass",
                description: Text("Preview arrives in a later task"))
        }
    }
}
