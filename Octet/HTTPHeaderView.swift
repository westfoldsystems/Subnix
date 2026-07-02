//
//  HTTPHeaderView.swift
//  Thin shell over HTTPInspector: enter a URL, see the redirect chain, the final
//  status, surfaced security headers, and the full header set. Copyable rows.
//

import SwiftUI

struct HTTPHeaderView: View {
    @State private var url = ""
    @State private var inspector = HTTPInspector()

    var body: some View {
        Form {
            Section("URL") {
                TextField("example.com or https://example.com/path", text: $url)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(inspect)
            }

            switch inspector.state {
            case .idle:
                EmptyView()
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Requesting…").foregroundStyle(.octetMuted)
                    }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.statusTimeout)
                }
            case .done(let report):
                reportSections(report)
            }
        }
        .formStyle(.grouped)
        .octetScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if inspector.isLoading {
                    Button("Stop", systemImage: "stop.fill") { inspector.cancel() }
                } else {
                    Button("Inspect", systemImage: "magnifyingglass", action: inspect)
                        .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Contacts only the URL you enter and the hosts it redirects to.")
                .font(.caption2)
                .foregroundStyle(.octetMuted)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }

    @ViewBuilder
    private func reportSections(_ report: HTTPReport) -> some View {
        if !report.chain.isEmpty {
            Section("Redirect chain (\(report.chain.count))") {
                ForEach(report.chain) { hop in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hop.status) \(hop.statusText)")
                            .font(.system(.callout, design: .monospaced))
                        Text(hop.url)
                            .font(.caption)
                            .foregroundStyle(.octetMuted)
                        if let location = hop.location {
                            Text("→ \(location)")
                                .font(.caption)
                                .foregroundStyle(.octetAccent)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }

        Section("Final response") {
            ResultRow("URL", report.finalURL)
            ResultRow("Status", "\(report.status) \(report.statusText)")
            ResultRow("Method", report.method)
            ResultRow("Server", report.server ?? "— not set")
        }

        Section("Security headers") {
            ForEach(report.security) { header in
                ResultRow(header.name, header.value ?? "— not set")
            }
        }

        Section("All response headers (\(report.headers.count))") {
            ForEach(report.headers) { field in
                ResultRow(field.name, field.value)
            }
        }
    }

    private func inspect() {
        inspector.inspect(urlString: url)
    }
}

#Preview {
    NavigationStack { HTTPHeaderView() }
}
