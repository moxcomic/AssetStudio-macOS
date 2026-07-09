import SwiftUI

struct AssetTableView: View {
    @Environment(EngineController.self) private var controller
    @Environment(ExportCoordinator.self) private var exporter

    var body: some View {
        @Bindable var controller = controller
        Table(controller.visibleRows, selection: $controller.selection,
              sortOrder: $controller.sortOrder) {
            TableColumn("Name", value: \.name)
            TableColumn("Container", value: \.container)
            TableColumn("Type", value: \.type).width(min: 90, ideal: 110)
            TableColumn("PathID", value: \.pathId) { Text(String($0.pathId)).monospacedDigit() }
                .width(min: 80, ideal: 140)
            TableColumn("Size", value: \.size) {
                Text(ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file))
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
        }
        .accessibilityIdentifier("assetTable")
        .contextMenu(forSelectionType: AssetRow.ID.self) { sel in
            let ids = Array(sel)
            Button("Export…") { exporter.begin(ids: ids, mode: "convert", controller: controller) }
            Button("Export Raw…") { exporter.begin(ids: ids, mode: "raw", controller: controller) }
            Button("Dump…") { exporter.begin(ids: ids, mode: "dump", controller: controller) }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    let ids = controller.selection.map { [$0] } ?? []
                    exporter.begin(ids: ids, mode: "convert", controller: controller)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(controller.selection == nil)
                .help("Export the selected asset")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("\(controller.visibleRows.count) of \(controller.rows.count) assets")
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("statusText")
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
        }
    }
}
