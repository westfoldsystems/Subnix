//
//  SubnixMark.swift
//  The Subnix brand mark, drawn natively (no PNG) so it's crisp at any size and
//  matches the app icon exactly: a honey CIDR "/" slash over dark ink, flanked by
//  two paper node dots — subnet notation as a network of two hosts split by a
//  prefix. Colors are the fixed brand values (not the adaptive tokens) so the mark
//  reads the same in light and dark, just like the icon on a home screen; a muted
//  hairline keeps the dark tile legible when it sits on a dark background.
//
//  Reusable: the detail empty state uses it now; an About screen can later too.
//

import SwiftUI

struct SubnixMark: View {
    /// Overall square edge length in points.
    var size: CGFloat = 44

    // Fixed brand palette — mirrors the app icon (deliberately not the adaptive
    // .subnix* tokens, so the mark never inverts).
    private static let ink = Color(red: 31 / 255, green: 27 / 255, blue: 22 / 255)      // #1F1B16
    private static let honey = Color(red: 232 / 255, green: 154 / 255, blue: 43 / 255)  // #E89A2B
    private static let paper = Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255) // #FAF7F1

    var body: some View {
        let radius = size * 0.2237  // macOS-style continuous corner

        Canvas { ctx, sz in
            let s = sz.width

            var slash = Path()
            slash.move(to: CGPoint(x: 0.28 * s, y: 0.72 * s))
            slash.addLine(to: CGPoint(x: 0.72 * s, y: 0.28 * s))
            ctx.stroke(slash, with: .color(Self.honey),
                       style: StrokeStyle(lineWidth: 0.145 * s, lineCap: .round))

            let r = 0.046 * s
            for p in [CGPoint(x: 0.30 * s, y: 0.30 * s), CGPoint(x: 0.70 * s, y: 0.70 * s)] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Self.paper))
            }
        }
        .frame(width: size, height: size)
        .background(Self.ink)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.subnixMuted.opacity(0.45), lineWidth: max(1, size * 0.014))
        )
        .accessibilityElement()
        .accessibilityLabel("Subnix")
    }
}

#Preview("Light") {
    SubnixMark(size: 96).padding().background(Color.subnixPaper)
}

#Preview("Dark") {
    SubnixMark(size: 96).padding().background(Color.subnixPaper)
        .preferredColorScheme(.dark)
}
