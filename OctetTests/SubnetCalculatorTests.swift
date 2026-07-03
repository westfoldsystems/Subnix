//
//  SubnetCalculatorTests.swift
//  Known-answer coverage for the IPv4 subnet math, including the edge cases the
//  engine calls out: /31 (RFC 3021), /32, and /0.
//

import Testing
@testable import Octet

struct SubnetCalculatorTests {

    @Test func standardSlash24() throws {
        let r = try SubnetCalculator.calculate("192.168.1.10/24")
        #expect(r.networkAddress == "192.168.1.0")
        #expect(r.broadcastAddress == "192.168.1.255")
        #expect(r.firstUsableHost == "192.168.1.1")
        #expect(r.lastUsableHost == "192.168.1.254")
        #expect(r.usableHostCount == 254)
        #expect(r.totalAddresses == 256)
        #expect(r.subnetMask == "255.255.255.0")
        #expect(r.wildcardMask == "0.0.0.255")
        #expect(r.cidr == "192.168.1.0/24")
        #expect(r.addressClass == "C")
        #expect(r.isPrivate)
    }

    @Test func slash31IsPointToPoint() throws {
        // RFC 3021: both addresses usable, no broadcast.
        let r = try SubnetCalculator.calculate("10.0.0.0/31")
        #expect(r.broadcastAddress == nil)
        #expect(r.firstUsableHost == "10.0.0.0")
        #expect(r.lastUsableHost == "10.0.0.1")
        #expect(r.usableHostCount == 2)
        #expect(r.totalAddresses == 2)
    }

    @Test func slash32IsSingleHost() throws {
        let r = try SubnetCalculator.calculate("192.168.1.5/32")
        #expect(r.broadcastAddress == nil)
        #expect(r.firstUsableHost == "192.168.1.5")
        #expect(r.lastUsableHost == "192.168.1.5")
        #expect(r.usableHostCount == 1)
        #expect(r.totalAddresses == 1)
    }

    @Test func slash0DoesNotOverflow() throws {
        let r = try SubnetCalculator.calculate("0.0.0.0/0")
        #expect(r.totalAddresses == 4_294_967_296)      // 2^32, needs UInt64
        #expect(r.usableHostCount == 4_294_967_294)
    }

    @Test func classAndPrivacyClassification() throws {
        #expect(try SubnetCalculator.calculate("8.8.8.8/24").isPrivate == false)
        #expect(try SubnetCalculator.calculate("8.8.8.8/24").addressClass == "A")
        #expect(try SubnetCalculator.calculate("172.16.5.4/20").isPrivate)      // 172.16/12
        #expect(try SubnetCalculator.calculate("172.32.5.4/20").isPrivate == false)
    }

    @Test func defaultPrefixAppliesWhenOmitted() throws {
        let r = try SubnetCalculator.calculate("192.168.1.1", defaultPrefix: 24)
        #expect(r.prefix == 24)
        #expect(r.networkAddress == "192.168.1.0")
    }

    @Test func rejectsMalformedInput() {
        #expect(throws: SubnetCalculator.CalculationError.self) {
            try SubnetCalculator.calculate("1.2.3/24")            // too few octets
        }
        #expect(throws: SubnetCalculator.CalculationError.self) {
            try SubnetCalculator.calculate("999.1.1.1/24")        // octet > 255
        }
        #expect(throws: SubnetCalculator.CalculationError.self) {
            try SubnetCalculator.calculate("1.2.3.4/33")          // prefix > 32
        }
        #expect(throws: SubnetCalculator.CalculationError.self) {
            try SubnetCalculator.calculate("1.2.3.4")             // no prefix, no default
        }
    }
}
