import SwiftUI

struct SidebarView: View {
    @Environment(EngineController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        List(selection: $controller.selectedType) {
            Section("Asset Types") {
                Label("All Assets", systemImage: "square.grid.2x2")
                    .badge(controller.rows.count)
                    .tag(String?.none)
                ForEach(controller.typeCounts, id: \.type) { entry in
                    Label(entry.type, systemImage: "doc")
                        .badge(entry.count)
                        .tag(String?.some(entry.type))
                }
            }
        }
        .overlay {
            if controller.rows.isEmpty {
                ContentUnavailableView("No Files Loaded", systemImage: "shippingbox",
                    description: Text("File ▸ Open… to load Unity files"))
            }
        }
    }
}
