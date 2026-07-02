//
//  SubnetView.swift
//  Live-updating subnet calculator UI. Recomputes on every keystroke; the
//  engine is cheap and pure so there's no need to debounce.
//

import SwiftUI

struct SubnetView: View {
    @State private var input = "192.168.1.0/24"
    @State private var result: SubnetCalculator.Result?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                TextField("e.g. 192.168.1.0/24", text: $input)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .onChange(of: input) { _, _ in calculate() }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.statusTimeout)
                }
            }

            if let r = result {
                Section("Network") {
                    ResultRow("CIDR", r.cidr)
                    ResultRow("Network", r.networkAddress)
                    if let b = r.broadcastAddress { ResultRow("Broadcast", b) }
                    ResultRow("Subnet mask", r.subnetMask)
                    ResultRow("Wildcard", r.wildcardMask)
                }

                Section("Hosts") {
                    if let f = r.firstUsableHost { ResultRow("First usable", f) }
                    if let l = r.lastUsableHost  { ResultRow("Last usable", l) }
                    ResultRow("Usable hosts", r.usableHostCount.formatted())
                    ResultRow("Total addresses", r.totalAddresses.formatted())
                }

                Section("Info") {
                    ResultRow("Legacy class", r.addressClass)
                    ResultRow("Private (RFC 1918)", r.isPrivate ? "Yes" : "No")
                }
            }
        }
        .formStyle(.grouped)
        .octetScreen()
        .onAppear(perform: calculate)
    }

    private func calculate() {
        do {
            result = try SubnetCalculator.calculate(input, defaultPrefix: 24)
            errorText = nil
        } catch {
            result = nil
            errorText = (error as? LocalizedError)?.errorDescription
                      ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { SubnetView() }
}
