//
//  DNSMessage.swift
//  A hand-rolled DNS wire-format encoder + decoder. Same hazard class as the
//  X.509 parser, so it is defensive from the first line: every offset is
//  bounds-checked against the buffer, every length validated, and name
//  decompression is hardened against out-of-bounds reads, runaway pointer
//  chains, and pointer loops. A malformed response must fail gracefully —
//  never crash, never loop, never read past the buffer.
//
//  Reuses IPv6Toolkit for AAAA formatting.
//

import Foundation

enum DNSRecordType: UInt16, CaseIterable, Identifiable, Sendable {
    case a = 1, ns = 2, cname = 5, soa = 6, ptr = 12, mx = 15, txt = 16
    case aaaa = 28, srv = 33, caa = 257

    var id: UInt16 { rawValue }
    var label: String {
        switch self {
        case .a: "A"; case .ns: "NS"; case .cname: "CNAME"; case .soa: "SOA"
        case .ptr: "PTR"; case .mx: "MX"; case .txt: "TXT"; case .aaaa: "AAAA"
        case .srv: "SRV"; case .caa: "CAA"
        }
    }
}

struct DNSRecord: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let type: DNSRecordType?
    let rawType: UInt16
    let ttl: UInt32
    let data: String
    var typeLabel: String { type?.label ?? "TYPE\(rawType)" }
}

struct DNSResponse: Sendable {
    let id: UInt16
    let truncated: Bool
    let responseCode: Int
    let answers: [DNSRecord]
    let authority: [DNSRecord]
    let additional: [DNSRecord]

    /// RCODE → human string for the common cases.
    var responseCodeText: String {
        switch responseCode {
        case 0: "NOERROR"; case 1: "FORMERR"; case 2: "SERVFAIL"
        case 3: "NXDOMAIN"; case 4: "NOTIMP"; case 5: "REFUSED"
        default: "RCODE\(responseCode)"
        }
    }
}

enum DNSError: LocalizedError, Equatable {
    case truncatedMessage
    case malformedName
    case pointerLoop
    case nameTooLong
    case badRDLength

    var errorDescription: String? {
        switch self {
        case .truncatedMessage: "The DNS response was truncated or too short to parse."
        case .malformedName:    "The DNS response contained a malformed name."
        case .pointerLoop:      "The DNS response had a looping compression pointer."
        case .nameTooLong:      "A DNS name exceeded the 255-byte limit."
        case .badRDLength:      "A record's data length ran past the response."
        }
    }
}

enum DNSMessage {

    // MARK: - Encoding

    static func query(id: UInt16, name: String, type: UInt16, recursionDesired: Bool = true) -> [UInt8] {
        var msg: [UInt8] = []
        msg += u16be(id)
        msg += u16be(recursionDesired ? 0x0100 : 0x0000)  // flags: RD
        msg += u16be(1)   // QDCOUNT
        msg += u16be(0)   // ANCOUNT
        msg += u16be(0)   // NSCOUNT
        msg += u16be(0)   // ARCOUNT
        msg += encodeName(name)
        msg += u16be(type)
        msg += u16be(1)   // QCLASS IN
        return msg
    }

