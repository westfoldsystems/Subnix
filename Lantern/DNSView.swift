//
//  DNSView.swift
//  Thin shell over DNSClient: name + record type + resolver, with answer/
//  authority/additional sections. Copyable ResultRows showing data + TTL.
//

import SwiftUI

struct DNSView: View {
    @State private var name = "example.com"
    @State private var type: DNSRecordType = .a
    @State private var resolver: DNSResolver = .cloudflare
    @State private var customResolver = ""
    @State private var client = DNSClient()

    var body: some View {
        Form {
            Section("Query") {
                TextField("Name or IP (PTR)", text: $name)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(run)

                Picker("Type", selection: $type) {
                    ForEach(DNSRecordType.allCases) { Text($0.label).tag($0) }
                }

                Picker("Resolver", selection: $resolver) {
                    ForEach(DNSResolver.allCases) { Text($0.rawValue).tag($0) }
                }
                if resolver == .custom {
                    TextField("Resolver IP", text: $customResolver)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                }
            }

            switch client.state {
            case .idle:
                EmptyView()
            case .querying:
                Section {
                    HStack(spacing: 12) { ProgressView(); Text("Querying…").foregroundStyle(.secondary) }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            case .done(let response, let viaTCP):
                resultSections(response, viaTCP: viaTCP)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if client.isQuerying {
                    Button("Stop", systemImage: "stop.fill") { client.cancel() }
                } else {
                    Button("Query", systemImage: "magnifyingglass", action: run)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Queries only the resolver you select.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }

    @ViewBuilder
    private func resultSections(_ response: DNSResponse, viaTCP: Bool) -> some View {
        Section("Status") {
            ResultRow("Response", response.responseCodeText)
            ResultRow("Transport", viaTCP ? "TCP (truncated UDP)" : "UDP")
        }
        recordSection("Answers", response.answers)
        recordSection("Authority", response.authority)
        recordSection("Additional", response.additional)
    }

    @ViewBuilder
    private func recordSection(_ title: String, _ records: [DNSRecord]) -> some View {
        if !records.isEmpty {
            Section("\(title) (\(records.count))") {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        ResultRow("\(record.typeLabel)  \(record.name)", record.data)
                        Text("TTL \(record.ttl)s")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func run() {
        client.query(name: name, type: type, server: resolver.serverIP(custom: customResolver))
    }
}

#Preview {
    NavigationStack { DNSView() }
}
