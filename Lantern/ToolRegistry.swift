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

// MARK: - Registry

@MainActor
enum ToolRegistry {
    /// The single source of truth for what ships. Order within a category is
    /// preserved in the sidebar.
    static let all: [any NetworkTool] = [
        SubnetTool(),
        BonjourTool(),
        // Next up (each is a self-contained PR):
        //   VLSMTool(), IPv6Tool(), MACVendorTool(),
        //   PingTool(), TracerouteTool(), DNSTool(),
        //   PortCheckTool(), TLSInspectorTool(), WhatsMyIPTool()
    ]

    static func tools(in category: ToolCategory) -> [any NetworkTool] {
        all.filter { $0.category == category }
    }

    static var categoriesInUse: [ToolCategory] {
        ToolCategory.allCases.filter { !tools(in: $0).isEmpty }
    }
}
