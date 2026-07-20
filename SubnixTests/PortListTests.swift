//
//  PortListTests.swift
//  The pure port-spec parser, presets, and service-name lookup. (The network
//  probing in PortScanner is integration-tested by hand, not here.)
//

import Testing
@testable import Subnix

struct PortListTests {

    @Test func parsesSingleAndList() throws {
        #expect(try PortList.parse("443") == [443])
        #expect(try PortList.parse("80, 443, 22") == [22, 80, 443])   // sorted
        #expect(try PortList.parse("80 443 8080") == [80, 443, 8080]) // space-separated
    }

    @Test func parsesRangesAndDeduplicates() throws {
        #expect(try PortList.parse("8000-8003") == [8000, 8001, 8002, 8003])
        // Overlap + duplicates collapse.
        #expect(try PortList.parse("80, 80, 79-81") == [79, 80, 81])
    }

    @Test func rejectsBadInput() {
        #expect(throws: PortList.ParseError.empty) { try PortList.parse("   ") }
        #expect(throws: PortList.ParseError.notANumber("ssh")) { try PortList.parse("ssh") }
        #expect(throws: PortList.ParseError.outOfRange("0")) { try PortList.parse("0") }
        #expect(throws: PortList.ParseError.outOfRange("70000")) { try PortList.parse("70000") }
        #expect(throws: PortList.ParseError.badRange("443-22")) { try PortList.parse("443-22") }
        #expect(throws: PortList.ParseError.self) { try PortList.parse("80-") }
    }

    @Test func presetAndServiceNames() {
        #expect(PortList.common.contains(443))
        #expect(PortList.common.contains(22))
        #expect(PortList.serviceName(for: 443) == "https")
        #expect(PortList.serviceName(for: 22) == "ssh")
        #expect(PortList.serviceName(for: 12345) == nil)
    }
}
