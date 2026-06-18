//
//  LANScannerView.swift
//  Thin shell over LANScanner. Streams discovered hosts with MAC, vendor, and
//  reverse-DNS hostname. Copyable ResultRows.
//

import SwiftUI

struct LANScannerView: View {
    @State private var scanner = LANScanner()

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
                        VStack(alignment: .leading, spacing: 2) {
                            ResultRow(host.hostname ?? host.ip, host.mac ?? "—")
                            if host.hostname != nil { Text(host.ip).font(.caption2).foregroundStyle(.octetMuted) }
                            if let vendor = host.vendor {
                                Text(vendor).font(.caption2).foregroundStyle(.octetMuted)
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
