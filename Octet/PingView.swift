//
//  PingView.swift
//  Thin shell over PingEngine: host + count, streaming per-packet RTTs and a
//  live summary (loss, min/avg/max/stddev). Copyable ResultRows.
//

import SwiftUI

struct PingView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case icmp = "ICMP"
        case tcp = "TCP"
        var id: String { rawValue }
    }

    @State private var host = "1.1.1.1"
    @State private var count = 5
    // TCP is the default: it works in the macOS sandbox and on iOS regardless of
    // whether ICMP is permitted. Users can switch to ICMP explicitly.
    @State private var mode: Mode = .tcp
    @State private var port = "443"
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

                Picker("Method", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .tcp {
                    TextField("Port", text: $port)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Stepper("Packets: \(count)", value: $count, in: 1...20)
            }

            switch engine.state {
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.statusTimeout)
                }
            case .idle:
                EmptyView()
            default:
                let stats = engine.statistics
                Section("Summary") {
                    ResultRow("Transmitted", "\(stats.transmitted)")
                    ResultRow("Received", "\(stats.received)")
                    ResultRow("Loss", String(format: "%.0f%%", stats.lossPercent),
                              valueColor: stats.lossPercent == 0 ? .statusOnline
                                        : stats.lossPercent >= 100 ? .statusError : .statusTimeout)
                    if let mn = stats.minMS, let avg = stats.avgMS, let mx = stats.maxMS, let sd = stats.stddevMS {
                        ResultRow("min/avg/max", String(format: "%.1f / %.1f / %.1f ms", mn, avg, mx))
                        ResultRow("stddev", String(format: "%.1f ms", sd))
                    }
                }
                if !engine.probes.isEmpty {
                    Section("Packets") {
                        ForEach(engine.probes) { probe in
                            ResultRow("seq \(probe.seq)",
                                      probe.rtt.map { String(format: "%.1f ms", $0 * 1000) } ?? "timed out",
                                      valueColor: probe.rtt == nil ? .statusTimeout : .statusOnline)
                        }
                    }
                }
            }

            if suggestTCP {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No ICMP replies. ICMP is often blocked (e.g. the macOS sandbox) — TCP works anywhere.",
                              systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.octetMuted)
                        Button("Retry with TCP") {
                            mode = .tcp
                            run()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.octetAccent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .octetScreen()
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
            Text(mode == .icmp
                 ? "ICMP echo to the host you type. ICMP availability depends on the platform/sandbox — try TCP if it’s blocked."
                 : "TCP connect timing to host:port. A refused port still counts as reachable. Works where ICMP is blocked.")
                .font(.caption2).foregroundStyle(.octetMuted)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }

    /// After an ICMP run that got no replies (or couldn't open the socket), nudge
    /// the user toward TCP — the mode that works in the sandbox and on the sim.
    private var suggestTCP: Bool {
        guard mode == .icmp else { return false }
        switch engine.state {
        case .finished: return engine.statistics.transmitted > 0 && engine.statistics.received == 0
        case .failed:   return true
        default:        return false
        }
    }

    private func run() {
        switch mode {
        case .icmp:
            engine.start(host: host, count: count, transport: .icmp)
        case .tcp:
            let p = Int(port.trimmingCharacters(in: .whitespaces)) ?? 443
            engine.start(host: host, count: count, transport: .tcp(port: p))
        }
    }
}

#Preview {
    NavigationStack { PingView() }
}
