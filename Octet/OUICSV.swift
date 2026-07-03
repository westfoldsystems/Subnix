//
//  OUICSV.swift
//  Converts the IEEE `oui.csv` (Registry, Assignment, Organization Name,
//  Organization Address) into the bundled `oui-mal.tsv` format
//  (ASSIGNMENT<TAB>Organization) used by OUILookup. Pure — no I/O — so the
//  parsing is unit-tested independently of the network fetch.
//
//  A minimal but correct CSV reader: it handles quoted fields with embedded
//  commas, doubled ("") quotes, and quoted newlines, which the IEEE data uses.
//

import Foundation

enum OUICSV {

    /// MA-L rows of `oui.csv` as `ASSIGNMENT<TAB>Org` lines. The header row and
    /// any non-MA-L / malformed rows are dropped; org whitespace is collapsed.
    nonisolated static func toTSV(_ csv: String) -> String {
        var out = ""
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var quoteSeen = false      // saw a quote inside a quoted field; awaiting disambiguation
        var isHeader = true

        func endField() { fields.append(field); field = "" }
        func endRecord() {
            endField()
            defer { fields.removeAll(keepingCapacity: true) }
            if isHeader { isHeader = false; return }
            guard fields.count >= 3 else { return }
            let registry = fields[0].trimmingCharacters(in: .whitespaces)
            let assignment = fields[1].trimmingCharacters(in: .whitespaces).uppercased()
            let org = fields[2].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard registry == "MA-L", assignment.count == 6,
                  assignment.allSatisfy(\.isHexDigit), !org.isEmpty else { return }
            out += assignment + "\t" + org + "\n"
        }

        for scalar in csv.unicodeScalars {
            let c = Character(scalar)
            if quoteSeen {
                quoteSeen = false
                if c == "\"" { field.append("\""); continue }   // escaped "" → literal quote
                inQuotes = false                                // the quote closed the field; fall through
            }
            if inQuotes {
                if c == "\"" { quoteSeen = true } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\n": endRecord()
                case "\r": continue
                default:   field.append(c)
                }
            }
        }
        if !field.isEmpty || !fields.isEmpty { endRecord() }   // trailing record, no final newline
        return out
    }
}
