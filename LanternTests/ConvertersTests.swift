//
//  ConvertersTests.swift
//  IPv4 base conversion (both directions) and MAC normalisation.
//

import Testing
@testable import Lantern

struct IPv4ConverterTests {

    @Test func rendersAllFourForms() {
        let forms = IPv4Converter.forms(from: 3_232_235_776)   // 192.168.1.0
        #expect(forms.dotted == "192.168.1.0")
        #expect(forms.hex == "0xC0A80100")
        #expect(forms.binary == "11000000.10101000.00000001.00000000")
        #expect(forms.integer == "3232235776")
    }

    @Test func boundaryValues() {
        #expect(IPv4Converter.forms(from: 0).dotted == "0.0.0.0")
        #expect(IPv4Converter.forms(from: .max).dotted == "255.255.255.255")
        #expect(IPv4Converter.forms(from: .max).hex == "0xFFFFFFFF")
    }

    @Test func parsesEachFormatToSameValue() throws {
        #expect(try IPv4Converter.parse("192.168.1.0", as: .dotted) == 3_232_235_776)
        #expect(try IPv4Converter.parse("0xC0A80100", as: .hex) == 3_232_235_776)
        #expect(try IPv4Converter.parse("c0a80100", as: .hex) == 3_232_235_776)   // 0x optional
        #expect(try IPv4Converter.parse("11000000.10101000.00000001.00000000", as: .binary) == 3_232_235_776)
        #expect(try IPv4Converter.parse("3232235776", as: .integer) == 3_232_235_776)
    }

    @Test func bidirectionalRoundTrip() throws {
        for value: UInt32 in [0, 1, 3_232_235_776, 2_886_729_777, .max] {
            let forms = IPv4Converter.forms(from: value)
            #expect(try IPv4Converter.parse(forms.dotted, as: .dotted) == value)
            #expect(try IPv4Converter.parse(forms.hex, as: .hex) == value)
            #expect(try IPv4Converter.parse(forms.binary, as: .binary) == value)
            #expect(try IPv4Converter.parse(forms.integer, as: .integer) == value)
        }
    }

    @Test func rejectsMalformedAndOutOfRange() {
        #expect(throws: IPv4Converter.ConvertError.self) { try IPv4Converter.parse("999.1.1.1", as: .dotted) }
        #expect(throws: IPv4Converter.ConvertError.self) { try IPv4Converter.parse("0xGG", as: .hex) }
        #expect(throws: IPv4Converter.ConvertError.self) { try IPv4Converter.parse("0102", as: .binary) }   // '2' isn't a bit
        #expect(throws: IPv4Converter.ConvertError.self) { try IPv4Converter.parse("-1", as: .integer) }
        #expect(throws: IPv4Converter.ConvertError.outOfRange("4294967296")) {
            try IPv4Converter.parse("4294967296", as: .integer)
        }
        #expect(throws: IPv4Converter.ConvertError.empty) { try IPv4Converter.parse("   ", as: .hex) }
    }
}

struct MACAddressTests {

    @Test func allFourInputShapesAreEquivalent() throws {
        let colon  = try MACAddress.parse("00:1b:63:84:45:e6")
        let hyphen = try MACAddress.parse("00-1b-63-84-45-e6")
        let dot    = try MACAddress.parse("001b.6384.45e6")
        let bare   = try MACAddress.parse("001b638445e6")
        #expect(colon == hyphen)
        #expect(colon == dot)
        #expect(colon == bare)
        #expect(colon.bytes == [0x00, 0x1b, 0x63, 0x84, 0x45, 0xe6])
    }

    @Test func parsingIsCaseInsensitive() throws {
        #expect(try MACAddress.parse("AA:BB:CC:DD:EE:FF").bytes == [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
    }

    @Test func rendersEveryCanonicalForm() throws {
        let mac = try MACAddress.parse("AA-BB-CC-DD-EE-FF")
        #expect(mac.colon == "aa:bb:cc:dd:ee:ff")
        #expect(mac.hyphen == "aa-bb-cc-dd-ee-ff")
        #expect(mac.dot == "aabb.ccdd.eeff")
        #expect(mac.bare == "aabbccddeeff")
        #expect(mac.oui == [0xaa, 0xbb, 0xcc])
    }

    @Test func flagsAndErrors() throws {
        #expect(try MACAddress.parse("02:00:00:00:00:00").isLocallyAdministered)
        #expect(try !MACAddress.parse("00:00:00:00:00:00").isLocallyAdministered)
        #expect(try MACAddress.parse("01:00:5e:00:00:fb").isGroup)

        #expect(throws: MACAddress.ParseError.self) { try MACAddress.parse("00:11:22") }
        #expect(throws: MACAddress.ParseError.self) { try MACAddress.parse("zz:11:22:33:44:55") }
    }
}
