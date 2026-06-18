//
//  OctetTheme.swift
//  Reusable styling helpers so every screen wears the brand palette consistently:
//  a warm paper background with surface-colored rows. Applied once per screen
//  rather than per section/row.
//

import SwiftUI

extension View {
    /// Warm paper background with surface-colored rows. Apply to a Form/List.
    func octetScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.octetPaper)
            .listRowBackground(Color.octetSurface)
    }

    /// Warm paper background only (sidebar, empty states) — no row surfaces.
    func octetPaperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.octetPaper)
    }
}
