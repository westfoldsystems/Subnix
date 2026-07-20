//
//  SubnetCalculator.swift
//  Pure, offline IPv4 subnet math. No UI, no I/O — fully unit-testable.
//
//  Correctness notes (the parts people get subtly wrong):
//   • /31 follows RFC 3021: BOTH addresses are usable, there is no broadcast.
//   • /32 is a single host: it is its own "first" and "last", no broadcast.
//   • /0 has 2^32 total addresses — host counts use UInt64 to avoid overflow.
//   • host counts for /0../30 are total − 2 (network + broadcast excluded).
//

import Foundation

struct SubnetCalculator {

    enum CalculationError: LocalizedError, Equatable {
        case malformedAddress(String)
        case octetOutOfRange(String)
        case prefixOutOfRange(String)
        case missingPrefix

        var errorDescription: String? {
            switch self {
            case .malformedAddress(let s): return "“\(s)” isn’t a valid IPv4 address."
            case .octetOutOfRange(let s):  return "“\(s)” has an octet outside 0–255."
            case .prefixOutOfRange(let s): return "“\(s)” isn’t a valid prefix (use /0–/32)."
            case .missingPrefix:           return "Add a prefix, e.g. 192.168.1.0/24."
            }
        }
    }

    struct Result: Equatable {
        let inputAddress: String
        let prefix: Int

        let networkAddress: String
        let broadcastAddress: String?   // nil for /31 and /32
        let firstUsableHost: String?
        let lastUsableHost: String?
        let usableHostCount: UInt64
        let totalAddresses: UInt64

        let subnetMask: String
        let wildcardMask: String
        let cidr: String                // canonical "network/prefix"
        let addressClass: String        // legacy A/B/C/D/E — informational only
        let isPrivate: Bool             // RFC 1918
    }

    /// Parse `"a.b.c.d"` or `"a.b.c.d/n"`. If no prefix is present, `defaultPrefix`
    /// is used; if that's also nil, throws `.missingPrefix`.
    static func calculate(_ input: String, defaultPrefix: Int? = nil) throws -> Result {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)

        let addressPart = String(parts[0])

        let prefix: Int
        if parts.count == 2 {
            let raw = String(parts[1])
            guard let p = Int(raw), (0...32).contains(p) else {
                throw CalculationError.prefixOutOfRange(raw)
            }
            prefix = p
        } else if let d = defaultPrefix, (0...32).contains(d) {
            prefix = d
        } else {
            throw CalculationError.missingPrefix
        }

        let addr = try parseIPv4(addressPart)

        let mask: UInt32 = prefix == 0 ? 0 : (~UInt32(0)) << (32 - prefix)
        let network = addr & mask
        let broadcast = network | ~mask
        let total = UInt64(1) << UInt64(32 - prefix)

        let networkStr = format(network)

        let broadcastStr: String?
        let firstStr: String?
        let lastStr: String?
        let usable: UInt64

        switch prefix {
        case 32:                                    // single host
            broadcastStr = nil
            firstStr = networkStr
            lastStr  = networkStr
            usable   = 1
        case 31:                                    // RFC 3021 point-to-point
            broadcastStr = nil
            firstStr = format(network)
            lastStr  = format(broadcast)
            usable   = 2
        default:                                    // /0 .. /30
            broadcastStr = format(broadcast)
            firstStr = format(network &+ 1)
            lastStr  = format(broadcast &- 1)
            usable   = total - 2
        }

        return Result(
            inputAddress: addressPart,
            prefix: prefix,
            networkAddress: networkStr,
            broadcastAddress: broadcastStr,
            firstUsableHost: firstStr,
            lastUsableHost: lastStr,
            usableHostCount: usable,
            totalAddresses: total,
            subnetMask: format(mask),
            wildcardMask: format(~mask),
            cidr: "\(networkStr)/\(prefix)",
            addressClass: legacyClass(for: addr),
            isPrivate: isRFC1918(addr)
        )
    }

    // MARK: - Parsing / formatting

    static func parseIPv4(_ s: String) throws -> UInt32 {
        let octets = s.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { throw CalculationError.malformedAddress(s) }

        var value: UInt32 = 0
        for octet in octets {
            // Reject empties, signs, non-digits, and out-of-range in one shot.
            guard octet.allSatisfy(\.isNumber),
                  let n = Int(octet), (0...255).contains(n) else {
                throw CalculationError.octetOutOfRange(s)
            }
            value = (value << 8) | UInt32(n)
        }
        return value
    }

    static func format(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    private static func legacyClass(for addr: UInt32) -> String {
        switch (addr >> 24) & 0xFF {
        case 0...127:   return "A"
        case 128...191: return "B"
        case 192...223: return "C"
        case 224...239: return "D (multicast)"
        default:        return "E (reserved)"
        }
    }

    private static func isRFC1918(_ addr: UInt32) -> Bool {
        let a = (addr >> 24) & 0xFF
        let b = (addr >> 16) & 0xFF
        if a == 10 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        return false
    }
}
