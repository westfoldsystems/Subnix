//
//  X509Certificate.swift
//  A small, dependency-free DER/ASN.1 reader for the certificate fields users
//  care about — Subject/Issuer CN, validity, serial, signature algorithm, and
//  (the hard part) the Subject Alternative Names.
//
//  Why parse DER by hand instead of SecCertificateCopyValues + kSecOIDSubjectAltName?
//  Because that API and those OID constants are macOS-only (__IPHONE_NA) — they
//  don't exist on the iOS 17 floor. A tiny DER walker works identically on both
//  platforms and is fully unit-testable against a bundled certificate, which is
//  exactly what we want for the SAN extraction.
//
//  SANs live in extension OID 2.5.29.17: an OCTET STRING wrapping a
//  SEQUENCE OF GeneralName, where dNSName is context tag [2] (0x82) and
//  iPAddress is [7] (0x87). We pull both.
//

import Foundation

struct CertSAN: Hashable, Sendable {
    enum Kind: String, Sendable { case dns = "DNS", ip = "IP" }
    let kind: Kind
    let value: String
}

struct X509Certificate: Sendable {
    let subjectCN: String?
    let issuerCN: String?
    let serialHex: String?
    let notBefore: Date?
    let notAfter: Date?
    let signatureAlgorithm: String?
    let sans: [CertSAN]

    // MARK: - DER primitives

    /// One tag-length-value triple. `start..<end` is the *content* (value).
    private struct TLV { let tag: UInt8; let start: Int; let length: Int; let end: Int }

