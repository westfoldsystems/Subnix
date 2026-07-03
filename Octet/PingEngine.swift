//
//  PingEngine.swift
//  ICMP echo (ping) over an unprivileged SOCK_DGRAM ICMP socket — iOS has no
//  raw sockets in-sandbox, and SOCK_DGRAM ICMP is the supported alternative.
//  This is a clean-room implementation: no SimplePing sample or third-party port
//  is used. ICMPv4 and ICMPv6 (echo type 8 / 128).
//
//  The blocking socket loop runs on a background queue and streams outcomes;
//  the @MainActor engine consumes them and updates observed state, same hop
//  pattern as BonjourScanner. Stats come from the pure PingStatistics.
//
//  DEVICE NOTE: ICMP socket permissions differ between simulator and a real
//  iPhone (and depend on the provisioning profile). Validated on macOS only;
//  iOS-device status is UNVERIFIED.
//

import Foundation
import Darwin
import Network
import Observation
import os

enum PingOutcome: Sendable {
    case reply(seq: Int, rtt: TimeInterval)
    case lost(seq: Int)
    case error(String)
}

/// How to probe reachability. ICMP is the real thing but is sandbox-restricted
/// on iOS; TCP connect-timing works anywhere outbound TCP is allowed.
enum PingTransport: Equatable, Sendable {
    case icmp
    case tcp(port: Int)
}

@MainActor
@Observable
final class PingEngine {

    struct Probe: Identifiable, Sendable {
        let id = UUID()
        let seq: Int
        let rtt: TimeInterval?   // nil = lost
    }

    enum State: Equatable {
        case idle
        case pinging
        case finished
        case failed(String)
    }

    private(set) var probes: [Probe] = []
    private(set) var state: State = .idle

    var statistics: PingStatistics { PingStatistics.compute(rtts: probes.map(\.rtt)) }
    var isPinging: Bool { state == .pinging }

    private var task: Task<Void, Never>?

    // MARK: - Control

    func start(host: String, count: Int = 5, transport: PingTransport = .icmp) {
        cancel()
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { state = .idle; return }
        probes = []
        state = .pinging

        let stream: AsyncStream<PingOutcome> = switch transport {
        case .icmp:            Self.stream(host: host, count: count)
        case .tcp(let port):   Self.tcpStream(host: host, port: port, count: count)
        }

        task = Task { @MainActor [weak self] in
            for await outcome in stream {
                if Task.isCancelled { break }
                switch outcome {
                case .reply(let seq, let rtt): self?.probes.append(Probe(seq: seq, rtt: rtt))
                case .lost(let seq):           self?.probes.append(Probe(seq: seq, rtt: nil))
                case .error(let message):      self?.state = .failed(message); return
                }
            }
            if self?.state == .pinging { self?.state = .finished }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Streaming (isolation-free; blocking I/O on a background queue)

    nonisolated static func stream(host: String, count: Int,
                                   interval: TimeInterval = 1,
                                   timeout: TimeInterval = 2) -> AsyncStream<PingOutcome> {
        AsyncStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            continuation.onTermination = { _ in cancelled.withLock { $0 = true } }
            DispatchQueue.global(qos: .utility).async {
                pingLoop(host: host, count: count, interval: interval, timeout: timeout,
                         isCancelled: { cancelled.withLock { $0 } },
                         emit: { continuation.yield($0) })
                continuation.finish()
            }
        }
    }

    // MARK: - TCP connect-ping (isolation-free; Network.framework)

    /// Reachability by TCP connect timing. A completed handshake OR a refusal
    /// (RST) both mean the host answered — that's the RTT; a timeout is a loss.
    /// Works wherever outbound TCP is allowed, including the iOS sandbox.
    nonisolated static func tcpStream(host: String, port: Int, count: Int,
                                      interval: TimeInterval = 1,
                                      timeout: TimeInterval = 2) -> AsyncStream<PingOutcome> {
        AsyncStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            continuation.onTermination = { _ in cancelled.withLock { $0 = true } }
            Task {
                guard UInt16(exactly: port) != nil else {
                    continuation.yield(.error("Port must be 1–65535.")); continuation.finish(); return
                }
                for seq in 0..<count {
                    if cancelled.withLock({ $0 }) { break }
                    if let rtt = await tcpConnectRTT(host: host, port: port, timeout: timeout) {
                        continuation.yield(.reply(seq: seq, rtt: rtt))
                    } else {
                        continuation.yield(.lost(seq: seq))
                    }
                    if seq < count - 1, !cancelled.withLock({ $0 }) {
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                }
                continuation.finish()
            }
        }
    }

    /// RTT to first definitive TCP response (ready or refused), or nil on timeout.
    nonisolated private static func tcpConnectRTT(host: String, port: Int,
                                                  timeout: TimeInterval) async -> TimeInterval? {
        guard let raw = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: raw) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "app.octet.tcpping")
        let start = DispatchTime.now()
        let resumed = OSAllocatedUnfairLock(initialState: false)