    static func encodeName(_ name: String) -> [UInt8] {
        var out: [UInt8] = []
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".") {
                let bytes = Array(label.utf8.prefix(63))
                out.append(UInt8(bytes.count))
                out += bytes
            }
        }
        out.append(0)   // root
        return out
    }

    /// Build the in-addr.arpa / ip6.arpa name for a PTR query.
    static func reverseName(forIPv4 address: String) -> String? {
        let parts = address.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return parts.reversed().joined(separator: ".") + ".in-addr.arpa"
    }

    // MARK: - Decoding

    private static let maxPointerJumps = 64
    private static let maxNameLength = 255

    static func decode(_ b: [UInt8]) throws -> DNSResponse {
        guard b.count >= 12 else { throw DNSError.truncatedMessage }

        let id = u16(b, 0)
        let flags = u16(b, 2)
        let truncated = (flags & 0x0200) != 0
        let rcode = Int(flags & 0x000F)
        let qd = Int(u16(b, 4)), an = Int(u16(b, 6)), ns = Int(u16(b, 8)), ar = Int(u16(b, 10))

        var pos = 12
        // Skip questions (name + qtype + qclass), still bounds-checking the name walk.
        for _ in 0..<qd {
            pos = try readName(b, at: pos).next
            guard pos + 4 <= b.count else { throw DNSError.truncatedMessage }
            pos += 4
        }

        let answers = try readRecords(b, &pos, count: an)
        let authority = try readRecords(b, &pos, count: ns)
        let additional = try readRecords(b, &pos, count: ar)

        return DNSResponse(id: id, truncated: truncated, responseCode: rcode,
                           answers: answers, authority: authority, additional: additional)
    }

    private static func readRecords(_ b: [UInt8], _ pos: inout Int, count: Int) throws -> [DNSRecord] {
        var records: [DNSRecord] = []
        records.reserveCapacity(min(count, 64))
        for _ in 0..<count {
            let (name, afterName) = try readName(b, at: pos)
            pos = afterName
            // TYPE(2) CLASS(2) TTL(4) RDLENGTH(2)
            guard pos + 10 <= b.count else { throw DNSError.truncatedMessage }
            let rawType = u16(b, pos)
            let ttl = u32(b, pos + 4)
            let rdlen = Int(u16(b, pos + 8))
            pos += 10
            guard rdlen >= 0, pos + rdlen <= b.count else { throw DNSError.badRDLength }

            let type = DNSRecordType(rawValue: rawType)
            let data = formatRData(b, type: type, start: pos, length: rdlen)
            records.append(DNSRecord(name: name, type: type, rawType: rawType, ttl: ttl, data: data))

            // Always advance by the declared length, regardless of how rdata parsed.
            pos += rdlen
        }
        return records
    }

    // MARK: - Name decompression (the dangerous part)

    /// Read a (possibly compressed) name starting at `start`.
    /// Returns the decoded name and `next` — the offset in the ORIGINAL stream
    /// immediately after the name (after the first pointer's two bytes, or after
    /// the terminating zero). Hardened against OOB reads, runaway length, and
    /// pointer loops.
    static func readName(_ b: [UInt8], at start: Int) throws -> (name: String, next: Int) {
        var labels: [String] = []
        var pos = start
        var jumps = 0
        var next: Int? = nil          // stream offset to resume the outer parser
        var totalLength = 0

        while true {
            guard pos < b.count else { throw DNSError.malformedName }
            let lead = Int(b[pos])

            switch lead & 0xC0 {
            case 0xC0:
                // Compression pointer: needs a second byte.
                guard pos + 1 < b.count else { throw DNSError.malformedName }
                let offset = ((lead & 0x3F) << 8) | Int(b[pos + 1])
                if next == nil { next = pos + 2 }     // outer parser resumes here
                jumps += 1
                guard jumps <= maxPointerJumps else { throw DNSError.pointerLoop }
                guard offset < b.count else { throw DNSError.malformedName }
                pos = offset                          // follow it

            case 0x00:
                if lead == 0 {
                    pos += 1                          // terminating root label
                    return (labels.joined(separator: "."), next ?? pos)
                }
                // Normal label of length 1...63.
                let labelStart = pos + 1
                let labelEnd = labelStart + lead
                guard labelEnd <= b.count else { throw DNSError.malformedName }
                totalLength += lead + 1
                guard totalLength <= maxNameLength else { throw DNSError.nameTooLong }
                labels.append(String(decoding: b[labelStart..<labelEnd], as: UTF8.self))
                pos = labelEnd

            default:
                // 0x40 / 0x80 label types are reserved/unsupported.
                throw DNSError.malformedName
            }
        }
    }

    // MARK: - RDATA formatting (bounds-safe; never throws — falls back to hex)

    private static func formatRData(_ b: [UInt8], type: DNSRecordType?, start: Int, length: Int) -> String {
        let end = start + length
        func hexDump() -> String {
            guard start <= end, end <= b.count else { return "(invalid)" }
            return b[start..<end].map { String(format: "%02x", $0) }.joined()
        }
        guard end <= b.count else { return "(invalid)" }

        switch type {
        case .a:
            guard length == 4 else { return hexDump() }
            return "\(b[start]).\(b[start+1]).\(b[start+2]).\(b[start+3])"

        case .aaaa:
            guard length == 16 else { return hexDump() }
            var hi: UInt64 = 0, lo: UInt64 = 0
            for i in 0..<8 { hi = (hi << 8) | UInt64(b[start + i]) }
            for i in 8..<16 { lo = (lo << 8) | UInt64(b[start + i]) }
            return IPv6Toolkit.Address(high: hi, low: lo).compressed

        case .cname, .ns, .ptr:
            return (try? readName(b, at: start).name) ?? "(malformed name)"

        case .mx:
            guard length >= 3 else { return hexDump() }
            let preference = u16(b, start)
            let exchange = (try? readName(b, at: start + 2).name) ?? "(malformed)"
            return "\(preference) \(exchange)"

        case .txt:
            var parts: [String] = []
            var p = start
            while p < end {
                let len = Int(b[p]); p += 1
                guard p + len <= end else { break }
                parts.append(String(decoding: b[p..<p+len], as: UTF8.self))
                p += len
            }
            return parts.joined(separator: " ")

        case .soa:
            guard let (mname, p1) = try? readName(b, at: start),
                  let (rname, p2) = try? readName(b, at: p1),
                  p2 + 20 <= b.count else { return hexDump() }
            let serial = u32(b, p2), refresh = u32(b, p2 + 4), retry = u32(b, p2 + 8)
            let expire = u32(b, p2 + 12), minimum = u32(b, p2 + 16)
            return "\(mname) \(rname) serial=\(serial) refresh=\(refresh) retry=\(retry) expire=\(expire) min=\(minimum)"

        case .srv:
            guard length >= 6 else { return hexDump() }
            let priority = u16(b, start), weight = u16(b, start + 2), port = u16(b, start + 4)
            let target = (try? readName(b, at: start + 6).name) ?? "(malformed)"
            return "\(priority) \(weight) \(port) \(target)"

        case .caa:
            guard length >= 2 else { return hexDump() }
            let flags = b[start]
            let tagLen = Int(b[start + 1])
            guard start + 2 + tagLen <= end else { return hexDump() }
            let tag = String(decoding: b[(start+2)..<(start+2+tagLen)], as: UTF8.self)
            let value = String(decoding: b[(start+2+tagLen)..<end], as: UTF8.self)
            return "\(flags) \(tag) \"\(value)\""

        case .none:
            return hexDump()
        }
    }

    // MARK: - Big-endian readers (callers bounds-check first)

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        (UInt16(b[i]) << 8) | UInt16(b[i + 1])
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16) | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
    }
    private static func u16be(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
}
