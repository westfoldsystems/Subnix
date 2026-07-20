//
//  OUICSVTests.swift
//  Pure CSV→TSV conversion for the OUI updater. The network fetch is I/O and
//  validated by hand against the live IEEE registry.
//

import Testing
@testable import Subnix

struct OUICSVTests {

    @Test func convertsMALRowsOnly() {
        let csv = """
        Registry,Assignment,Organization Name,Organization Address
        MA-L,001B63,"Apple, Inc.","1 Infinite Loop, Cupertino CA"
        MA-L,3C5AB4,Google  LLC,MTV
        MA-M,0055DA,"Filtered Out",addr
        MA-L,ZZZZZZ,Bad Hex,addr
        MA-L,000000,XEROX CORPORATION,addr
        """
        let lines = OUICSV.toTSV(csv).split(separator: "\n").map(String.init)
        #expect(lines.contains("001B63\tApple, Inc."))       // quoted comma preserved
        #expect(lines.contains("3C5AB4\tGoogle LLC"))         // whitespace collapsed
        #expect(lines.contains("000000\tXEROX CORPORATION"))
        #expect(!lines.contains { $0.hasPrefix("0055DA") })   // MA-M filtered
        #expect(!lines.contains { $0.contains("Bad Hex") })   // bad hex filtered
        #expect(lines.count == 3)
    }

    @Test func handlesQuotedNewlinesAndEscapedQuotes() {
        // Org has a doubled ("") quote; the address field spans a newline.
        let csv = "Registry,Assignment,Organization Name,Organization Address\r\n"
                + "MA-L,ABCDEF,\"Acme \"\"X\"\" Co\",\"Line1\nLine2\"\r\n"
                + "MA-L,123456,Next Corp,addr\r\n"
        let lines = OUICSV.toTSV(csv).split(separator: "\n").map(String.init)
        #expect(lines.contains("ABCDEF\tAcme \"X\" Co"))
        #expect(lines.contains("123456\tNext Corp"))
        #expect(lines.count == 2)
    }

    @Test func outputFeedsOUILookup() throws {
        let csv = "Registry,Assignment,Organization Name,Organization Address\nMA-L,001B63,Apple Inc,addr\n"
        let lookup = OUILookup.parse(OUICSV.toTSV(csv))
        let mac = try MACAddress.parse("00:1b:63:11:22:33")
        #expect(lookup.vendor(for: mac) == "Apple Inc")
    }
}
