import SwiftUI

struct SettingsView: View {
    @AppStorage("export.imageFormat") private var imageFormat = "png"
    @AppStorage("export.groupBy") private var groupBy = "containerPath"

    var body: some View {
        Form {
            Picker("Image format", selection: $imageFormat) {
                Text("PNG").tag("png"); Text("TGA").tag("tga"); Text("JPEG").tag("jpg")
                Text("BMP").tag("bmp"); Text("WebP").tag("webp")
            }
            Picker("Group exported assets", selection: $groupBy) {
                Text("Do not group").tag("none")
                Text("By type name").tag("typeName")
                Text("By container path").tag("containerPath")
                Text("By container path (full)").tag("containerPathFull")
                Text("By source file name").tag("sourceFileName")
            }
        }
        .formStyle(.grouped).frame(width: 420).navigationTitle("Settings")
    }
}
