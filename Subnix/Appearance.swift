//
//  Appearance.swift
//  In-app light/dark override. The choice is persisted (@AppStorage) and applied
//  at the window root via .preferredColorScheme, so it sticks across launches and
//  overrides the system setting — `.system` defers back to it.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// nil means "follow the system" (no override).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The shared `@AppStorage` key for the persisted choice.
    static let storageKey = "appearanceMode"
}
