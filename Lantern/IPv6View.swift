//
//  IPv6View.swift
//  Thin SwiftUI shell over IPv6Toolkit: canonicalisation, prefix math, and
//  EUI-64 from a MAC. Recomputes live; all output is copyable ResultRows.
//

import SwiftUI

struct IPv6View: View {
    @State private var address = "2001:db8::1"
    @State private var prefix = 64.0
    @State private var mac = "00:1b:63:84:45:e6"

    @State private var parsed: IPv6Toolkit.Address?
    @State private var prefixReport: IPv6Toolkit.PrefixReport?
    @State private var addressError: String?

    @State private var eui64: IPv6Toolkit.EUI64Report?
    @State private var macError: String?

    var body: some View {
        Form {
            Section("Address") {
                TextField("e.g. 2001:db8::1 or ::ffff:1.2.3.4", text: $address)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                if let addressError {
                    Label(addressError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            if let parsed {
                Section("Canonical") {
                    ResultRow("Compressed", parsed.compressed)
                    ResultRow("Expanded", parsed.expanded)
                }
            }

            if let report = prefixReport {
                Section("Prefix /\(Int(prefix))") {
                    Stepper("Prefix length: \(Int(prefix))", value: $prefix, in: 0...128)
                    ResultRow("Network", report.network)
                    ResultRow("First address", report.firstAddress)
                    ResultRow("Last address", report.lastAddress)
                    ResultRow("Addresses", "2^\(report.addressCountExponent)")
                    ResultRow("Addresses (exact)", report.addressCountDecimal)
                }
            }

            Section("EUI-64 from MAC") {
                TextField("e.g. 00:1b:63:84:45:e6", text: $mac)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                if let macError {
                    Label(macError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if let eui64 {
                    ResultRow("Interface ID", eui64.interfaceID)
                    ResultRow("Link-local", eui64.linkLocal)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: address) { _, _ in recomputeAddress() }
        .onChange(of: prefix) { _, _ in recomputeAddress() }
        .onChange(of: mac) { _, _ in recomputeMAC() }
        .onAppear {
            recomputeAddress()
            recomputeMAC()
        }
    }

    private func recomputeAddress() {
        do {
            let addr = try IPv6Toolkit.parse(address)
            parsed = addr
            prefixReport = try IPv6Toolkit.prefixReport(addr, prefix: Int(prefix))
            addressError = nil
        } catch {
            parsed = nil
            prefixReport = nil
            addressError = (error as? LocalizedError)?.errorDescription
                         ?? error.localizedDescription
        }
    }

    private func recomputeMAC() {
        do {
            let parsedMAC = try MACAddress.parse(mac)
            eui64 = IPv6Toolkit.eui64(from: parsedMAC)
            macError = nil
        } catch {
            eui64 = nil
            macError = (error as? LocalizedError)?.errorDescription
                     ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { IPv6View() }
}
