import SwiftUI

struct AssetTableView: View {
    @Environment(EngineController.self) private var controller

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
