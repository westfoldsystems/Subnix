//
//  LANScanner.swift
//  The hero Discovery tool. Derives the local /24 from the active interface,
//  sweeps it with bounded TCP-connect probes (which also populate the ARP cache
//  on-link), then enriches each live host with its MAC (ARPTable), a reverse-DNS
//  hostname, and a vendor (the Phase-1 OUILookup). Streams hosts as they appear,
//  like BonjourScanner.
//
//  We sweep with TCP connects rather than ICMP because ICMP is walled in the
//  macOS sandbox (see PingEngine); a connect to any port — open or refused —
//  still forces on-link ARP resolution, which is what we read afterwards.
//
//  DEVICE NOTE: sysctl ARP behavior and local-network access differ between
//  simulator and a real iPhone, and the feature is only meaningful on a real
//  LAN. Validated on macOS only; iOS-device status is UNVERIFIED.
//

import Foundation
import Darwin
import Observation

struct LANHost: Identifiable, Sendable {
    let id = UUID()
    let ip: String
    var mac: String?
    var vendor: String?
    var hostname: String?
    var openPorts: [Int] = []            // TCP ports that answered during the sweep

    /// Best-guess device type from the open-port fingerprint.
    var deviceHint: String? { LANScanner.deviceHint(openPorts: openPorts) }
}

@MainActor
@Observable
final class LANScanner {

    enum State: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case enriching
        case finished
        case failed(String)
    }

    private(set) var hosts: [LANHost] = []
    private(set) var state: State = .idle
    private(set) var subnet: String?
    private(set) var selfIP: String?     // this device's own address on the subnet

    private var task: Task<Void, Never>?
    // Curated high-signal TCP ports: liveness + a service/device fingerprint.
    private let probePorts = [22, 80, 443, 139, 445, 3389, 631, 9100, 8080, 62078, 8009, 32400]

    var isScanning: Bool {
        switch state { case .scanning, .enriching: true; default: false }
    }

    // MARK: - Control

    func start() {
        cancel()
        guard let primary = LANScanner.primaryIPv4(), let plan = LANScanner.slash24(for: primary) else {
            state = .failed("No active IPv4 LAN interface found.")
            return
        }
        subnet = plan.network
        selfIP = primary
        hosts = []
        state = .scanning(done: 0, total: plan.hosts.count)

        task = Task { @MainActor [weak self] in
            await self?.run(hosts: plan.hosts)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Driver

    private func run(hosts candidates: [String]) async {
        let total = candidates.count
        var done = 0

        // Sweep: bounded TCP-connect probes, streaming live hosts with open ports.
        await withTaskGroup(of: (ip: String, alive: Bool, open: [Int]).self) { group in
            var iterator = candidates.makeIterator()
            let cap = 24
            for _ in 0..<cap {
                guard let ip = iterator.next() else { break }
                group.addTask { [probePorts] in await Self.probeHost(ip, ports: probePorts) }
            }
            while let result = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                done += 1
                if result.alive { insertHost(result.ip, openPorts: result.open) }
                state = .scanning(done: done, total: total)
                if let ip = iterator.next() {
                    group.addTask { [probePorts] in await Self.probeHost(ip, ports: probePorts) }
                }
            }
        }
        guard !Task.isCancelled else { state = .failed("Cancelled."); return }

        // Enrich: fold in ARP (adds hosts that answered ARP but no TCP port),
        // then attach MAC/vendor/hostname.
        state = .enriching
        let arp = ARPTable.entries()
        for (ip, _) in arp where Self.inSameSlash24(ip, as: subnet) {
            insertHost(ip)
        }
        for index in hosts.indices {
            let ip = hosts[index].ip
            if let mac = arp[ip] {
                hosts[index].mac = mac
                if let parsed = try? MACAddress.parse(mac) {
                    hosts[index].vendor = OUILookup.shared.vendor(for: parsed)
                }
            }
            if let name = await Self.reverseDNS(ip) { hosts[index].hostname = name }
        }

        state = .finished
    }

    private func insertHost(_ ip: String, openPorts: [Int] = []) {
        guard !hosts.contains(where: { $0.ip == ip }) else { return }
        let index = hosts.firstIndex { Self.ipLess(ip, $0.ip) } ?? hosts.endIndex
        hosts.insert(LANHost(ip: ip, openPorts: openPorts), at: index)
    }

    // MARK: - Probing (isolation-free)

    /// Connect-probe every port. `alive` = the host answered anything (open OR
    /// refused → it's up and ARP resolved); `open` = ports that accepted.
    nonisolated static func probeHost(_ ip: String, ports: [Int]) async -> (ip: String, alive: Bool, open: [Int]) {
        await withTaskGroup(of: (port: Int, status: PortStatus).self) { group in
            for port in ports {
                group.addTask { (port, await PortScanner.probe(host: ip, port: port, timeout: 1).status) }
            }
            var alive = false
            var open: [Int] = []
            for await result in group {
                switch result.status {
                case .open:   alive = true; open.append(result.port)
                case .closed: alive = true
                default:      break
                }
            }
            return (ip, alive, open.sorted())
        }
    }

    /// Best-guess device type from open ports. Most specific match wins. Pure.
    nonisolated static func deviceHint(openPorts: [Int]) -> String? {
        let p = Set(openPorts)
        if p.contains(62078)                 { return "iPhone / iPad" }
        if p.contains(32400)                 { return "Plex media server" }
        if p.contains(8009)                  { return "Chromecast / Google TV" }
        if p.contains(9100) || p.contains(631) { return "Printer" }
        if p.contains(3389)                  { return "Windows (RDP)" }
        if p.contains(445) || p.contains(139) { return "Windows / NAS (SMB)" }
        if p.contains(22)                    { return "Linux / Unix (SSH)" }
        if p.contains(443) || p.contains(80) || p.contains(8080) { return "Web server / router" }
        return nil
    }

    nonisolated static func reverseDNS(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
                    continuation.resume(returning: nil); return
                }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }
                let name = rc == 0 ? String(cString: host) : ""
                continuation.resume(returning: name.isEmpty ? nil : name)
            }
        }
    }

    // MARK: - Subnet math (pure)

    static func primaryIPv4() -> String? {
        LocalInterfaces.all().first { $0.isIPv4 && !$0.isLoopback && !$0.isLinkLocal }?.address
    }

    /// (network/24, [.1 ... .254]) for a dotted IPv4. Defensive about shape.
    nonisolated static func slash24(for ip: String) -> (network: String, hosts: [String])? {
        let octets = ip.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        let prefix = octets.prefix(3).joined(separator: ".")
        return ("\(prefix).0/24", (1...254).map { "\(prefix).\($0)" })
    }

    nonisolated static func inSameSlash24(_ ip: String, as subnet: String?) -> Bool {
        guard let subnet, let network = subnet.split(separator: "/").first else { return false }
        let a = ip.split(separator: ".").prefix(3)
        let b = network.split(separator: ".").prefix(3)
        return a.count == 3 && a == b
    }

    nonisolated static func ipLess(_ lhs: String, _ rhs: String) -> Bool {
        func value(_ s: String) -> UInt32 {
            s.split(separator: ".").reduce(UInt32(0)) { ($0 << 8) | (UInt32($1) ?? 0) }
        }
        return value(lhs) < value(rhs)
    }
}
