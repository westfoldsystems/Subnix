//
//  RootView.swift
//  The sidebar + detail shell. Tool list is data-driven off ToolRegistry,
//  so adding a tool is one line in the registry and zero changes here.
//

import SwiftUI

struct RootView: View {
    @State private var selectedToolID: String?
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

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
            .subnixPaperBackground()
            .navigationTitle("Subnix")
            .toolbar { appearanceMenu }
            #if os(iOS)
            // Brand lockup: "Subnix" with the mark to its right, in the title bar.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Subnix")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.subnixInk)
                        SubnixMark(size: 26)
                    }
                }
            }
            #endif
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
                ContentUnavailableView {
                    Label {
                        Text("Select a tool")
                    } icon: {
                        SubnixMark(size: 44)
                    }
                } description: {
                    Text("Everything runs on-device. No account, no telemetry, nothing leaves this device.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.subnixPaper)
            }
        }
        // Apply the chosen appearance to the whole window; .system passes nil
        // (defers to the OS).
        .preferredColorScheme(appearance.colorScheme)
        // Brand accent (honey) for controls, selection, buttons app-wide.
        .tint(.subnixAccent)
    }

    private var appearanceMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Appearance", selection: Binding(
                    get: { appearance },
                    set: { appearanceRaw = $0.rawValue }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Appearance", systemImage: appearance.systemImage)
            }
        }
    }
}

#Preview {
    RootView()
}
