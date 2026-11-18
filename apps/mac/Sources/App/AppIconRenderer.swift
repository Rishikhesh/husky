#if DEBUG
import AppKit
import SwiftUI
import ThinkingOrbsKit

/// draws the app icon with the orb engine itself, so the icon is the same orb
/// the app shows. development only:
/// `open -a "Husky Dev" --args -RenderAppIconTo /some/folder`
/// writes every size the asset catalog's AppIcon set names, then quits.
@MainActor
enum AppIconRenderer {
    static let key = "RenderAppIconTo"

    /// the file name for each pixel size, as AppIcon.appiconset lists them.
    static let files: [(name: String, pixels: Int)] = [
        ("icon_16.png", 16), ("icon_16@2x.png", 32),
        ("icon_32.png", 32), ("icon_32@2x.png", 64),
        ("icon_128.png", 128), ("icon_128@2x.png", 256),
        ("icon_256.png", 256), ("icon_256@2x.png", 512),
        ("icon_512.png", 512), ("icon_512@2x.png", 1024),
    ]

    static func renderIfAsked() {
        guard let folder = UserDefaults.standard.string(forKey: key) else { return }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files {
            let renderer = ImageRenderer(content: AppIconArt().frame(width: 1024, height: 1024))
            renderer.scale = CGFloat(file.pixels) / 1024
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: url.appendingPathComponent(file.name))
        }
        NSApp.terminate(nil)
    }
}

/// the icon at 1024: Apple's grid puts the squircle at 824 inside a clear
/// margin. a near-black body, a soft violet-blue glow under the orb, a hairline
/// of light on the top edge, and the Composing orb in the middle.
private struct AppIconArt: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.11, blue: 0.14), Color(red: 0.035, green: 0.035, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.36, green: 0.40, blue: 1.0).opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 330
                    )
                )
                .frame(width: 700, height: 700)
                .offset(y: 30)
            ThinkingOrb(state: .composing, theme: .dark, displaySize: 560)
                .orbFrozenTime(1.2)
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                lineWidth: 3
            )
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        .frame(width: 1024, height: 1024)
    }
}
#endif
