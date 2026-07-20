//
//  WhatsMyIPView.swift
//  Local interfaces shown automatically (offline); public IPv4/IPv6 are separate,
//  opt-in reveals that name the provider being contacted. Copyable ResultRows.
//

import SwiftUI

struct WhatsMyIPView: View {
    @State private var model = WhatsMyIP()

    var body: some View {
        Form {
            Section("Local interfaces") {
                if model.interfaces.isEmpty {
                    Text("No active interfaces found.").foregroundStyle(.subnixMuted)
                } else {
                    ForEach(model.interfaces) { iface in
                        ResultRow(label(for: iface), iface.address)
                    }
                }
            }

            Section {
                publicRow(.v4, lookup: model.v4)
                publicRow(.v6, lookup: model.v6)
            } header: {
                Text("Public address")
            } footer: {
                Text("Tapping a reveal contacts an external provider (Cloudflare, falling back to ipify) — the only outside connection Subnix makes. IPv4 and IPv6 are independent; nothing is fetched until you tap.")
            }
        }
        .formStyle(.grouped)
        .subnixScreen()
        .onAppear { model.loadInterfaces() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func publicRow(_ family: IPFamily, lookup: WhatsMyIP.Lookup) -> some View {
        switch lookup {
        case .idle:
            Button {
                model.revealPublic(family)
            } label: {
                Label("Reveal public \(family.rawValue)", systemImage: "eye")
            }
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Contacting provider…").foregroundStyle(.subnixMuted)
            }
        case .value(let ip, let provider):
            VStack(alignment: .leading, spacing: 4) {
                ResultRow("Public \(family.rawValue)", ip)
                Text("via \(provider)")
                    .font(.caption)
                    .foregroundStyle(.subnixMuted)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.statusTimeout)
                Button("Try again") { model.revealPublic(family) }
                    .font(.callout)
            }
        }
    }

    private func label(for iface: NetInterface) -> String {
        var parts = ["\(iface.name) · \(iface.family)"]
        if iface.address == model.primaryAddress { parts.append("primary") }
        if iface.isLoopback { parts.append("loopback") }
        else if iface.isLinkLocal { parts.append("link-local") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { WhatsMyIPView() }
}
