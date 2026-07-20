//
//  PortScanner.swift
//  TCP connect-scan over NWConnection. iOS has no raw sockets, so this is an
//  honest connect-scan: we actually open the TCP handshake and report what the
//  stack tells us. Probes run concurrently with a bounded in-flight cap so one
//  hung port can't stall the sweep, each with its own short timeout.
//
//  Privacy: contacts ONLY the host:port the user typed. Same @MainActor
//  @Observable + Task{@MainActor} hop pattern as BonjourScanner — the NWConnection
//  callbacks land on a background queue and we bounce observed state to main.
//

import Foundation
import Network
import Observation
import os

// These are plain Sendable value types at file scope (not nested in the
// @MainActor class) so they stay nonisolated and can cross into the background
// probe — same reason BonjourScanner.DiscoveredService works off the main actor.

enum PortStatus: Equatable, Hashable, Sendable {
    case open
    case closed          // refused / reset — host answered "no"
    case timedOut        // no answer in time (filtered / unreachable)
    case error(String)
}

struct PortProbeResult: Identifiable, Hashable, Sendable {
    let id = UUID()
    let port: Int
    let status: PortStatus
    let latency: TimeInterval?   // seconds, only for .open
}

@MainActor
@Observable
final class PortScanner {

    enum ScanState: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case finished
        case cancelled
    }

    private(set) var results: [PortProbeResult] = []
    private(set) var state: ScanState = .idle

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    // MARK: - Control

    func scan(host rawHost: String,
              ports: [Int],
              timeout: TimeInterval = 2,
              maxInFlight: Int = 16) {
        cancel()
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !ports.isEmpty else { state = .idle; return }

        results = []
        state = .scanning(done: 0, total: ports.count)

        scanTask = Task { [weak self] in
            await self?.run(host: host, ports: ports, timeout: timeout, maxInFlight: maxInFlight)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { state = .cancelled }
    }

    // MARK: - Driver (main actor)

    private func run(host: String, ports: [Int], timeout: TimeInterval, maxInFlight: Int) async {
        let total = ports.count
        var done = 0

        await withTaskGroup(of: PortProbeResult.self) { group in
            var next = ports.makeIterator()

            // Seed up to the in-flight cap, then top up one-for-one as each lands.
            for _ in 0..<min(maxInFlight, total) {
                guard let port = next.next() else { break }
                group.addTask { await Self.probe(host: host, port: port, timeout: timeout) }
            }

            while let result = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                done += 1
                insert(result)
                state = .scanning(done: done, total: total)

                if let port = next.next() {
                    group.addTask { await Self.probe(host: host, port: port, timeout: timeout) }
                }
            }
        }

        state = Task.isCancelled ? .cancelled : .finished
    }

    /// Keep results ordered by port as they stream in.
    private func insert(_ result: PortProbeResult) {
        let index = results.firstIndex { $0.port > result.port } ?? results.endIndex
        results.insert(result, at: index)
    }

    // MARK: - Probe (isolation-free: runs off the main actor)

    /// One TCP connect attempt. Pure network work with Sendable in/out, so it's
    /// `nonisolated` and safe to run as a detached child task.
    nonisolated static func probe(host: String,
                                  port: Int,
                                  timeout: TimeInterval) async -> PortProbeResult {
        guard let raw = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: raw) else {
            return PortProbeResult(port: port, status: .error("invalid port"), latency: nil)
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "app.subnix.portscan.\(port)")
        let start = DispatchTime.now()
        // Both the state handler and the timeout run on `queue`, but the compiler
        // still needs a Sendable-safe one-shot to gate the single continuation resume.
        let resumed = OSAllocatedUnfairLock(initialState: false)

        let status: PortStatus = await withCheckedContinuation { continuation in
            @Sendable func finish(_ status: PortStatus) {
                let isFirst = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if isFirst { continuation.resume(returning: status) }
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    finish(.open)
                case .failed(let error):
                    finish(Self.classify(error))
                case .waiting(let error):
                    // Refused arrives as .waiting; that's a definitive "closed".
                    // Other waits (no route, etc.) ride until the timeout fires.
                    if case .posix(.ECONNREFUSED) = error { finish(.closed) }
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) { finish(.timedOut) }
            connection.start(queue: queue)
        }

        connection.cancel()

        var latency: TimeInterval?
        if case .open = status {
            latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        }
        return PortProbeResult(port: port, status: status, latency: latency)
    }

    nonisolated private static func classify(_ error: NWError) -> PortStatus {
        if case .posix(let code) = error {
            switch code {
            case .ECONNREFUSED, .ECONNRESET: return .closed
            case .ETIMEDOUT:                 return .timedOut
            default:                         return .error(error.localizedDescription)
            }
        }
        return .error(error.localizedDescription)
    }
}
