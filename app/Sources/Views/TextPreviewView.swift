import SwiftUI

struct TextPreviewView: View {
    let text: String

    /// Character cap on what is laid out. A single non-virtualized Text with
    /// horizontal scroll (no wrapping) lays out the whole string on the main
    /// thread, so a multi-MB dump would hang the UI — show a slice + a notice.
    private static let displayCap = 64 * 1024

    var body: some View {
        // O(cap): prefix walks at most `displayCap` characters; the index
        // comparison is O(1). Never touches `text.count` (O(n)).
        let prefix = text.prefix(Self.displayCap)
        let truncated = prefix.endIndex < text.endIndex
        let shown = String(prefix)

        VStack(spacing: 0) {
            if truncated {
                Text("Showing the first \(Self.displayCap / 1024) KB — export the asset to view it in full.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.bar)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(shown)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
