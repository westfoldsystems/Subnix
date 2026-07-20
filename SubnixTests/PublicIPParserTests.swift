//
//  PublicIPParserTests.swift
//  The pure reflection-response parsers. getifaddrs enumeration and the live
//  fetch are validated by hand, not here.
//

import Testing
import Foundation
@testable import Subnix

struct PublicIPParserTests {

    @Test func parsesCloudflareTrace() {
        let body = """
        fl=123abc
        h=1.1.1.1
        ip=203.0.113.7
        ts=1700000000.123
        visit_scheme=https
        """
        #expect(PublicIPParser.parseTrace(body) == "203.0.113.7")
    }

    @Test func parsesTraceWithIPv6() {
        #expect(PublicIPParser.parseTrace("ip=2001:db8::7\nts=1") == "2001:db8::7")
    }

    @Test func traceMissingIPReturnsNil() {
        #expect(PublicIPParser.parseTrace("fl=x\nts=1") == nil)
        #expect(PublicIPParser.parseTrace("ip=\n") == nil)   // empty value
    }

    @Test func parsesIPifyJSON() throws {
        let data = Data(#"{"ip":"198.51.100.42"}"#.utf8)
        #expect(PublicIPParser.parseIPify(data) == "198.51.100.42")
    }

    @Test func ipifyMalformedReturnsNil() {
        #expect(PublicIPParser.parseIPify(Data("not json".utf8)) == nil)
        #expect(PublicIPParser.parseIPify(Data(#"{"other":"x"}"#.utf8)) == nil)
        #expect(PublicIPParser.parseIPify(Data(#"{"ip":""}"#.utf8)) == nil)
    }
}
