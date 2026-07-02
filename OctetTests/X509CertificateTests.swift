//
//  X509CertificateTests.swift
//  DER/ASN.1 parsing against a bundled fixture — a self-signed cert generated
//  with known SANs (DNS + IPv4 + IPv6) so SAN extraction is verified exactly.
//  Reference values cross-checked with `openssl x509`.
//

import Testing
import Foundation
@testable import Octet

private final class _TestBundleAnchor {}

struct X509CertificateTests {

    private func loadFixture() throws -> [UInt8] {
        let bundle = Bundle(for: _TestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "sample-cert", withExtension: "der"),
                               "sample-cert.der must be bundled in the test target")
        return try [UInt8](Data(contentsOf: url))
    }

    @Test func parsesSubjectIssuerSerialAndSigAlg() throws {
        let cert = try #require(X509Certificate.parse(der: loadFixture()))
        #expect(cert.subjectCN == "octet.example")
        #expect(cert.issuerCN == "octet.example")          // self-signed
        #expect(cert.serialHex == "C3A355A4ECB5220F")      // matches `openssl -serial`
        #expect(cert.signatureAlgorithm == "sha256WithRSAEncryption")
    }

    @Test func extractsEverySAN_DNSandIP() throws {
        let cert = try #require(X509Certificate.parse(der: loadFixture()))

        let dns = cert.sans.filter { $0.kind == .dns }.map(\.value)
        let ip = cert.sans.filter { $0.kind == .ip }.map(\.value)

        // Every SAN captured — not just the CN, and both DNS + IP families.
        #expect(dns == ["example.com", "www.example.com"])
        #expect(ip.contains("192.0.2.1"))           // IPv4 SAN
        #expect(ip.contains("2001:db8::1"))         // IPv6 SAN, compressed
        #expect(cert.sans.count == 4)
    }

    @Test func parsesValidityWindow() throws {
        let cert = try #require(X509Certificate.parse(der: loadFixture()))
        let notBefore = try #require(cert.notBefore)
        let notAfter = try #require(cert.notAfter)
        #expect(notAfter > notBefore)
        // Generated with -days 3650; allow slack for leap days.
        let years = notAfter.timeIntervalSince(notBefore) / (365.25 * 86_400)
        #expect(years > 9.8 && years < 10.2)
    }

    @Test func rejectsGarbage() {
        #expect(X509Certificate.parse(der: [0x00, 0x01, 0x02]) == nil)
        #expect(X509Certificate.parse(der: []) == nil)
    }
}
