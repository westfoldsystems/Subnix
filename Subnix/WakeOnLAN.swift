//
//  WakeOnLAN.swift
//  Sends a Wake-on-LAN "magic packet" to wake a sleeping device by its MAC.
//  Pure packet construction (testable) + a BSD UDP broadcast send. Stays on the
//  local network: the packet goes to the subnet-directed broadcast and the
//  global broadcast, never to a server.
//
//  The magic packet is 6 × 0xFF followed by the 6-byte target MAC repeated 16
//  times (102 bytes). The target device's firmware/OS must have WoL enabled.
//
//  DEVICE NOTE: sending to a broadcast address works on macOS with the client
//  networking entitlement. On iOS 14+, broadcast/multicast sends require the
//  `com.apple.developer.networking.multicast` entitlement (an Apple-approved
//  request) — without it the send is dropped. Validated on macOS only.
//

import Foundation
import Darwin
import Observation

@MainActor
@Observable
final class WakeOnLAN {

    enum State: Equatable {
        case idle
        case sending
        case sent(mac: String, targets: [String])
        case failed(String)
    }

    private(set) var state: State = .idle
    var isSending: Bool { state == .sending }

    private var task: Task<Void, Never>?

    // MARK: - Control

    /// Parse the MAC, build the magic packet, and broadcast it. `targetOverride`
    /// (an IP or broadcast address) is used verbatim when non-empty; otherwise the
    /// packet goes to the /24 subnet-directed broadcast and the global broadcast.
    func wake(macText: String, targetOverride: String = "") {
        cancel()
        let mac: MACAddress
        do { mac = try MACAddress.parse(macText) }
        catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Invalid MAC address.")
            return
        }

        let packet = Self.magicPacket(for: mac.bytes)
        let targets = Self.targets(override: targetOverride, primaryIPv4: Self.primaryIPv4())
        guard !targets.isEmpty else { state = .failed("No broadcast target — are you on a LAN?"); return }

        state = .sending
        let canonicalMAC = mac.colon
        task = Task { @MainActor [weak self] in
            let result = await Self.broadcast(packet: packet, targets: targets, port: 9)
            guard let self, self.isSending else { return }
            if let error = result.error {
                self.state = .failed(error)
            } else if result.sent.isEmpty {
                self.state = .failed("Couldn’t send to any target.")
            } else {
                self.state = .sent(mac: canonicalMAC, targets: result.sent)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isSending { state = .idle }
    }

    // MARK: - Magic packet (pure, testable)

    /// 6 × 0xFF sync stream, then the 6-byte MAC repeated 16 times = 102 bytes.
    nonisolated static func magicPacket(for mac: [UInt8]) -> [UInt8] {
        precondition(mac.count == 6, "MAC must be 6 bytes")
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }
        return packet
    }

    // MARK: - Targets (pure)

    /// Where to send: the override verbatim if given, else the subnet-directed
    /// broadcast (when we know our address) plus the global broadcast.
    nonisolated static func targets(override: String, primaryIPv4: String?) -> [String] {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return [trimmed] }
        var out: [String] = []
        if let directed = subnetBroadcast(for: primaryIPv4) { out.append(directed) }
        out.append("255.255.255.255")
        return out
    }

    /// The /24 directed broadcast for an address (`a.b.c.d` → `a.b.c.255`). Pure.
    nonisolated static func subnetBroadcast(for ip: String?) -> String? {
        guard let ip else { return nil }
        let octets = ip.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).255"
    }

    static func primaryIPv4() -> String? {
        LocalInterfaces.all().first { $0.isIPv4 && !$0.isLoopback && !$0.isLinkLocal }?.address
    }

    // MARK: - Broadcast send (isolation-free; BSD UDP)

    /// Send `packet` to each target on `port`. Returns the targets that accepted
    /// the send; `error` is set only if the socket couldn't be opened.
    nonisolated static func broadcast(packet: [UInt8], targets: [String], port: UInt16) async -> (sent: [String], error: String?) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return ([], "UDP socket unavailable (errno \(errno)).") }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var sent: [String] = []
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, target, &addr.sin_addr) == 1 else { continue }

            let n = packet.withUnsafeBytes { pkt in
                withUnsafePointer(to: &addr) { ap in
                    ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, pkt.baseAddress, pkt.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if n >= 0 { sent.append(target) }
        }
        return (sent, nil)
    }
}
