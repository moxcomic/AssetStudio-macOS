import SwiftUI

struct PreviewPane: View {
    @Environment(EngineController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch controller.preview {
                case .empty:
                    ContentUnavailableView("No Selection", systemImage: "eye",
                        description: Text("Select an asset to preview it"))
                case .loading:
                    ProgressView()
                case .image(let image, let meta):
                    ImagePreviewView(image: image)
                        .id(meta.pathId)   // fresh zoom/pan/channel state per asset
                case .text(let text, _):
                    TextPreviewView(text: text)
                case .none(let meta):
                    ContentUnavailableView(meta.type, systemImage: "shippingbox",
                        description: Text("No visual preview for this type yet"))
                case .failed(let why):
                    ContentUnavailableView("Preview Failed", systemImage: "exclamationmark.triangle",
                        description: Text(why))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let meta = controller.preview.meta {
                Divider()
                InspectorView(meta: meta)
            }
        }
        .onChange(of: controller.selection) { controller.selectionChanged() }
    }
}

extension PreviewState {
    var meta: PreviewMeta? {
        switch self {
        case .image(_, let m), .text(_, let m), .none(let m): m
        default: nil
        }
    }
}
