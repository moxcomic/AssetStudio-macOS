import SwiftUI

struct ContentView: View {
    @Environment(EngineController.self) private var controller
    @Environment(ExportCoordinator.self) private var exporter
    @State private var isDropTarget = false

    var body: some View {
        @Bindable var controller = controller
        @Bindable var exporter = exporter
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
        // Drag Unity files or a folder onto the window to load them (same path as ⌘O).
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter(\.isFileURL)
            guard !fileURLs.isEmpty else { return false }
            Task { await controller.openFiles(fileURLs) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(6)
                    .overlay {
                        Label("Drop Unity files to load", systemImage: "square.and.arrow.down")
                            .font(.title3.weight(.medium))
                            .padding(20)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if case .loading(let current, let total) = controller.state {
                VStack(spacing: 12) {
                    ProgressView(value: total > 0 ? Double(current) : nil,
                                 total: Double(max(total, 1)))
                        .frame(width: 240)
                    Text(total > 0 ? "Reading assets… \(current)/\(total)" : "Loading files…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else if case .engineMissing(let why) = controller.state {
                ContentUnavailableView("Engine Not Found", systemImage: "exclamationmark.triangle",
                    description: Text(why))
            }
        }
        .overlay { ExportProgressOverlay() }
        .alert("AssetStudio", isPresented: .init(
            get: { controller.errorToast != nil },
            set: { if !$0 { controller.errorToast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(controller.errorToast ?? "") }
        .sheet(item: $exporter.report) { summary in
            ExportReportSheet(summary: summary)
        }
        .navigationTitle("AssetStudio")
    }
}
