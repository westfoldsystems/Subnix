//
//  OUIView.swift
//  Thin SwiftUI shell over OUILookup. Enter a MAC, see its manufacturer from the
//  bundled IEEE table. Degrades clearly when no database is bundled yet.
//

import SwiftUI

struct OUIView: View {
    @State private var macInput = "00:1b:63:84:45:e6"
    // Loaded once from the bundle; empty until a database is sourced.
    private let database = OUILookup.bundled()

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

            if database.isEmpty {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No OUI database bundled")
                            Text("Vendor lookup needs the IEEE MA-L registry bundled as oui-mal.tsv. See SupportingFiles/Info-plist-setup.md.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray")
                    }
                }
            }

            if let mac = parsedMAC {
                Section("Result") {
                    ResultRow("OUI", mac.oui.map { String(format: "%02X", $0) }.joined(separator: ":"))
                    if !database.isEmpty {
                        ResultRow("Vendor", database.vendor(for: mac) ?? "Not found")
                    }
                    ResultRow("Administration", mac.isLocallyAdministered ? "Locally administered" : "Globally unique (OUI)")
                }
            } else {
                Section {
                    Label("Enter a valid 48-bit MAC address.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("Lookup is fully offline — no IEEE API is contacted.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }
}

#Preview {
    NavigationStack { OUIView() }
}
