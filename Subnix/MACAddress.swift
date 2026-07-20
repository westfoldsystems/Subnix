//
//  MACAddress.swift
//  A parsed 48-bit MAC / EUI-48. Pure, offline, no I/O — the shared currency
//  for the MAC normalizer, EUI-64 generation, and OUI vendor lookup.
//
//  Accepts the four shapes people actually paste — colon, hyphen, Cisco dot,
//  and bare hex — in any case, and re-emits all of them canonically.
//

import Foundation

struct MACAddress: Equatable, Hashable {

    enum ParseError: LocalizedError, Equatable {
        case wrongLength(String)
        case nonHex(String)

        var errorDescription: String? {
            switch self {
            case .wrongLength(let s): return "“\(s)” isn’t 12 hex digits (a 48-bit MAC)."
            case .nonHex(let s):      return "“\(s)” contains non-hex characters."
            }
        }
    }

    /// Exactly six bytes, most-significant first.
    let bytes: [UInt8]

    /// The 24-bit OUI (first three bytes) — the part an IEEE registry keys on.
    var oui: [UInt8] { Array(bytes.prefix(3)) }

    /// `true` when the locally-administered bit (bit 1 of the first octet) is set.
    var isLocallyAdministered: Bool { (bytes[0] & 0x02) != 0 }
    /// `true` when the group bit (bit 0 of the first octet) is set (multicast).
    var isGroup: Bool { (bytes[0] & 0x01) != 0 }

    private init(checkedBytes: [UInt8]) {
        self.bytes = checkedBytes
    }

    /// Parse any of `aa:bb:cc:dd:ee:ff`, `aa-bb-…`, `aabb.ccdd.eeff`, `aabbccddeeff`.
    static func parse(_ raw: String) throws -> MACAddress {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Strip the accepted separators; whatever remains must be 12 hex digits.
        let stripped = trimmed.filter { $0 != ":" && $0 != "-" && $0 != "." }

        guard stripped.count == 12 else { throw ParseError.wrongLength(trimmed) }
        guard stripped.allSatisfy(\.isHexDigit) else { throw ParseError.nonHex(trimmed) }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        var index = stripped.startIndex
        for _ in 0..<6 {
            let next = stripped.index(index, offsetBy: 2)
            // allSatisfy(isHexDigit) above guarantees this parse succeeds.
            bytes.append(UInt8(stripped[index..<next], radix: 16)!)
            index = next
        }
        return MACAddress(checkedBytes: bytes)
    }

    // MARK: - Canonical renderings

    private func hexPairs(uppercase: Bool) -> [String] {
        bytes.map { String(format: uppercase ? "%02X" : "%02x", $0) }
    }

    var colon: String  { hexPairs(uppercase: false).joined(separator: ":") }
    var hyphen: String { hexPairs(uppercase: false).joined(separator: "-") }
    var bare: String   { hexPairs(uppercase: false).joined() }

    /// Cisco/“dotted-quad” form: three 16-bit groups, e.g. `aabb.ccdd.eeff`.
    var dot: String {
        let h = hexPairs(uppercase: false)
        return "\(h[0])\(h[1]).\(h[2])\(h[3]).\(h[4])\(h[5])"
    }
}
