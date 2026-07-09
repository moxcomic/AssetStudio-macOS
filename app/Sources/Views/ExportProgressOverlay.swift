import SwiftUI

struct ExportProgressOverlay: View {
    @Environment(ExportCoordinator.self) private var exporter

    var body: some View {
        if case .running(let current, let total) = exporter.phase {
            VStack(spacing: 12) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .frame(width: 260)
                Text("Exporting… \(current)/\(total)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button("Cancel", role: .cancel) { exporter.cancel() }
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

struct ExportReportSheet: View {
    @Environment(ExportCoordinator.self) private var exporter
    let summary: ExportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(summary.exported) exported, \(summary.skipped) skipped, \(summary.errors.count) failed",
                  systemImage: summary.errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.headline)
            if !summary.errors.isEmpty {
                List(summary.errors) { e in
                    VStack(alignment: .leading) {
                        Text(e.name).bold()
                        Text(e.message).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 160)
            }
            HStack {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([summary.destination]) }
                Spacer()
                Button("Done") { exporter.acknowledge() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(minWidth: 460)
    }
}
