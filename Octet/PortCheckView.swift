//
//  PortCheckView.swift
//  Thin shell over PortScanner. Type a host, scan a single port / list / range
//  or the common-ports preset, watch results stream in. Output is copyable
//  ResultRows.
//

import SwiftUI

struct PortCheckView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case custom = "Ports"
        case preset = "Common"
        var id: String { rawValue }
    }

    @State private var host = ""
    @State private var portSpec = "443"
    @State private var mode: Mode = .custom
    @State private var parseError: String?

    @State private var scanner = PortScanner()

    var body: some View {
        Form {
            Section("Target") {
                TextField("Host or IP, e.g. example.com", text: $host)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                Picker("Ports", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .custom {
                    TextField("e.g. 22, 80, 443, 8000-8010", text: $portSpec)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                } else {
                    Text("\(PortList.common.count) common ports (web, mail, SSH, DB, RDP…)")
                        .font(.caption)
                        .foregroundStyle(.octetMuted)
                }

                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.statusTimeout)
                }
            }

            if !scanner.results.isEmpty {
                Section(resultsHeader) {
                    ForEach(scanner.results) { result in
                        ResultRow(label(for: result), value(for: result), valueColor: color(for: result))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .octetScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scanner.isScanning {
                    Button("Stop", systemImage: "stop.fill") { scanner.cancel() }
                } else {
                    Button("Scan", systemImage: "bolt.horizontal") { startScan() }
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Connect-scan to the host you typed only. Nothing else is contacted.")
                .font(.caption2)
                .foregroundStyle(.octetMuted)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }

    // MARK: - Actions

    private func startScan() {
        let ports: [Int]
        do {
            ports = mode == .preset ? PortList.common : try PortList.parse(portSpec)
            parseError = nil
        } catch {
            parseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        scanner.scan(host: host, ports: ports)
    }

    // MARK: - Formatting

    private var resultsHeader: String {
        let open = scanner.results.filter { $0.status == .open }.count
        switch scanner.state {
        case .scanning(let done, let total): return "Scanning \(done)/\(total) — \(open) open"
        default:                             return "\(open) open of \(scanner.results.count)"
        }
    }

    private func label(for result: PortProbeResult) -> String {
        if let name = PortList.serviceName(for: result.port) { return "Port \(result.port) · \(name)" }
        return "Port \(result.port)"
    }

    private func value(for result: PortProbeResult) -> String {
        switch result.status {
        case .open:
            if let latency = result.latency {
                return String(format: "open · %.0f ms", latency * 1000)
            }
            return "open"
        case .closed:        return "closed"
        case .timedOut:      return "timed out"
        case .error(let m):  return "error · \(m)"
        }
    }

    private func color(for result: PortProbeResult) -> Color {
        switch result.status {
        case .open:     .statusOnline
        case .closed:   .statusError
        case .timedOut: .statusTimeout
        case .error:    .statusTimeout
        }
    }
}

#Preview {
    NavigationStack { PortCheckView() }
}
