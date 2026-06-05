import AppKit

// Renders the app icon at all required sizes into an .iconset directory.
// Usage: genicon <output.iconset dir>

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: genicon <iconset-dir>\n".utf8))
    exit(1)
}
let outDir = CommandLine.arguments[1]

func savePNG(_ image: NSImage, pixels: Int, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

// (point size, scale) -> filename per Apple's iconset convention.
let variants: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for v in variants {
    let pixels = v.pt * v.scale
    let image = TrashIcon.makeAppIcon(size: CGFloat(pixels))
    let suffix = v.scale == 1 ? "" : "@2x"
    let name = "icon_\(v.pt)x\(v.pt)\(suffix).png"
    savePNG(image, pixels: pixels, to: "\(outDir)/\(name)")
}

print("rendered \(variants.count) icon sizes to \(outDir)")
