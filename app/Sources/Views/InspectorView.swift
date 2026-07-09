import SwiftUI

struct InspectorView: View {
    let meta: PreviewMeta

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Name", meta.name)
            row("Type", meta.type)
            if !meta.container.isEmpty { row("Container", meta.container) }
            row("PathID", String(meta.pathId))
            row("Size", ByteCountFormatter.string(fromByteCount: meta.size, countStyle: .file))
            ForEach(meta.extra.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                row(k, v)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(2)
        }
    }
}
