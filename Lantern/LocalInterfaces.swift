//
//  LocalInterfaces.swift
//  Enumerate every local network interface address via getifaddrs. Fully
//  offline — this reads the device's own configuration, contacts nothing.
//

import Foundation
import Darwin

struct NetInterface: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String         // e.g. en0
    let isIPv4: Bool
    let address: String
    let isLoopback: Bool
    let isLinkLocal: Bool     // 169.254/16 or fe80::/10

    var family: String { isIPv4 ? "IPv4" : "IPv6" }
}

enum LocalInterfaces {

    /// All up IPv4/IPv6 addresses, in getifaddrs order (roughly primary-first).
    static func all() -> [NetInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [NetInterface] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            let isV4 = family == UInt8(AF_INET)
            let isV6 = family == UInt8(AF_INET6)
            guard isV4 || isV6 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let saLen = socklen_t(isV4 ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, saLen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            var address = String(cString: host)
            // Drop the zone id off link-local v6 (fe80::1%en0 → fe80::1) for display.
            if let percent = address.firstIndex(of: "%") { address = String(address[..<percent]) }

            let isLoopback = (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
            let isLinkLocal = isV4
                ? address.hasPrefix("169.254.")
                : address.lowercased().hasPrefix("fe80")

            result.append(NetInterface(name: String(cString: ifa.ifa_name),
                                       isIPv4: isV4,
                                       address: address,
                                       isLoopback: isLoopback,
                                       isLinkLocal: isLinkLocal))
        }
        return result
    }
}
