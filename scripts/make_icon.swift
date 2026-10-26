// Turns the generated artwork into a proper macOS app icon set.
// Usage: swift make_icon.swift <source-image> <output.iconset>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: make_icon <image> <out.iconset>"); exit(1)
}

// Crop the squircle out of the rendered artwork (artwork is 1024², tile spans ~195…830).
let scale = CGFloat(cg.width) / 1024
let crop = CGRect(x: 203 * scale, y: 201 * scale, width: 620 * scale, height: 620 * scale)
guard let tile = cg.cropping(to: crop) else { exit(1) }

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Apple grid: 824/1024 body with ~100px margin.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // Slight overscan so the tile's own rounded border sits outside the mask.
    let over = body.insetBy(dx: -body.width * 0.035, dy: -body.width * 0.035)
    ctx.draw(tile, in: over)
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written to \(out.path)")
