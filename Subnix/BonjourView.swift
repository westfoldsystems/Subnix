//
//  BonjourView.swift
//  Lists discovered services grouped by type, with scan/stop control.
//

import SwiftUI

struct BonjourView: View {
    @State private var scanner = BonjourScanner()

    var body: some View {
        List {
            if scanner.services.isEmpty {
                emptyState
            } else {
                ForEach(groupedTypes, id: \.self) { type in
                    Section(prettyType(type)) {
                        ForEach(grouped[type] ?? []) { svc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(svc.name)
                                Text(svc.domain)
                                    .font(.caption)
                                    .foregroundStyle(.subnixMuted)
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .subnixScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scanner.state == .scanning {
                    Button("Stop", systemImage: "stop.fill") { scanner.stop() }
                } else {
                    Button("Scan", systemImage: "arrow.clockwise") { scanner.start() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Discovery stays on this network. Subnix contacts no servers.")
                .font(.caption2)
                .foregroundStyle(.subnixMuted)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scanner.state {
        case .scanning:
            HStack(spacing: 12) {
                ProgressView()
                Text("Listening for services…").foregroundStyle(.subnixMuted)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.statusTimeout)
        default:
            ContentUnavailableView(
                "No services yet",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Tap Scan to discover devices advertising on this network.")
            )
        }
    }

    // MARK: - Grouping

    private var grouped: [String: [BonjourScanner.DiscoveredService]] {
        Dictionary(grouping: scanner.services, by: \.type)
    }

    private var groupedTypes: [String] {
        grouped.keys.sorted()
    }

    private func prettyType(_ raw: String) -> String {
        // "_http._tcp" -> "HTTP"
        let core = raw.split(separator: ".").first.map(String.init) ?? raw
        return core.replacingOccurrences(of: "_", with: "").uppercased()
    }
}

#Preview {
    NavigationStack { BonjourView() }
}
