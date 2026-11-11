// Renders App/HearthLogo.swift to the 1024-pt app icon. Run on a Mac from the repo root:
//   cat App/HearthLogo.swift ci/render-icon.swift > /tmp/hearth-icon.swift && \
//     swift /tmp/hearth-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// (This file is not part of the app target; it only has top-level code for that one-off script.)
import AppKit

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: HearthLogo(rounded: false).frame(width: 1024, height: 1024))
    renderer.scale = 1
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { fatalError("Could not render the logo") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("Wrote \(CommandLine.arguments[1]) \(cg.width)x\(cg.height)")
}
