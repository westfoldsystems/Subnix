//
//  OUILookupTests.swift
//  Exercises the TSV codec and lookup logic against a SYNTHETIC fixture — these
//  vendor names are invented for the test only and are not real IEEE data.
//

import Testing
@testable import Subnix

struct OUILookupTests {

    // Obviously-fake names + prefixes so nothing here is mistaken for real data.
    private static let fixture = """
    # sample OUI table — synthetic
    0000FF\tVendor One
    abcdef\tVendor Two

    \tNo prefix
    GGGGGG\tBad hex
    001\tToo short
    123456\t
    """

    @Test func parsesValidRowsAndSkipsJunk() {
        let db = OUILookup.parse(Self.fixture)
        // Only the two well-formed rows survive; comments/blank/malformed are skipped.
        #expect(db.count == 2)
    }

    @Test func looksUpByOUICaseInsensitively() throws {
        let db = OUILookup.parse(Self.fixture)
        #expect(db.vendor(for: try MACAddress.parse("00:00:ff:11:22:33")) == "Vendor One")
        // Lowercase prefix in the file still matches an uppercase MAC.
        #expect(db.vendor(for: try MACAddress.parse("AB:CD:EF:00:00:01")) == "Vendor Two")
    }

    @Test func unknownAndEmpty() throws {
        let db = OUILookup.parse(Self.fixture)
        #expect(db.vendor(for: try MACAddress.parse("de:ad:be:ef:00:00")) == nil)

        let empty = OUILookup(entries: [:])
        #expect(empty.isEmpty)
        #expect(empty.vendor(for: try MACAddress.parse("00:00:ff:00:00:00")) == nil)
    }
}
