//
//  LANScannerTests.swift
//  Pure subnet-derivation helpers. The sweep, ARP read, and enrichment are I/O
//  and validated by hand (macOS / real LAN) — not here.
//

import Testing
@testable import Lantern

struct LANScannerTests {

    @Test func slash24EnumeratesUsableHosts() throws {
        let plan = try #require(LANScanner.slash24(for: "192.168.1.137"))
        #expect(plan.network == "192.168.1.0/24")
        #expect(plan.hosts.count == 254)
        #expect(plan.hosts.first == "192.168.1.1")
        #expect(plan.hosts.last == "192.168.1.254")
    }

    @Test func slash24RejectsMalformed() {
        #expect(LANScanner.slash24(for: "not.an.ip") == nil)
        #expect(LANScanner.slash24(for: "10.0.0") == nil)
        #expect(LANScanner.slash24(for: "999.1.1.1") == nil)
    }

    @Test func sameSlash24Membership() {
        #expect(LANScanner.inSameSlash24("192.168.1.5", as: "192.168.1.0/24"))
        #expect(!LANScanner.inSameSlash24("192.168.2.5", as: "192.168.1.0/24"))
        #expect(!LANScanner.inSameSlash24("192.168.1.5", as: nil))
    }

    @Test func ipOrdering() {
        #expect(LANScanner.ipLess("192.168.1.2", "192.168.1.10"))
        #expect(!LANScanner.ipLess("192.168.1.10", "192.168.1.2"))
    }
}
