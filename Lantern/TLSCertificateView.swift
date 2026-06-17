//
//  TLSCertificateView.swift
//  Thin shell over TLSInspector: enter host[:port], see the leaf cert's subject/
//  issuer/validity/key/serial, every SAN, and the rest of the chain. Copyable
//  ResultRows.
//

import SwiftUI

struct TLSCertificateView: View {
    @State private var host = ""
    @State private var portText = "443"
    @State private var inspector = TLSInspector()

    var body: some View {
        Form {
            Section("Target") {
                TextField("Host, e.g. example.com", text: $host)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(inspect)

                TextField("Port", text: $portText)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            switch inspector.state {
            case .idle:
                EmptyView()
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Handshaking…").foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            case .done(let report):
                reportSections(report)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if inspector.isLoading {
                    Button("Stop", systemImage: "stop.fill") { inspector.cancel() }
                } else {
                    Button("Inspect", systemImage: "lock.shield", action: inspect)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Connects only to the host you enter, and only to read its certificate.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }

    @ViewBuilder
    private func reportSections(_ report: TLSReport) -> some View {
        if let leaf = report.leaf {
            Section("Leaf certificate") {
                ResultRow("Subject CN", leaf.subjectCN ?? "—")
                ResultRow("Issuer CN", leaf.issuerCN ?? "—")
                if let notBefore = leaf.notBefore {
                    ResultRow("Valid from", notBefore.formatted(date: .abbreviated, time: .shortened))
                }
                if let notAfter = leaf.notAfter {
                    ResultRow("Valid until", notAfter.formatted(date: .abbreviated, time: .shortened))
                    ResultRow("Expires", expiry(notAfter))
                }
                ResultRow("Signature", leaf.signatureAlgorithm ?? "—")
                ResultRow("Public key", keyDescription(leaf))
                ResultRow("Serial", leaf.serialHex ?? "—")
            }

            Section("Subject Alternative Names (\(leaf.sans.count))") {
                if leaf.sans.isEmpty {
                    Text("None present").foregroundStyle(.secondary)
                } else {
                    ForEach(leaf.sans, id: \.self) { san in
                        ResultRow(san.kind.rawValue, san.value)
                    }
                }
            }
        }

        if report.chain.count > 1 {
            Section("Chain (\(report.chain.count))") {
                ForEach(report.chain) { cert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cert.subjectCN ?? "—")
                            .font(.callout)
                        Text("issued by \(cert.issuerCN ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Formatting

    private func keyDescription(_ cert: CertSummary) -> String {
        switch (cert.keyType, cert.keyBits) {
        case (let type?, let bits?): return "\(type) \(bits)-bit"
        case (let type?, nil):       return type
        default:                     return "—"
        }
    }

    private func expiry(_ date: Date) -> String {
        let days = Int((date.timeIntervalSinceNow / 86_400).rounded(.towardZero))
        if days < 0 { return "expired \(-days) day\(-days == 1 ? "" : "s") ago" }
        if days == 0 { return "today" }
        return "in \(days) day\(days == 1 ? "" : "s")"
    }

    private func inspect() {
        inspector.inspect(host: host, port: Int(portText) ?? 443)
    }
}

#Preview {
    NavigationStack { TLSCertificateView() }
}
