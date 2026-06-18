//
//  IPv6Toolkit.swift
//  Pure, offline IPv6 address math. No UI, no I/O — fully unit-testable.
//
//  The address is held as two UInt64 (high/low) rather than UInt128 on purpose:
//  UInt128 only exists from iOS 18 / macOS 15, and Octet's floor is iOS 17 /
//  macOS 14. Two 64-bit halves cover every operation we need with no
//  availability gymnastics.
//
//  Correctness notes (the parts people get subtly wrong):
//   • Exactly one "::" is allowed, and it must stand for at least one zero group.
//   • Embedded IPv4 (`::ffff:1.2.3.4`) is only legal as the final element.
//   • Canonical output follows RFC 5952: lowercase, no leading zeros, and the
//     single longest zero run (leftmost on ties, length ≥ 2) becomes "::".
//

import Foundation

struct IPv6Toolkit {

    // MARK: - Address (two 64-bit halves)

    struct Address: Equatable, Hashable {
        let high: UInt64
        let low: UInt64

        init(high: UInt64, low: UInt64) {
            self.high = high
            self.low = low
        }

        init(groups g: [UInt16]) {
            precondition(g.count == 8, "an IPv6 address is exactly 8 groups")
            high = (UInt64(g[0]) << 48) | (UInt64(g[1]) << 32) | (UInt64(g[2]) << 16) | UInt64(g[3])
            low  = (UInt64(g[4]) << 48) | (UInt64(g[5]) << 32) | (UInt64(g[6]) << 16) | UInt64(g[7])
        }

        var groups: [UInt16] {
            func split(_ w: UInt64) -> [UInt16] {
                [UInt16((w >> 48) & 0xFFFF), UInt16((w >> 32) & 0xFFFF),
                 UInt16((w >> 16) & 0xFFFF), UInt16(w & 0xFFFF)]
            }
            return split(high) + split(low)
        }

        /// Fully-expanded, eight four-digit groups: `2001:0db8:0000:…:0001`.
        var expanded: String {
            groups.map { String(format: "%04x", $0) }.joined(separator: ":")
        }

        /// Canonical RFC 5952 form.
        var compressed: String {
            let g = groups

            // Longest run of consecutive zero groups, leftmost wins ties.
            var bestStart = -1, bestLen = 0
            var i = 0
            while i < 8 {
                guard g[i] == 0 else { i += 1; continue }
                var j = i
                while j < 8 && g[j] == 0 { j += 1 }
                if j - i > bestLen { bestLen = j - i; bestStart = i }
                i = j
            }

            func hex(_ x: UInt16) -> String { String(x, radix: 16) }
            guard bestLen >= 2 else { return g.map(hex).joined(separator: ":") }

            let head = g[0..<bestStart].map(hex).joined(separator: ":")
            let tail = g[(bestStart + bestLen)...].map(hex).joined(separator: ":")
            return "\(head)::\(tail)"
        }
    }

    // MARK: - Errors

    enum ParseError: LocalizedError, Equatable {
        case empty
        case tooManyDoubleColons
        case badGroup(String)
        case wrongGroupCount
        case embeddedIPv4NotLast(String)
        case badEmbeddedIPv4(String)
        case prefixOutOfRange(Int)

        var errorDescription: String? {
            switch self {
            case .empty:                     return "Enter an IPv6 address."
            case .tooManyDoubleColons:       return "An address may contain “::” only once."
            case .badGroup(let g):           return "“\(g)” isn’t a valid hex group (0–ffff)."
            case .wrongGroupCount:           return "That isn’t eight 16-bit groups."
            case .embeddedIPv4NotLast(let s):return "Embedded IPv4 “\(s)” is only allowed at the end."
            case .badEmbeddedIPv4(let s):    return "“\(s)” isn’t a valid embedded IPv4 address."
            case .prefixOutOfRange(let p):   return "“/\(p)” isn’t a valid prefix (use /0–/128)."
            }
        }
    }

    // MARK: - Parsing

    static func parse(_ raw: String) throws -> Address {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw ParseError.empty }

        let halves = s.components(separatedBy: "::")
        guard halves.count <= 2 else { throw ParseError.tooManyDoubleColons }

