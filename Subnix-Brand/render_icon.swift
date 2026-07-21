// render_icon.swift — regenerate the Subnix app-icon PNGs (CIDR-slash design).
//
// Pure CoreGraphics, no third-party deps (the old PIL/Pillow render_icon.py is
// gone — Pillow isn't guaranteed on macOS, this is). Draws the honey "/" slash
// over dark ink with two paper node dots, matching Subnix-icon.svg and the
// in-app SubnixMark.
//
// Usage — writes straight into the asset catalog:
//   swift Subnix-Brand/render_icon.swift Subnix/Assets.xcassets/AppIcon.appiconset
//
// Produces: Subnix-iOS-1024.png (full-bleed, iOS rounds it itself) plus
// icon_{16,32,64,128,256,512,1024}.png (macOS: 10% padding + continuous corner).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let ink   = (r: 31.0 / 255, g: 27.0 / 255, b: 22.0 / 255)   // #1F1B16
let honey = (r: 232.0 / 255, g: 154.0 / 255, b: 43.0 / 255) // #E89A2B
let paper = (r: 250.0 / 255, g: 247.0 / 255, b: 241.0 / 255)// #FAF7F1

func cg(_ c: (r: Double, g: Double, b: Double)) -> CGColor {
    CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(size: Int, mac: Bool, to path: String) {
    let s = CGFloat(size)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)   // top-left origin
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let pad: CGFloat = mac ? 0.10 * s : 0
    let px = pad, py = pad, ts = s - 2 * pad
    let tileRadius: CGFloat = mac ? 0.2237 * ts : 0

    let tile = roundedPath(CGRect(x: px, y: py, width: ts, height: ts), tileRadius)
    ctx.addPath(tile); ctx.setFillColor(cg(ink)); ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()

    ctx.setStrokeColor(cg(honey))
    ctx.setLineWidth(0.145 * ts)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: px + 0.28 * ts, y: py + 0.72 * ts))
    ctx.addLine(to: CGPoint(x: px + 0.72 * ts, y: py + 0.28 * ts))
    ctx.strokePath()

    ctx.setFillColor(cg(paper))
    let r = 0.046 * ts
    for (cx, cy) in [(0.30, 0.30), (0.70, 0.70)] {
        let c = CGPoint(x: px + CGFloat(cx) * ts, y: py + CGFloat(cy) * ts)
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.fillPath()
    ctx.restoreGState()

    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
render(size: 1024, mac: false, to: "\(dir)/Subnix-iOS-1024.png")
for n in [16, 32, 64, 128, 256, 512, 1024] {
    render(size: n, mac: true, to: "\(dir)/icon_\(n).png")
}
