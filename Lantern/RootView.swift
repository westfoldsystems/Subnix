//
//  RootView.swift
//  The sidebar + detail shell. Tool list is data-driven off ToolRegistry,
//  so adding a tool is one line in the registry and zero changes here.
//

import SwiftUI

struct RootView: View {
    @State private var selectedToolID: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedToolID) {
                ForEach(ToolRegistry.categoriesInUse) { category in
                    Section(category.rawValue) {
                        ForEach(ToolRegistry.tools(in: category), id: \.id) { tool in
                            Label(tool.name, systemImage: tool.systemImage)
                                .tag(tool.id)
                        }
                    }
                }
            }
            .navigationTitle("Lantern")
            #if os(macOS)
            .frame(minWidth: 230)
            #endif
        } detail: {
            if let id = selectedToolID,
               let tool = ToolRegistry.all.first(where: { $0.id == id }) {
                tool.view
                    .navigationTitle(tool.name)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else {
                ContentUnavailableView(
                    "Select a tool",
                    systemImage: "lightbulb.min",
                    description: Text("Everything runs on-device. No account, no telemetry, nothing leaves this device.")
                )
            }
        }
    }
}

#Preview {
    RootView()
}
