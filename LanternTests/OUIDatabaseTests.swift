//
//  OUIDatabaseTests.swift
//  Sanity checks against the REAL bundled IEEE MA-L registry (oui-mal.tsv).
//  Separate from OUILookupTests, which exercises the codec on a synthetic
//  fixture. These assertions use long-stable, well-known assignments and a
//  loose size floor so an IEEE refresh won't make them flaky.
//

import Testing
import Foundation
@testable import Lantern

struct OUIDatabaseTests {

    private var database: OUILookup { OUILookup.bundled() }

    @Test func registryIsBundledAndSubstantial() {
        // The full MA-L list is ~39k assignments; anything this large means the
        // file shipped and parsed. (A missing file would be 0.)
        #expect(database.count > 20_000)
    }

    @Test func resolvesWellKnownOUIs() throws {
        let db = database
        // 00:00:00 has been XEROX since the registry began.
        let xerox = db.vendor(for: try MACAddress.parse("00:00:00:12:34:56"))
        #expect(xerox?.localizedCaseInsensitiveContains("xerox") == true)

        // 00:1B:63 is Apple — present and non-empty.
        #expect(db.vendor(for: try MACAddress.parse("00:1b:63:84:45:e6"))?.isEmpty == false)
    }

    @Test func unassignedPrefixReturnsNil() throws {
        // Locally-administered space (x2/x6/xA/xE first octet) is never an OUI.
        #expect(database.vendor(for: try MACAddress.parse("02:00:00:00:00:01")) == nil)
    }
}
