//
//  OUILookup.swift
//  Offline MAC → manufacturer lookup against a LOCALLY bundled IEEE OUI table.
//  No network, no API: the whole point is that vendor resolution works on a
//  plane. This file is the engine + the file-format contract only — it ships no
//  vendor data. The actual database is a sourcing decision flagged for the owner
//  (see SupportingFiles/Info-plist-setup.md → "OUI database").
//
//  File format ("oui-mal.tsv", UTF-8, one assignment per line):
//
//      # comments and blank lines are ignored
//      001B63<TAB>Apple, Inc.
//      3C5AB4<TAB>Google, Inc.
//
//  Column 1 is the 24-bit MA-L assignment as 6 hex digits (no separators, case
//  insensitive). Column 2 is the organization name, verbatim. v1 handles MA-L
//  (24-bit) only; MA-M (28-bit) and MA-S (36-bit) are a later schema bump.
//

import Foundation

struct OUILookup {

    /// 24-bit MA-L prefix → organization name.
    private let entries: [UInt32: String]

    /// How many assignments are loaded. Zero means "no database bundled yet".
    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    init(entries: [UInt32: String]) {
        self.entries = entries
    }

    // MARK: - Lookup

    /// The vendor for a MAC's 24-bit OUI, or nil if unknown / no database.
    func vendor(for mac: MACAddress) -> String? {
        entries[Self.key(forOUI: mac.oui)]
    }

    private static func key(forOUI oui: [UInt8]) -> UInt32 {
        (UInt32(oui[0]) << 16) | (UInt32(oui[1]) << 8) | UInt32(oui[2])
    }

    // MARK: - Loading

    /// Parse the bundled TSV format. Malformed lines are skipped, not fatal —
    /// a single bad row shouldn't sink the whole table.
    static func parse(_ text: String) -> OUILookup {
        var entries: [UInt32: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let prefix = parts[0].trimmingCharacters(in: .whitespaces)
            let vendor = parts[1].trimmingCharacters(in: .whitespaces)
            guard prefix.count == 6, prefix.allSatisfy(\.isHexDigit),
                  let key = UInt32(prefix, radix: 16), !vendor.isEmpty else {
                continue
            }
            entries[key] = vendor
        }
        return OUILookup(entries: entries)
    }

    /// The bundled database, parsed exactly once. SwiftUI recreates view structs
    /// constantly, so the UI must read this rather than re-parsing 39k rows per init.
    static let shared = OUILookup.bundled()

    /// Load `oui-mal.tsv` from the app bundle. Returns an empty table (not an
    /// error) when the file isn't present, so the UI can degrade gracefully
    /// until a database is bundled.
    static func bundled(in bundle: Bundle = .main) -> OUILookup {
        guard let url = bundle.url(forResource: "oui-mal", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return OUILookup(entries: [:])
        }
        return parse(text)
    }
}
