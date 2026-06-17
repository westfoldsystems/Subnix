//
//  PingView.swift
//  Thin shell over PingEngine: host + count, streaming per-packet RTTs and a
//  live summary (loss, min/avg/max/stddev). Copyable ResultRows.
//

import SwiftUI

struct PingView: View {
    @State private var host = "1.1.1.1"
    @State private var count = 5
    @State private var engine = PingEngine()

    var body: some View {
        Form {
            Section("Target") {
                TextField("Host or IP", text: $host)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(run)
                Stepper("Packets: \(count)", value: $count, in: 1...20)
            }

            switch engine.state {
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            case .idle:
                EmptyView()
            default:
                let stats = engine.statistics
                Section("Summary") {
                    ResultRow("Transmitted", "\(stats.transmitted)")
                    ResultRow("Received", "\(stats.received)")
                    ResultRow("Loss", String(format: "%.0f%%", stats.lossPercent))
                    if let mn = stats.minMS, let avg = stats.avgMS, let mx = stats.maxMS, let sd = stats.stddevMS {
                        ResultRow("min/avg/max", String(format: "%.1f / %.1f / %.1f ms", mn, avg, mx))
                        ResultRow("stddev", String(format: "%.1f ms", sd))
                    }
                }
                if !engine.probes.isEmpty {
                    Section("Packets") {
                        ForEach(engine.probes) { probe in
                            ResultRow("seq \(probe.seq)",
                                      probe.rtt.map { String(format: "%.1f ms", $0 * 1000) } ?? "timed out")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if engine.isPinging {
                    Button("Stop", systemImage: "stop.fill") { engine.cancel() }
                } else {
                    Button("Ping", systemImage: "wave.3.right", action: run)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Sends ICMP echo to the host you type. ICMP availability depends on the platform/sandbox.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }

    private func run() { engine.start(host: host, count: count) }
}

#Preview {
    NavigationStack { PingView() }
}
