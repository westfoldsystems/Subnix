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
    var isGateway = false                // this host is the default route (router)
    var latency: TimeInterval?           // fastest TCP-connect RTT, seconds
    var tlsName: String?                 // leaf-cert subject CN (hosts with 443 open)
    var bonjourName: String?             // friendly mDNS instance name, if advertised

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
    private(set) var gatewayIP: String?  // default-route router (read on macOS, guessed on iOS)

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
        await withTaskGroup(of: (ip: String, alive: Bool, open: [Int], latency: TimeInterval?).self) { group in
            var iterator = candidates.makeIterator()
            let cap = 24
            for _ in 0..<cap {
                guard let ip = iterator.next() else { break }
                group.addTask { [probePorts] in await Self.probeHost(ip, ports: probePorts) }
            }
            while let result = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                done += 1
                if result.alive { insertHost(result.ip, openPorts: result.open, latency: result.latency) }
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

        // Kick off the Bonjour/mDNS name join now so its browse budget overlaps
        // with the ARP / reverse-DNS / TLS work below instead of adding to it.
        async let bonjourNames = LANmDNS.resolve()

        let arp = ARPTable.entries()
        for (ip, _) in arp where Self.inSameSlash24(ip, as: subnet) {
            insertHost(ip)
        }

        // Flag the default-route gateway (real read on macOS, .1 guess on iOS).
        let gateway = DefaultRoute.gatewayIPv4() ?? Self.assumedGateway(subnet: subnet)
        gatewayIP = gateway
        if let gateway, !hosts.contains(where: { $0.ip == gateway }),
           Self.inSameSlash24(gateway, as: subnet) {
            insertHost(gateway)
        }

        for index in hosts.indices {
            let ip = hosts[index].ip
            if ip == gateway { hosts[index].isGateway = true }
            if let mac = arp[ip] {
                hosts[index].mac = mac
                if let parsed = try? MACAddress.parse(mac) {
                    hosts[index].vendor = OUILookup.shared.vendor(for: parsed)
                }
            }
            if let name = await Self.reverseDNS(ip) { hosts[index].hostname = name }
        }

        // Cert names: for every host with 443 open, grab the leaf-cert subject CN
        // (accepts self-signed — routers/NAS usually present one). Bounded fan-out.
        let tlsHosts = hosts.filter { $0.openPorts.contains(443) }.map(\.ip)
        if !tlsHosts.isEmpty, !Task.isCancelled {
            let names = await withTaskGroup(of: (String, String?).self) { group in
                for ip in tlsHosts {
                    group.addTask { (ip, await Self.tlsCertName(ip)) }
                }
                var out: [String: String] = [:]
                for await (ip, cn) in group where cn != nil { out[ip] = cn }
                return out
            }
            for index in hosts.indices {
                if let cn = names[hosts[index].ip] { hosts[index].tlsName = cn }
            }
        }

        // Join the mDNS names (started above). Attach to known hosts, and surface
        // any in-subnet device that only advertised Bonjour (no TCP answer).
        let mdns = await bonjourNames
        for (ip, _) in mdns where Self.inSameSlash24(ip, as: subnet) {
            if !hosts.contains(where: { $0.ip == ip }) { insertHost(ip) }
        }
        for index in hosts.indices {
            if let name = mdns[hosts[index].ip] { hosts[index].bonjourName = name }
        }

        state = .finished
    }

    private func insertHost(_ ip: String, openPorts: [Int] = [], latency: TimeInterval? = nil) {
        guard !hosts.contains(where: { $0.ip == ip }) else { return }
        let index = hosts.firstIndex { Self.ipLess(ip, $0.ip) } ?? hosts.endIndex
        hosts.insert(LANHost(ip: ip, openPorts: openPorts, latency: latency), at: index)
    }

    // MARK: - Probing (isolation-free)

    /// Connect-probe every port. `alive` = the host answered anything (open OR
    /// refused → it's up and ARP resolved); `open` = ports that accepted;
    /// `latency` = fastest connect RTT among open ports (nil if none opened).
    nonisolated static func probeHost(_ ip: String, ports: [Int]) async -> (ip: String, alive: Bool, open: [Int], latency: TimeInterval?) {
        await withTaskGroup(of: PortProbeResult.self) { group in
            for port in ports {
                group.addTask { await PortScanner.probe(host: ip, port: port, timeout: 1) }
            }
            var alive = false
            var open: [Int] = []
            var latency: TimeInterval?
            for await result in group {
                switch result.status {
                case .open:
                    alive = true
                    open.append(result.port)
                    if let l = result.latency { latency = min(latency ?? l, l) }
                case .closed:
                    alive = true
                default:
                    break
                }
            }
            return (ip, alive, open.sorted(), latency)
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

    /// Leaf-cert subject CN for an HTTPS host, or nil. The handshake
    /// (`fetchCertChain`) runs off-main; only the tiny DER parse — which is
    /// main-actor-isolated under the module default — lands back here.
    static func tlsCertName(_ ip: String) async -> String? {
        guard let handshake = try? await TLSInspector.fetchCertChain(host: ip, port: 443, timeout: 3),
              let leaf = handshake.ders.first else { return nil }
        return X509Certificate.parse(der: leaf)?.subjectCN
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

    /// The conventional gateway for a /24 (`<prefix>.1`). Used as a best-effort
    /// fallback where the real default route can't be read (iOS). Pure.
    nonisolated static func assumedGateway(subnet: String?) -> String? {
        guard let subnet, let network = subnet.split(separator: "/").first else { return nil }
        let octets = network.split(separator: ".")
        guard octets.count == 4 else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).1"
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
