//
//  ConvertersView.swift
//  Thin SwiftUI shell over IPv4Converter + MACAddress. Two live, bidirectional
//  converters: IPv4 base conversion and MAC normalisation. Type in any field's
//  format; the rest follow. All output is copyable ResultRows.
//

import SwiftUI

struct ConvertersView: View {
    // IPv4: one editable field plus the format it's written in.
    @State private var ipv4Input = "192.168.1.1"
    @State private var ipv4Format: IPv4Converter.Format = .dotted
    @State private var ipv4Forms: IPv4Converter.Forms?
    @State private var ipv4Error: String?

    // MAC normaliser.
    @State private var macInput = "001b.6384.45e6"
    @State private var mac: MACAddress?
    @State private var macError: String?

    var body: some View {
        Form {
            Section("IPv4 base converter") {
                Picker("Input format", selection: $ipv4Format) {
                    ForEach(IPv4Converter.Format.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Value", text: $ipv4Input)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif

                if let ipv4Error {
                    Label(ipv4Error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if let forms = ipv4Forms {
                    ResultRow("Dotted", forms.dotted)
                    ResultRow("Hex", forms.hex)
                    ResultRow("Binary", forms.binary)
                    ResultRow("Integer", forms.integer)
                }
            }

            Section("MAC normaliser") {
                TextField("Any of colon / hyphen / dot / bare", text: $macInput)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                if let macError {
                    Label(macError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if let mac {
                    ResultRow("Colon", mac.colon)
                    ResultRow("Hyphen", mac.hyphen)
                    ResultRow("Dot (Cisco)", mac.dot)
                    ResultRow("Bare", mac.bare)
                    ResultRow("OUI", mac.oui.map { String(format: "%02X", $0) }.joined(separator: ":"))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: ipv4Input) { _, newInput in convertIPv4(newInput, as: ipv4Format) }
        .onChange(of: ipv4Format) { _, newFormat in reformatIPv4(to: newFormat) }
        .onChange(of: macInput) { _, _ in convertMAC() }
        .onAppear {
            convertIPv4(ipv4Input, as: ipv4Format)
            convertMAC()
        }
    }

    private func convertIPv4(_ text: String, as format: IPv4Converter.Format) {
        do {
            let value = try IPv4Converter.parse(text, as: format)
            ipv4Forms = IPv4Converter.forms(from: value)
            ipv4Error = nil
        } catch {
            ipv4Forms = nil
            ipv4Error = (error as? LocalizedError)?.errorDescription
                      ?? error.localizedDescription
        }
    }

    /// Flipping the input format transcodes the current value into the new
    /// format rather than reinterpreting the old text — so picking "Hex" while
    /// the field reads 192.168.1.1 rewrites it to 0xC0A80101 instead of erroring.
    private func reformatIPv4(to newFormat: IPv4Converter.Format) {
        if let forms = ipv4Forms {
            let text = forms.string(for: newFormat)
            ipv4Input = text
            convertIPv4(text, as: newFormat)
        } else {
            convertIPv4(ipv4Input, as: newFormat)
        }
    }

    private func convertMAC() {
        do {
            mac = try MACAddress.parse(macInput)
            macError = nil
        } catch {
            mac = nil
            macError = (error as? LocalizedError)?.errorDescription
                     ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { ConvertersView() }
}
