//
//  ARPTable.swift
//  Reads the kernel ARP cache (IPv4 → MAC) via sysctl(NET_RT_FLAGS) and walks
//  the route-message dump. Like the DNS/X.509 parsers this is a byte-walker over
//  kernel-supplied data, so it's bounds-checked throughout: every sockaddr
//  offset is validated against the buffer before reading.
//
//  ARP only reflects hosts this device has recently talked to — which is why the
//  LAN Scanner sweeps first to populate it.
//
//  DEVICE NOTE: sysctl routing/ARP behavior differs between simulator and a real
//  iPhone. Validated on macOS only; iOS-device status is UNVERIFIED.
//

import Foundation
import Darwin

enum ARPTable {

    // RTF_LLINFO (0x400) filters the dump to link-layer (ARP/NDP) entries; the
    // constant isn't surfaced to Swift, so it's spelled out here.
    private static let rtfLLInfo: Int32 = 0x400
    private static let rtaxDst = 0
    private static let rtaxGateway = 1
    private static let rtaxMax = 8

    /// IPv4 address string → lowercase colon MAC. Empty on failure (never throws).
    ///
    /// macOS only: the route-message structs (`rt_msghdr`) aren't exposed to Swift
    /// in the iOS Darwin overlay, and sysctl ARP is sandbox-restricted there. On
    /// iOS this returns empty and the LAN Scanner runs without MAC/vendor until a
    /// C bridging-header path is validated on a real device.
    static func entries() -> [String: String] {
#if os(macOS)
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, rtfLLInfo]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: needed)
        var length = needed
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: String] = [:]
        let headerSize = MemoryLayout<rt_msghdr>.stride

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + headerSize <= length {
                let rtm = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let msgLen = Int(rtm.rtm_msglen)
                guard msgLen >= headerSize, offset + msgLen <= length else { break }
                let addrs = Int(rtm.rtm_addrs)

                var saOffset = offset + headerSize
                var ip: String?
                var mac: String?

                for bit in 0..<rtaxMax {
                    guard addrs & (1 << bit) != 0 else { continue }
                    guard saOffset + 2 <= offset + msgLen else { break }

                    let saLen = Int(raw[saOffset])
                    let family = raw[saOffset + 1]
                    let rounded = saLen == 0 ? 4 : (saLen + 3) & ~3   // ROUNDUP to 4 bytes
                    guard saLen > 0, saOffset + saLen <= offset + msgLen else { break }

                    if bit == rtaxDst, family == UInt8(AF_INET), saOffset + 8 <= offset + msgLen {
                        // sockaddr_in: sin_addr (4 bytes) at offset +4.
                        ip = "\(raw[saOffset+4]).\(raw[saOffset+5]).\(raw[saOffset+6]).\(raw[saOffset+7])"
                    } else if bit == rtaxGateway, family == UInt8(AF_LINK) {
                        // sockaddr_dl: header is 8 bytes; MAC is sdl_alen bytes
                        // after sdl_nlen name bytes inside sdl_data (offset +8).
                        let nlen = Int(raw[saOffset + 5])
                        let alen = Int(raw[saOffset + 6])
                        let macStart = saOffset + 8 + nlen
                        if alen == 6, macStart + 6 <= offset + msgLen {
                            mac = (0..<6).map { String(format: "%02x", raw[macStart + $0]) }.joined(separator: ":")
                        }
                    }
                    saOffset += rounded
                }

                if let ip, let mac, mac != "00:00:00:00:00:00" { result[ip] = mac }
                offset += msgLen
            }
        }
        return result
#else
        return [:]
#endif
    }
}
