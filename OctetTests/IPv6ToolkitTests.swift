//
//  IPv6ToolkitTests.swift
//  Compress/expand round trips, tricky "::" positions, prefix math, EUI-64.
//

import Testing
@testable import Octet

struct IPv6ToolkitTests {

    // MARK: - Canonicalisation

    @Test func compressFollowsRFC5952() throws {
        #expect(try IPv6Toolkit.parse("2001:0db8:0000:0000:0000:0000:0000:0001").compressed == "2001:db8::1")
        #expect(try IPv6Toolkit.parse("::").compressed == "::")
        #expect(try IPv6Toolkit.parse("0:0:0:0:0:0:0:1").compressed == "::1")
        #expect(try IPv6Toolkit.parse("1:0:0:0:0:0:0:8").compressed == "1::8")
        // Two equal-length zero runs: leftmost is compressed.
        #expect(try IPv6Toolkit.parse("2001:db8:0:0:1:0:0:1").compressed == "2001:db8::1:0:0:1")
        // A single zero group is NOT shortened to "::".
        #expect(try IPv6Toolkit.parse("1:2:3:4:5:6:0:8").compressed == "1:2:3:4:5:6:0:8")
    }

    @Test func expandIsEightFourDigitGroups() throws {
        #expect(try IPv6Toolkit.parse("2001:db8::1").expanded == "2001:0db8:0000:0000:0000:0000:0000:0001")
        #expect(try IPv6Toolkit.parse("::").expanded == "0000:0000:0000:0000:0000:0000:0000:0000")
    }

    @Test func roundTripCompressedExpanded() throws {
        for text in ["2001:db8::1", "fe80::1", "::1", "ff02::fb", "2001:db8:0:0:1:0:0:1"] {
            let a = try IPv6Toolkit.parse(text)
            // Re-parsing either rendering yields the same address.
            #expect(try IPv6Toolkit.parse(a.compressed) == a)
            #expect(try IPv6Toolkit.parse(a.expanded) == a)
        }
    }

    // MARK: - Embedded IPv4

    @Test func embeddedIPv4ParsesAndCompresses() throws {
        let a = try IPv6Toolkit.parse("::ffff:1.2.3.4")
        #expect(a.compressed == "::ffff:102:304")
        #expect(a.expanded == "0000:0000:0000:0000:0000:ffff:0102:0304")
        #expect(try IPv6Toolkit.parse("::ffff:102:304") == a)   // round trip
    }

    @Test func embeddedIPv4MustBeLast() {
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("1.2.3.4::1") }
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("::1.2.3.4:5") }
    }

    // MARK: - Tricky "::" positions

    @Test func doubleColonAtEdges() throws {
        #expect(try IPv6Toolkit.parse("::1:2:3:4:5:6:7").expanded == "0000:0001:0002:0003:0004:0005:0006:0007")
        #expect(try IPv6Toolkit.parse("1:2:3:4:5:6:7::").expanded == "0001:0002:0003:0004:0005:0006:0007:0000")
    }

    @Test func malformedAddressesRejected() {
        #expect(throws: IPv6Toolkit.ParseError.tooManyDoubleColons) { try IPv6Toolkit.parse("1::2::3") }
        // 8 explicit groups leave no room for "::" to absorb anything.
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("1:2:3:4::5:6:7:8") }
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("1:2:3") }
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("12345::") }
        #expect(throws: IPv6Toolkit.ParseError.self) { try IPv6Toolkit.parse("gggg::") }
        #expect(throws: IPv6Toolkit.ParseError.empty) { try IPv6Toolkit.parse("   ") }
    }

    // MARK: - Prefix math

    @Test func prefixReportNetworkAndBounds() throws {
        let addr = try IPv6Toolkit.parse("2001:db8:abcd:1234::1")
        let report = try IPv6Toolkit.prefixReport(addr, prefix: 32)
        #expect(report.network == "2001:db8::")
        #expect(report.firstAddress == "2001:db8::")
        #expect(report.lastAddress == "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff")
        #expect(report.addressCountExponent == 96)
    }

    @Test func prefixCrossesTheHighLowBoundary() throws {
        // /64 splits exactly at the high/low halves.
        let report = try IPv6Toolkit.prefixReport(try IPv6Toolkit.parse("2001:db8::abcd:1"), prefix: 64)
        #expect(report.network == "2001:db8::")
        #expect(report.lastAddress == "2001:db8::ffff:ffff:ffff:ffff")
    }

    @Test func prefixOutOfRangeThrows() {
        #expect(throws: IPv6Toolkit.ParseError.prefixOutOfRange(129)) {
            try IPv6Toolkit.prefixReport(IPv6Toolkit.Address(high: 0, low: 0), prefix: 129)
        }
    }

    @Test func powerOfTwoDecimalIsExact() {
        #expect(IPv6Toolkit.powerOfTwoDecimal(0) == "1")
        #expect(IPv6Toolkit.powerOfTwoDecimal(8) == "256")
        #expect(IPv6Toolkit.powerOfTwoDecimal(10) == "1024")
        #expect(IPv6Toolkit.powerOfTwoDecimal(64) == "18446744073709551616")
        #expect(IPv6Toolkit.powerOfTwoDecimal(128) == "340282366920938463463374607431768211456")
    }

    // MARK: - EUI-64

    @Test func eui64FlipsBitAndSplicesFFFE() throws {
        let mac = try MACAddress.parse("00:1b:63:84:45:e6")
        let report = IPv6Toolkit.eui64(from: mac)
        #expect(report.interfaceID == "021b:63ff:fe84:45e6")
        #expect(report.linkLocal == "fe80::21b:63ff:fe84:45e6")
    }
}
