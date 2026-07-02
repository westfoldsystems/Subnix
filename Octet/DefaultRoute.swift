//
//  DefaultRoute.swift
//  Reads the IPv4 default route's gateway (your router) from the kernel routing
//  table via sysctl(NET_RT_DUMP), walking the route-message dump the same way
//  ARPTable does — every sockaddr offset is bounds-checked against the buffer.
//
//  DEVICE NOTE: like ARPTable, the route-message structs (`rt_msghdr`) aren't
//  exposed to Swift in the iOS Darwin overlay, so the real read is macOS-only.
//  On iOS the LAN Scanner falls back to the conventional `.1` gateway guess
//  (see LANScanner.assumedGateway) — flagged honestly as a heuristic.
//

import Foundation
import Darwin

enum DefaultRoute {

    private static let rtfUp: Int32 = 0x1        // RTF_UP
    private static let rtfGateway: Int32 = 0x2   // RTF_GATEWAY
    private static let rtaxDst = 0
    private static let rtaxGateway = 1
    private static let rtaxMax = 8

    /// The IPv4 gateway of the default route (dotted string), or nil.
    ///
    /// macOS only — returns nil on iOS, where the caller supplies a heuristic.
    static func gatewayIPv4() -> String? {
#if os(macOS)
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: needed)
        var length = needed
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        let headerSize = MemoryLayout<rt_msghdr>.stride
        var gateway: String?

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + headerSize <= length {
                let rtm = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let msgLen = Int(rtm.rtm_msglen)
                guard msgLen >= headerSize, offset + msgLen <= length else { break }

                // Default route = UP + GATEWAY, destination 0.0.0.0.
                let flags = rtm.rtm_flags
                guard flags & rtfUp != 0, flags & rtfGateway != 0 else { offset += msgLen; continue }
                let addrs = Int(rtm.rtm_addrs)

                var saOffset = offset + headerSize
                var isDefault = false
                var gw: String?

                for bit in 0..<rtaxMax {
                    guard addrs & (1 << bit) != 0 else { continue }
                    guard saOffset + 2 <= offset + msgLen else { break }

                    let saLen = Int(raw[saOffset])
                    let family = raw[saOffset + 1]
                    let rounded = saLen == 0 ? 4 : (saLen + 3) & ~3   // ROUNDUP to 4
                    guard saOffset + max(saLen, 4) <= offset + msgLen else { break }

                    if bit == rtaxDst {
                        // Default destination is either a zero-length sockaddr or
                        // an AF_INET 0.0.0.0.
                        if saLen == 0 {
                            isDefault = true
                        } else if family == UInt8(AF_INET), saOffset + 8 <= offset + msgLen {
                            let z = raw[saOffset+4] == 0 && raw[saOffset+5] == 0
                                 && raw[saOffset+6] == 0 && raw[saOffset+7] == 0
                            isDefault = z
                        }
                    } else if bit == rtaxGateway, family == UInt8(AF_INET), saOffset + 8 <= offset + msgLen {
                        gw = "\(raw[saOffset+4]).\(raw[saOffset+5]).\(raw[saOffset+6]).\(raw[saOffset+7])"
                    }
                    saOffset += rounded
                }

                if isDefault, let gw {
                    gateway = gw
                    break
                }
                offset += msgLen
            }
        }
        return gateway
#else
        return nil
#endif
    }
}