        let rtt: TimeInterval? = await withCheckedContinuation { cont in
            @Sendable func elapsed() -> TimeInterval {
                Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            }
            @Sendable func finish(_ value: TimeInterval?) {
                let isFirst = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if isFirst { cont.resume(returning: value) }
            }
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    finish(elapsed())
                case .waiting(let error):
                    // Refused (RST) means the host is up and answered — a hit.
                    if case .posix(.ECONNREFUSED) = error { finish(elapsed()) }
                case .failed:
                    finish(nil)
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
            connection.start(queue: queue)
        }

        connection.cancel()
        return rtt
    }

    // MARK: - Socket work

    nonisolated private static func pingLoop(host: String, count: Int,
                                             interval: TimeInterval, timeout: TimeInterval,
                                             isCancelled: () -> Bool,
                                             emit: (PingOutcome) -> Void) {
        guard let (addr, family) = resolve(host) else {
            emit(.error("Couldn’t resolve “\(host)”.")); return
        }
        let isV6 = family == AF_INET6
        let fd = socket(family, SOCK_DGRAM, isV6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else {
            emit(.error("ICMP socket unavailable (errno \(errno)) — likely blocked by the sandbox/profile."))
            return
        }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout),
                         tv_usec: __darwin_suseconds_t((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 0...UInt16.max)
        for seq in 0..<count {
            if isCancelled() { return }
            let packet = makeEcho(isV6: isV6, identifier: identifier, sequence: UInt16(truncatingIfNeeded: seq))
            let start = DispatchTime.now()

            let sent = packet.withUnsafeBytes { pkt in
                addr.withUnsafeBytes { sa in
                    sendto(fd, pkt.baseAddress, pkt.count, 0,
                           sa.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(addr.count))
                }
            }
            if sent < 0 { emit(.error("send failed (errno \(errno)).")); return }

            if let rtt = receiveReply(fd: fd, isV6: isV6, expectSeq: UInt16(truncatingIfNeeded: seq),
                                      start: start, budget: timeout) {
                emit(.reply(seq: seq, rtt: rtt))
            } else {
                emit(.lost(seq: seq))
            }

            if seq < count - 1, !isCancelled() { Thread.sleep(forTimeInterval: interval) }
        }
    }

    /// Read until the matching echo reply arrives or the per-probe budget elapses.
    nonisolated private static func receiveReply(fd: Int32, isV6: Bool, expectSeq: UInt16,
                                                 start: DispatchTime, budget: TimeInterval) -> TimeInterval? {
        var buffer = [UInt8](repeating: 0, count: 1500)
        while true {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            if elapsed > budget { return nil }

            let n = recv(fd, &buffer, buffer.count, 0)
            if n < 0 { return nil }      // timeout (EAGAIN) or error
            if n < 8 { continue }

            // For SOCK_DGRAM the ICMP message usually starts at byte 0, but defend
            // against an IPv4 header being present.
            var offset = 0
            if !isV6, (buffer[0] & 0xF0) == 0x40 {
                let ihl = Int(buffer[0] & 0x0F) * 4
                guard n > ihl + 8 else { continue }
                offset = ihl
            }
            if Self.isEchoReply(buffer, offset: offset, available: n, expectSeq: expectSeq, isV6: isV6) {
                return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            }
        }
    }

    /// Whether the ICMP message at `offset` (with `available` valid bytes) is OUR
    /// echo reply: correct reply type, matching sequence, AND our payload echoed
    /// back. The payload check rejects unrelated or spoofed replies that merely
    /// share the sequence number. Pure.
    nonisolated static func isEchoReply(_ buffer: [UInt8], offset: Int, available: Int,
                                        expectSeq: UInt16, isV6: Bool) -> Bool {
        guard offset >= 0, offset + 8 <= available else { return false }
        guard buffer[offset] == (isV6 ? 129 : 0) else { return false }   // echo reply type
        let seq = (UInt16(buffer[offset + 6]) << 8) | UInt16(buffer[offset + 7])
        guard seq == expectSeq else { return false }
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + echoPayload.count
        guard payloadEnd <= available else { return false }
        return Array(buffer[payloadStart..<payloadEnd]) == echoPayload
    }

    nonisolated private static func resolve(_ host: String) -> (addr: [UInt8], family: Int32)? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }

        let length = Int(info.pointee.ai_addrlen)
        guard let sa = info.pointee.ai_addr, length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        bytes.withUnsafeMutableBytes { _ = memcpy($0.baseAddress, sa, length) }
        return (bytes, info.pointee.ai_family)
    }

    /// 16-byte marker echoed in every request. Replies must return it (RFC 792),
    /// so we can reject unrelated/spoofed ICMP that merely shares our sequence.
    nonisolated static let echoPayload: [UInt8] = Array("octet-echo-pkt-x".utf8.prefix(16))

    nonisolated private static func makeEcho(isV6: Bool, identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var pkt: [UInt8] = [
            isV6 ? 128 : 8, 0,           // type, code
            0, 0,                         // checksum (filled below for v4; kernel does v6)
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
        ]
        pkt += echoPayload               // 16-byte payload
        if !isV6 {
            let ck = checksum(pkt)
            pkt[2] = UInt8(ck >> 8)
            pkt[3] = UInt8(ck & 0xFF)
        }
        return pkt
    }

    /// Standard 16-bit one's-complement Internet checksum.
    nonisolated static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum += (UInt32(data[i]) << 8) | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count { sum += UInt32(data[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }
}
