//
//  LANScannerView.swift
//  Thin shell over LANScanner. Streams discovered hosts with MAC, vendor, and
//  reverse-DNS hostname. Copyable ResultRows.
//

import SwiftUI

struct LANScannerView: View {
    @State private var scanner = LANScanner()

    /// Sub-millisecond LAN RTTs round to 0 — show them as "<1 ms".
    static func latencyLabel(_ seconds: TimeInterval) -> String {
        let ms = seconds * 1000
        return ms < 1 ? "<1 ms" : String(format: "%.0f ms", ms)
    }

    var body: some View {
        List {
            Section {
                if let subnet = scanner.subnet {
                    ResultRow("Subnet", subnet)
                }
                ResultRow("Hosts found", "\(scanner.hosts.count)")
                if case .scanning(let done, let total) = scanner.state {
                    ResultRow("Swept", "\(done)/\(total)")
                } else if case .enriching = scanner.state {
                    Label("Reading ARP & resolving names…", systemImage: "ellipsis")
                        .foregroundStyle(.octetMuted)
                } else if case .failed(let message) = scanner.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.statusTimeout)
                }
            } header: {
                Text("Scan")
            } footer: {
                Text("Sweeps the local /24 to find live hosts and populate the ARP cache. ARP only shows hosts this device has talked to — hence the sweep runs first.")
            }

            if !scanner.hosts.isEmpty {
                Section("Hosts") {
                    ForEach(scanner.hosts) { host in
                        HStack(alignment: .top, spacing: 10) {
                            // Every host that turns up in the sweep is live.
                            Circle().fill(.statusOnline).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                ResultRow(host.hostname ?? host.ip, host.mac ?? "—")
                                if host.ip == scanner.selfIP || host.isGateway {
                                    HStack(spacing: 6) {
                                        if host.ip == scanner.selfIP { Text("This device") }
                                        if host.isGateway { Text("Gateway") }
                                    }
                                    .font(.caption2).foregroundStyle(.octetAccent)
                                }
                                if host.hostname != nil {
                                    Text(host.ip).font(.caption2).foregroundStyle(.octetMuted)
                                }
                                if let hint = host.deviceHint {
                                    Text(hint).font(.caption2).foregroundStyle(.octetMuted)
                                }
                                if let latency = host.latency {
                                    Text(LANScannerView.latencyLabel(latency))
                                        .font(.caption2).foregroundStyle(.octetMuted)
                                }
                                if !host.openPorts.isEmpty {
                                    Text("open: " + host.openPorts.map { PortList.serviceName(for: $0) ?? String($0) }.joined(separator: ", "))
                                        .font(.caption2).foregroundStyle(.octetMuted)
                                }
                                if let tls = host.tlsName {
                                    Text("cert: \(tls)").font(.caption2).foregroundStyle(.octetMuted)
                                }
                                if let vendor = host.vendor {
                                    Text(vendor).font(.caption2).foregroundStyle(.octetMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
        .octetScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scanner.isScanning {
                    Button("Stop", systemImage: "stop.fill") { scanner.cancel() }
                } else {
                    Button("Scan", systemImage: "rectangle.3.group") { scanner.start() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Scans only your local subnet, fully on-device.")
                .font(.caption2).foregroundStyle(.octetMuted)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }
}

#Preview {
    NavigationStack { LANScannerView() }
}
