//
//  DNSClient.swift
//  DNS-over-UDP transport with TCP fallback, driving the hardened DNSMessage
//  codec. Contacts only the resolver the user selects. The query is built and
//  the response decoded on the main actor; only the raw byte exchange runs off
//  it (and we peek the TC bit on the raw bytes to decide the TCP retry, so the
//  codec never has to leave the main actor).
//
//  Note: a "System resolver" option is intentionally not shipped — discovering
//  the OS resolver needs res_getservers via a C bridging header and behaves
//  differently in-sandbox. Use Custom to point at any resolver, including your
//  own. See README / the Phase 3 summary.
//

import Foundation
import Network
import Observation
import os

enum DNSResolver: String, CaseIterable, Identifiable, Sendable {
    case cloudflare = "1.1.1.1"
    case google = "8.8.8.8"
    case quad9 = "9.9.9.9"
    case custom = "Custom"

    var id: String { rawValue }
    func serverIP(custom: String) -> String {
        self == .custom ? custom.trimmingCharacters(in: .whitespaces) : rawValue
    }
}

enum DNSTransportError: LocalizedError, Equatable {
    case timeout
    case noResponse
    case badServer

    var errorDescription: String? {
        switch self {
        case .timeout:    "The resolver didn’t respond in time."
        case .noResponse: "The resolver returned an empty response."
        case .badServer:  "Enter a valid resolver address."
        }
    }
}

@MainActor
@Observable
final class DNSClient {

    enum State {
        case idle
        case querying
        case done(response: DNSResponse, viaTCP: Bool)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isQuerying: Bool {
        if case .querying = state { return true }
        return false
    }

    // MARK: - Control

    func query(name rawName: String, type: DNSRecordType, server: String) {
        cancel()
        let server = server.trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty else { state = .failed(DNSTransportError.badServer.localizedDescription); return }

        // For PTR on a bare IPv4, build the in-addr.arpa name automatically.
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        let name = (type == .ptr ? DNSMessage.reverseName(forIPv4: trimmed) : nil) ?? trimmed
        guard !name.isEmpty else { state = .idle; return }

        let queryBytes = DNSMessage.query(id: UInt16.random(in: 0...UInt16.max),
                                          name: name, type: type.rawValue)
        state = .querying

        task = Task { @MainActor [weak self] in
            do {
                let (raw, viaTCP) = try await Self.exchange(query: queryBytes, server: server)
                guard !Task.isCancelled else { return }
                let response = try DNSMessage.decode(raw)
                self?.state = .done(response: response, viaTCP: viaTCP)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed((error as? LocalizedError)?.errorDescription
                                      ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Exchange (isolation-free; raw bytes only, no codec)

    static func exchange(query: [UInt8], server: String) async throws -> (bytes: [UInt8], viaTCP: Bool) {
        let udp = try await sendUDP(query, server: server)
        // Peek the TC (truncation) bit in the flags high byte without decoding.
        let truncated = udp.count >= 3 && (udp[2] & 0x02) != 0
        if truncated {
            let tcp = try await sendTCP(query, server: server)
            return (tcp, true)
        }
        return (udp, false)
    }

    static func sendUDP(_ query: [UInt8], server: String,
                        port: UInt16 = 53, timeout: TimeInterval = 5) async throws -> [UInt8] {
        let connection = NWConnection(host: NWEndpoint.Host(server),
                                      port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        let queue = DispatchQueue(label: "systems.westfold.lantern.dns.udp")
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            @Sendable func finish(_ result: Result<[UInt8], Error>) {
                let isFirst = resumed.withLock { done -> Bool in
                    if done { return false }; done = true; return true
                }
                if isFirst { connection.cancel(); cont.resume(with: result) }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(query), completion: .contentProcessed { error in
                        if let error { finish(.failure(error)); return }
                        connection.receiveMessage { data, _, _, error in
                            if let error { finish(.failure(error)) }
                            else if let data, !data.isEmpty { finish(.success([UInt8](data))) }
                            else { finish(.failure(DNSTransportError.noResponse)) }
                        }
                    })
                case .failed(let error):  finish(.failure(error))
                case .waiting(let error): finish(.failure(error))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(DNSTransportError.timeout)) }
            connection.start(queue: queue)
        }
    }

    static func sendTCP(_ query: [UInt8], server: String,
                        port: UInt16 = 53, timeout: TimeInterval = 5) async throws -> [UInt8] {
        // DNS over TCP frames each message with a 2-byte big-endian length.
        let framed = [UInt8(query.count >> 8), UInt8(query.count & 0xFF)] + query
        let connection = NWConnection(host: NWEndpoint.Host(server),
                                      port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "systems.westfold.lantern.dns.tcp")
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let buffer = OSAllocatedUnfairLock(initialState: [UInt8]())

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            @Sendable func finish(_ result: Result<[UInt8], Error>) {
                let isFirst = resumed.withLock { done -> Bool in
                    if done { return false }; done = true; return true
                }
                if isFirst { connection.cancel(); cont.resume(with: result) }
            }

            // Pull bytes until we have the 2-byte length prefix plus that many bytes.
            @Sendable func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, _, isComplete, error in
                    if let error { finish(.failure(error)); return }
                    if let data, !data.isEmpty { buffer.withLock { $0 += [UInt8](data) } }

                    let current = buffer.withLock { $0 }
                    if current.count >= 2 {
                        let expected = (Int(current[0]) << 8) | Int(current[1])
                        if current.count >= expected + 2 {
                            finish(.success(Array(current[2..<(2 + expected)])))
                            return
                        }
                    }
                    if isComplete { finish(.failure(DNSTransportError.noResponse)); return }
                    receiveLoop()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(framed), completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) } else { receiveLoop() }
                    })
                case .failed(let error):  finish(.failure(error))
                case .waiting(let error): finish(.failure(error))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(DNSTransportError.timeout)) }
            connection.start(queue: queue)
        }
    }
}
