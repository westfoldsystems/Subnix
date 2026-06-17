//
//  NetworkTool.swift
//  The extension point for the whole app.
//
//  Design note: I deliberately did NOT force a uniform `run(input) async -> Result`
//  across tools. A pure synchronous calculator and a long-lived streaming scanner
//  don't share an honest signature — forcing one produces a leaky abstraction.
//  Instead, `NetworkTool` is about identity + presentation (so the UI can be
//  data-driven), and each tool owns its own engine type (SubnetCalculator,
//  BonjourScanner, …) with whatever signature actually fits it.
//

import SwiftUI

enum ToolCategory: String, CaseIterable, Identifiable {
    case calculators = "Calculators"
    case discovery   = "Discovery"
    case lookup      = "Lookup"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .calculators: return "function"
        case .discovery:   return "dot.radiowaves.left.and.right"
        case .lookup:      return "magnifyingglass"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

@MainActor
protocol NetworkTool: Identifiable {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var systemImage: String { get }
    var category: ToolCategory { get }
    var view: AnyView { get }
}
