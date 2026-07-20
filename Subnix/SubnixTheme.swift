//
//  SubnixTheme.swift
//  Reusable styling helpers so every screen wears the brand palette consistently:
//  a warm paper background with surface-colored rows. Applied once per screen
//  rather than per section/row.
//

import SwiftUI

extension View {
    /// Warm paper background with surface-colored rows. Apply to a Form/List.
    func subnixScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.subnixPaper)
            .listRowBackground(Color.subnixSurface)
    }

    /// Warm paper background only (sidebar, empty states) — no row surfaces.
    func subnixPaperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.subnixPaper)
    }
}
