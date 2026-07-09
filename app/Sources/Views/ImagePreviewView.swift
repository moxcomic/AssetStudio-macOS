import SwiftUI
import CoreImage

struct ImagePreviewView: View {
    let image: NSImage
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var channels: Set<Character> = ["R", "G", "B", "A"]
    /// Memoized channel-filtered image: recomputed only when `channels` changes,
    /// never inside `body`, so gesture-driven re-renders stay cheap.
    @State private var displayed: NSImage

    /// Shared context — creating a CIContext per frame is the expensive part.
    private static let ciContext = CIContext()

    init(image: NSImage) {
        self.image = image
        _displayed = State(initialValue: image)
    }

    var body: some View {
        GeometryReader { _ in
            CheckerboardBackground()
                .overlay {
                    Image(nsImage: displayed)
                        .resizable()
                        .interpolation(zoom > 3 ? .none : .high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .accessibilityIdentifier("previewImage")   // E2E success signal
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged {
                            offset = CGSize(width: baseOffset.width + $0.translation.width,
                                            height: baseOffset.height + $0.translation.height)
                        }
                        .onEnded { _ in baseOffset = offset }
                )
                .gesture(
                    MagnifyGesture()
                        .onChanged { zoom = max(0.1, min(32, baseZoom * $0.magnification)) }
                        .onEnded { _ in baseZoom = zoom }
                )
                .onTapGesture(count: 2) {
                    withAnimation { zoom = 1; baseZoom = 1; offset = .zero; baseOffset = .zero }
                }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                ForEach(["R", "G", "B", "A"], id: \.self) { ch in
                    Toggle(ch, isOn: .init(
                        get: { channels.contains(Character(ch)) },
                        set: { on in
                            if on { channels.insert(Character(ch)) } else { channels.remove(Character(ch)) }
                            if channels.isEmpty { channels = [Character(ch)] }
                        }))
                        .toggleStyle(.button)
                        .font(.caption.bold())
                }
                Divider().frame(height: 16)
                Text("\(Int(image.size.width))×\(Int(image.size.height))  \(Int(zoom * 100))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 10)
        }
        .onChange(of: channels) {
            displayed = channels == ["R", "G", "B", "A"] ? image : Self.filtered(image, channels: channels)
        }
    }

    static func filtered(_ image: NSImage, channels: Set<Character>) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let ci = CIImage(cgImage: cg)
        let f = CIFilter(name: "CIColorMatrix")!
        f.setValue(ci, forKey: kCIInputImageKey)
        if channels == ["A"] {
            // Alpha-only: show the alpha channel as opaque grayscale.
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        } else {
            let r: CGFloat = channels.contains("R") ? 1 : 0
            let g: CGFloat = channels.contains("G") ? 1 : 0
            let b: CGFloat = channels.contains("B") ? 1 : 0
            f.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
            if !channels.contains("A") {
                // A off (with RGB on): force fully opaque so the toggle is visible
                // instead of leaving the source alpha to pass through unchanged.
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
            }
        }
        guard let out = f.outputImage,
              let rendered = Self.ciContext.createCGImage(out, from: ci.extent) else { return image }
        return NSImage(cgImage: rendered, size: image.size)
    }
}

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 8
            for row in 0...Int(size.height / cell) {
                for col in 0...Int(size.width / cell) where (row + col).isMultiple(of: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                                         width: cell, height: cell)),
                             with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(Color.gray.opacity(0.08))
    }
}
