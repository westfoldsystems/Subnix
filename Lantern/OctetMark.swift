//
//  OctetMark.swift
//  The Octet brand mark, drawn natively (no PNG) so it's crisp at any size and
//  adapts to light/dark via the color tokens. Four stacked rounded cells — the
//  top three in .octetInk (ink on light, cream on dark) and the bottom one in
//  .octetAccent (honey), mirroring the app icon's highlighted "8th bit".
//
//  Reusable: the detail empty state uses it now; an About screen can later too.
//

import SwiftUI

struct OctetMark: View {
    /// Overall square edge length in points.
    var size: CGFloat = 44

    var body: some View {
        let cellWidth = size * 0.46
        let cellHeight = size * 0.17
        let gap = size * 0.06
        let radius = cellHeight * 0.34

        VStack(spacing: gap) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(index == 3 ? Color.octetAccent : Color.octetInk)
                    .frame(width: cellWidth, height: cellHeight)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Octet")
    }
}

#Preview("Light") {
    OctetMark(size: 96).padding().background(Color.octetPaper)
}

#Preview("Dark") {
    OctetMark(size: 96).padding().background(Color.octetPaper)
        .preferredColorScheme(.dark)
}
