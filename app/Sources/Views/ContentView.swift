import SwiftUI

struct ContentView: View {
    @Environment(EngineController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            AssetTableView()
                .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        } detail: {
            PreviewPane()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .searchable(text: $controller.searchText, placement: .toolbar,
                    prompt: "Name, container or PathID")
        .navigationTitle("AssetStudio")
    }
}
