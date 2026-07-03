//
//  OUIView.swift
//  Thin SwiftUI shell over OUIStore. Enter a MAC, see its manufacturer from the
//  bundled IEEE table. Shows the database source and offers an opt-in refresh
//  from the IEEE registry. Degrades clearly when no database is present.
//

import SwiftUI

struct OUIView: View {
    @State private var macInput = "00:1b:63:84:45:e6"
    // The shared, observable table (bundled or a downloaded refresh).
    @State private var store = OUIStore.shared

    private var parsedMAC: MACAddress? { try? MACAddress.parse(macInput) }

    var body: some View {
        Form {
            Section("MAC address") {
                TextField("e.g. 00:1b:63:84:45:e6", text: $macInput)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if let mac = parsedMAC {
                Section("Result") {
                    ResultRow("OUI", mac.oui.map { String(format: "%02X", $0) }.joined(separator: ":"))
                    if !store.isEmpty {
                        ResultRow("Vendor", store.vendor(for: mac) ?? "Not found")
                    }
                    ResultRow("Administration", mac.isLocallyAdministered ? "Locally administered" : "Globally unique (OUI)")
                }
            } else {
                Section {
                    Label("Enter a valid 48-bit MAC address.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.statusTimeout)
                }
            }

            Section {
                if store.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No OUI database")
                            Text("Tap Update to download the IEEE MA-L registry, or bundle oui-mal.tsv.")
                                .font(.caption).foregroundStyle(.octetMuted)
                        }
                    } icon: { Image(systemName: "tray") }
                } else {
                    ResultRow("Entries", "\(store.count)")
                    ResultRow("Source", sourceLabel)
                }

                switch store.state {
                case .updating:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Downloading IEEE registry…").foregroundStyle(.octetMuted)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.statusTimeout)
                default:
                    EmptyView()
                }

                Button {
                    store.update()
                } label: {
                    Label("Update from IEEE", systemImage: "arrow.down.circle")
                }
                .disabled(store.isUpdating)
                .tint(.octetAccent)
            } header: {
                Text("Database")
            } footer: {
                Text("Lookups are fully offline against the bundled table. “Update” is the only outside connection Octet makes here — it downloads the latest IEEE MA-L registry, and only when you tap it.")
            }
        }
        .formStyle(.grouped)
        .octetScreen()
    }

    private var sourceLabel: String {
        switch store.source {
        case .bundled:           return "Bundled"
        case .updated(let date): return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

#Preview {
    NavigationStack { OUIView() }
}
