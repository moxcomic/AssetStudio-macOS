import SwiftUI
import CoreImage

struct ImagePreviewView: View {
    let image: NSImage
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var channels: Set<Character> = ["R", "G", "B", "A"]

    private var displayed: NSImage {
        channels == ["R", "G", "B", "A"] ? image : Self.filtered(image, channels: channels)
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
                }
                .clipped()
                .gesture(DragGesture().onChanged { offset = $0.translation })
                .gesture(MagnifyGesture().onChanged { zoom = max(0.1, min(32, $0.magnification)) })
                .onTapGesture(count: 2) { withAnimation { zoom = 1; offset = .zero } }
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
    }

    static func filtered(_ image: NSImage, channels: Set<Character>) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let ci = CIImage(cgImage: cg)
        let r: CGFloat = channels.contains("R") ? 1 : 0
        let g: CGFloat = channels.contains("G") ? 1 : 0
        let b: CGFloat = channels.contains("B") ? 1 : 0
        let alphaOnly = channels == ["A"]
        let f = CIFilter(name: "CIColorMatrix")!
        f.setValue(ci, forKey: kCIInputImageKey)
        if alphaOnly {
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        } else {
            f.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        }
        let context = CIContext()
        guard let out = f.outputImage,
              let rendered = context.createCGImage(out, from: ci.extent) else { return image }
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