        let groups: [UInt16]
        if halves.count == 2 {
            let head = try parseSegment(halves[0], allowEmbeddedIPv4: false)
            let tail = try parseSegment(halves[1], allowEmbeddedIPv4: true)
            let fill = 8 - head.count - tail.count
            // "::" must absorb at least one group; otherwise it's redundant/invalid.
            guard fill >= 1 else { throw ParseError.wrongGroupCount }
            groups = head + Array(repeating: 0, count: fill) + tail
        } else {
            groups = try parseSegment(s, allowEmbeddedIPv4: true)
            guard groups.count == 8 else { throw ParseError.wrongGroupCount }
        }
        return Address(groups: groups)
    }

    /// Parse one colon-separated run of groups. The trailing token may be an
    /// embedded IPv4 literal when `allowEmbeddedIPv4` is set.
    private static func parseSegment(_ segment: String,
                                     allowEmbeddedIPv4: Bool) throws -> [UInt16] {
        guard !segment.isEmpty else { return [] }
        let tokens = segment.components(separatedBy: ":")

        var result: [UInt16] = []
        for (index, token) in tokens.enumerated() {
            if token.contains(".") {
                guard allowEmbeddedIPv4, index == tokens.count - 1 else {
                    throw ParseError.embeddedIPv4NotLast(token)
                }
                let v32 = try embeddedIPv4(token)
                result.append(UInt16(v32 >> 16))
                result.append(UInt16(v32 & 0xFFFF))
            } else {
                guard !token.isEmpty, token.count <= 4,
                      token.allSatisfy(\.isHexDigit),
                      let value = UInt16(token, radix: 16) else {
                    throw ParseError.badGroup(token)
                }
                result.append(value)
            }
        }
        return result
    }

    /// Reuse the IPv4 parser so the two engines agree on what's valid.
    private static func embeddedIPv4(_ s: String) throws -> UInt32 {
        do { return try SubnetCalculator.parseIPv4(s) }
        catch { throw ParseError.badEmbeddedIPv4(s) }
    }

    // MARK: - Prefix math

    struct PrefixReport: Equatable {
        let prefix: Int
        let network: String          // compressed
        let firstAddress: String
        let lastAddress: String
        let addressCountExponent: Int    // 128 − prefix
        let addressCountDecimal: String  // 2^(128 − prefix), exact
    }

    static func prefixReport(_ addr: Address, prefix: Int) throws -> PrefixReport {
        guard (0...128).contains(prefix) else { throw ParseError.prefixOutOfRange(prefix) }
        let (mh, ml) = mask(prefix)
        let network = Address(high: addr.high & mh, low: addr.low & ml)
        let last = Address(high: network.high | ~mh, low: network.low | ~ml)
        return PrefixReport(
            prefix: prefix,
            network: network.compressed,
            firstAddress: network.compressed,
            lastAddress: last.compressed,
            addressCountExponent: 128 - prefix,
            addressCountDecimal: powerOfTwoDecimal(128 - prefix)
        )
    }

    /// The /prefix netmask as two halves.
    static func mask(_ prefix: Int) -> (high: UInt64, low: UInt64) {
        func half(_ bits: Int) -> UInt64 {
            if bits <= 0 { return 0 }
            if bits >= 64 { return ~UInt64(0) }
            return ~UInt64(0) << (64 - bits)
        }
        return prefix <= 64 ? (half(prefix), 0) : (~UInt64(0), half(prefix - 64))
    }

    // MARK: - EUI-64

    struct EUI64Report: Equatable {
        let interfaceID: String   // the low-64 IID, four groups
        let linkLocal: String     // fe80::/64 with that IID, compressed
    }

    /// Modified EUI-64: flip the U/L bit, splice FF:FE into the middle, and hang
    /// the result off fe80::/64.
    static func eui64(from mac: MACAddress) -> EUI64Report {
        let b = mac.bytes
        let iid: [UInt8] = [b[0] ^ 0x02, b[1], b[2], 0xFF, 0xFE, b[3], b[4], b[5]]

        var low: UInt64 = 0
        for byte in iid { low = (low << 8) | UInt64(byte) }

        let linkLocal = Address(high: 0xfe80_0000_0000_0000, low: low)
        let iidStr = stride(from: 0, to: 8, by: 2).map {
            String(format: "%02x%02x", iid[$0], iid[$0 + 1])
        }.joined(separator: ":")

        return EUI64Report(interfaceID: iidStr, linkLocal: linkLocal.compressed)
    }

    // MARK: - Helpers

    /// 2^n as an exact decimal string (n ≤ 128 here), via schoolbook doubling.
    static func powerOfTwoDecimal(_ n: Int) -> String {
        var digits = [1]   // little-endian base-10
        for _ in 0..<max(0, n) {
            var carry = 0
            for i in digits.indices {
                let v = digits[i] * 2 + carry
                digits[i] = v % 10
                carry = v / 10
            }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }
}