    private static func parseTLV(_ b: [UInt8], _ p: Int) -> TLV? {
        guard p + 1 < b.count else { return nil }
        let tag = b[p]
        var i = p + 1
        let first = b[i]; i += 1

        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4, i + count <= b.count else { return nil }
            for _ in 0..<count { length = (length << 8) | Int(b[i]); i += 1 }
        }
        let end = i + length
        guard end <= b.count else { return nil }
        return TLV(tag: tag, start: i, length: length, end: end)
    }

    /// All TLVs directly inside `[start, end)`.
    private static func children(_ b: [UInt8], _ start: Int, _ end: Int) -> [TLV] {
        var result: [TLV] = []
        var p = start
        while p < end {
            guard let tlv = parseTLV(b, p) else { break }
            result.append(tlv)
            p = tlv.end
        }
        return result
    }

    // MARK: - Parse

    static func parse(der b: [UInt8]) -> X509Certificate? {
        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
        guard let cert = parseTLV(b, 0), cert.tag == 0x30 else { return nil }
        let top = children(b, cert.start, cert.end)
        guard top.count >= 2, top[0].tag == 0x30 else { return nil }

        let tbs = top[0]
        let signatureAlgorithm = firstOID(b, in: top[1]).flatMap { oidNames[$0] } ?? firstOID(b, in: top[1])

        var fields = children(b, tbs.start, tbs.end)
        var idx = 0

        // version [0] EXPLICIT (optional)
        if idx < fields.count, fields[idx].tag == 0xA0 { idx += 1 }
        // serialNumber INTEGER
        guard idx < fields.count, fields[idx].tag == 0x02 else { return nil }
        let serialHex = hexStrippingSign(b, fields[idx]); idx += 1
        // signature AlgorithmIdentifier (skip — same as outer)
        guard idx < fields.count else { return nil }; idx += 1
        // issuer Name
        guard idx < fields.count else { return nil }
        let issuerCN = commonName(b, fields[idx]); idx += 1
        // validity SEQUENCE { notBefore, notAfter }
        guard idx < fields.count else { return nil }
        let validity = children(b, fields[idx].start, fields[idx].end); idx += 1
        let notBefore = validity.count > 0 ? parseTime(b, validity[0]) : nil
        let notAfter = validity.count > 1 ? parseTime(b, validity[1]) : nil
        // subject Name
        guard idx < fields.count else { return nil }
        let subjectCN = commonName(b, fields[idx]); idx += 1
        // subjectPublicKeyInfo (skip — key details come from the Security framework)
        guard idx < fields.count else { return nil }; idx += 1

        // Remaining optional fields; extensions are [3] (0xA3).
        var sans: [CertSAN] = []
        while idx < fields.count {
            let field = fields[idx]; idx += 1
            if field.tag == 0xA3 { sans = parseSANs(b, field) }
        }

        return X509Certificate(subjectCN: subjectCN, issuerCN: issuerCN, serialHex: serialHex,
                               notBefore: notBefore, notAfter: notAfter,
                               signatureAlgorithm: signatureAlgorithm, sans: sans)
    }

    // MARK: - Subject Alternative Names

    private static func parseSANs(_ b: [UInt8], _ extensionsExplicit: TLV) -> [CertSAN] {
        // [3] EXPLICIT wraps a SEQUENCE OF Extension.
        guard let extSeq = children(b, extensionsExplicit.start, extensionsExplicit.end).first,
              extSeq.tag == 0x30 else { return [] }

        for ext in children(b, extSeq.start, extSeq.end) {
            // Extension ::= SEQUENCE { extnID OID, critical BOOLEAN OPTIONAL, extnValue OCTET STRING }
            let parts = children(b, ext.start, ext.end)
            guard let oidTLV = parts.first, oidTLV.tag == 0x06,
                  decodeOID(b, oidTLV) == "2.5.29.17",
                  let octet = parts.last(where: { $0.tag == 0x04 }) else { continue }

            // extnValue OCTET STRING wraps a SEQUENCE OF GeneralName.
            guard let sanSeq = parseTLV(b, octet.start), sanSeq.tag == 0x30 else { return [] }
            return children(b, sanSeq.start, sanSeq.end).compactMap { generalName(b, $0) }
        }
        return []
    }

    private static func generalName(_ b: [UInt8], _ gn: TLV) -> CertSAN? {
        switch gn.tag {
        case 0x82:   // dNSName [2] IA5String
            return CertSAN(kind: .dns, value: ascii(b, gn))
        case 0x87:   // iPAddress [7] OCTET STRING
            return formatIP(Array(b[gn.start..<gn.end])).map { CertSAN(kind: .ip, value: $0) }
        default:
            return nil
        }
    }

    private static func formatIP(_ bytes: [UInt8]) -> String? {
        switch bytes.count {
        case 4:
            return bytes.map(String.init).joined(separator: ".")
        case 16:
            var high: UInt64 = 0, low: UInt64 = 0
            for i in 0..<8 { high = (high << 8) | UInt64(bytes[i]) }
            for i in 8..<16 { low = (low << 8) | UInt64(bytes[i]) }
            return IPv6Toolkit.Address(high: high, low: low).compressed
        default:
            return nil
        }
    }

    // MARK: - Names, OIDs, time, hex

    /// Walk a Name (SEQUENCE OF RDN(SET) OF ATV(SEQUENCE{OID,value})) for CN (2.5.4.3).
    private static func commonName(_ b: [UInt8], _ name: TLV) -> String? {
        for rdn in children(b, name.start, name.end) where rdn.tag == 0x31 {
            for atv in children(b, rdn.start, rdn.end) where atv.tag == 0x30 {
                let pair = children(b, atv.start, atv.end)
                guard pair.count == 2, pair[0].tag == 0x06, decodeOID(b, pair[0]) == "2.5.4.3" else { continue }
                return ascii(b, pair[1])
            }
        }
        return nil
    }

    private static func firstOID(_ b: [UInt8], in seq: TLV) -> String? {
        guard let oid = children(b, seq.start, seq.end).first(where: { $0.tag == 0x06 }) else { return nil }
        return decodeOID(b, oid)
    }

    private static func decodeOID(_ b: [UInt8], _ tlv: TLV) -> String {
        guard tlv.length > 0 else { return "" }
        var parts: [Int] = []
        let first = Int(b[tlv.start])
        parts.append(first / 40)
        parts.append(first % 40)
        var value = 0
        for i in (tlv.start + 1)..<tlv.end {
            let byte = Int(b[i])
            value = (value << 7) | (byte & 0x7F)
            if byte & 0x80 == 0 { parts.append(value); value = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    private static func ascii(_ b: [UInt8], _ tlv: TLV) -> String {
        String(decoding: b[tlv.start..<tlv.end], as: UTF8.self)
    }

    private static func hexStrippingSign(_ b: [UInt8], _ tlv: TLV) -> String {
        var bytes = Array(b[tlv.start..<tlv.end])
        while bytes.count > 1, bytes.first == 0x00 { bytes.removeFirst() }   // drop sign padding
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func parseTime(_ b: [UInt8], _ tlv: TLV) -> Date? {
        let raw = ascii(b, tlv)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch tlv.tag {
        case 0x17: formatter.dateFormat = "yyMMddHHmmss'Z'"      // UTCTime
        case 0x18: formatter.dateFormat = "yyyyMMddHHmmss'Z'"    // GeneralizedTime
        default:   return nil
        }
        return formatter.date(from: raw)
    }

    private static let oidNames: [String: String] = [
        "1.2.840.113549.1.1.5":  "sha1WithRSAEncryption",
        "1.2.840.113549.1.1.10": "rsassaPss",
        "1.2.840.113549.1.1.11": "sha256WithRSAEncryption",
        "1.2.840.113549.1.1.12": "sha384WithRSAEncryption",
        "1.2.840.113549.1.1.13": "sha512WithRSAEncryption",
        "1.2.840.10045.4.3.2":   "ecdsa-with-SHA256",
        "1.2.840.10045.4.3.3":   "ecdsa-with-SHA384",
        "1.2.840.10045.4.3.4":   "ecdsa-with-SHA512",
    ]
}
