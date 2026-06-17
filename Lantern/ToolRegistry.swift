//
//  ToolRegistry.swift
//  Register tools here. The sidebar reads straight off this — to ship a new
//  tool, write its engine + view, add a small wrapper struct, drop it in `all`.
//

import SwiftUI

// MARK: - Concrete tool wrappers

struct SubnetTool: @MainActor NetworkTool {
    let id = "subnet"
    let name = "Subnet Calculator"
    let summary = "CIDR, masks, host ranges and counts — fully offline."
    let systemImage = "function"
    let category: ToolCategory = .calculators
    var view: AnyView { AnyView(SubnetView()) }
}

struct BonjourTool: @MainActor NetworkTool {
    let id = "bonjour"
    let name = "Bonjour Discovery"
    let summary = "Find services advertised on your local network (mDNS)."
    let systemImage = "dot.radiowaves.left.and.right"
    let category: ToolCategory = .discovery
    var view: AnyView { AnyView(BonjourView()) }
}

struct VLSMTool: @MainActor NetworkTool {
    let id = "vlsm"
    let name = "VLSM Planner"
    let summary = "Pack named subnets into a base block, largest-first — offline."
    let systemImage = "square.grid.3x3.topleft.filled"
    let category: ToolCategory = .calculators
    var view: AnyView { AnyView(VLSMView()) }
}

struct IPv6Tool: @MainActor NetworkTool {
    let id = "ipv6"
    let name = "IPv6 Toolkit"
    let summary = "Compress/expand, prefix math, and EUI-64 — fully offline."
    let systemImage = "6.circle"
    let category: ToolCategory = .calculators
    var view: AnyView { AnyView(IPv6View()) }
}

struct ConvertersTool: @MainActor NetworkTool {
    let id = "converters"
    let name = "Converters"
    let summary = "IPv4 base conversion and MAC normalisation — offline."
    let systemImage = "arrow.left.arrow.right"
    let category: ToolCategory = .calculators
    var view: AnyView { AnyView(ConvertersView()) }
}

struct OUITool: @MainActor NetworkTool {
    let id = "oui"
    let name = "MAC Vendor Lookup"
    let summary = "Resolve a MAC's manufacturer from a bundled IEEE table — offline."
    let systemImage = "barcode.viewfinder"
    let category: ToolCategory = .lookup
    var view: AnyView { AnyView(OUIView()) }
}

struct PortCheckTool: @MainActor NetworkTool {
    let id = "portcheck"
    let name = "TCP Port Check"
    let summary = "Connect-scan ports on a host you type — open/closed/timed-out."
    let systemImage = "bolt.horizontal"
    let category: ToolCategory = .lookup
    var view: AnyView { AnyView(PortCheckView()) }
}

struct HTTPHeaderTool: @MainActor NetworkTool {
    let id = "httpheaders"
    let name = "HTTP Header Inspector"
    let summary = "Follow the redirect chain and inspect response + security headers."
    let systemImage = "list.bullet.rectangle"
    let category: ToolCategory = .lookup
    var view: AnyView { AnyView(HTTPHeaderView()) }
}

// MARK: - Registry

@MainActor
enum ToolRegistry {
    /// The single source of truth for what ships. Order within a category is
    /// preserved in the sidebar.
    static let all: [any NetworkTool] = [
        // Calculators (pure, offline)
        SubnetTool(),
        VLSMTool(),
        IPv6Tool(),
        ConvertersTool(),
        // Lookup
        OUITool(),
        PortCheckTool(),
        HTTPHeaderTool(),
        // Discovery
        BonjourTool(),
        // Next up (each is a self-contained PR):
        //   TLSInspectorTool(), WhatsMyIPTool(),
        //   DNSTool(), PingTool(), LANScannerTool()
    ]

    static func tools(in category: ToolCategory) -> [any NetworkTool] {
        all.filter { $0.category == category }
    }

    static var categoriesInUse: [ToolCategory] {
        ToolCategory.allCases.filter { !tools(in: $0).isEmpty }
    }
}
