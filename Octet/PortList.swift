//
//  PortList.swift
//  Pure, offline helpers for the TCP Port Check: the common-ports preset, the
//  port→service-name labels, and a parser for a user's port spec. No I/O here,
//  so it's unit-tested independently of the network probing.
//

import Foundation

enum PortList {

    /// A pragmatic "scan the usual suspects" preset.
    static let common: [Int] = [
        21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 587, 993, 995,
        1433, 3306, 3389, 5432, 5900, 6379, 8080, 8443,
    ]

    /// Well-known service names for nicer row labels. Not exhaustive — unknown
    /// ports just render without a name.
    static let serviceNames: [Int: String] = [
        21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp", 53: "dns",
        80: "http", 110: "pop3", 143: "imap", 443: "https", 445: "smb",
        587: "submission", 993: "imaps", 995: "pop3s", 1433: "mssql",
        3306: "mysql", 3389: "rdp", 5432: "postgres", 5900: "vnc",
        6379: "redis", 8080: "http-alt", 8443: "https-alt",
    ]

    static func serviceName(for port: Int) -> String? { serviceNames[port] }

    enum ParseError: LocalizedError, Equatable {
        case empty
        case notANumber(String)
        case outOfRange(String)
        case badRange(String)

        var errorDescription: String? {
            switch self {
            case .empty:              return "Enter a port or list of ports."
            case .notANumber(let s):  return "“\(s)” isn’t a port number."
            case .outOfRange(let s):  return "“\(s)” is outside 1–65535."
            case .badRange(let s):    return "“\(s)” isn’t a valid range (use low-high)."
            }
        }
    }

    /// Parse a comma/space-separated spec with optional ranges, e.g.
    /// `"22, 80, 443, 8000-8010"`. Result is sorted and de-duplicated.
    static func parse(_ raw: String) throws -> [Int] {
        let tokens = raw.split { $0 == "," || $0 == " " }.map(String.init)
        guard !tokens.isEmpty else { throw ParseError.empty }

        var ports = Set<Int>()
        for token in tokens {
            if token.contains("-") {
                let bounds = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard bounds.count == 2,
                      let lo = Int(bounds[0]), let hi = Int(bounds[1]) else {
                    throw ParseError.badRange(token)
                }
                guard isValid(lo) else { throw ParseError.outOfRange(bounds[0]) }
                guard isValid(hi) else { throw ParseError.outOfRange(bounds[1]) }
                guard lo <= hi else { throw ParseError.badRange(token) }
                for p in lo...hi { ports.insert(p) }
            } else {
                guard let p = Int(token) else { throw ParseError.notANumber(token) }
                guard isValid(p) else { throw ParseError.outOfRange(token) }
                ports.insert(p)
            }
        }
        return ports.sorted()
    }

    private static func isValid(_ port: Int) -> Bool { (1...65535).contains(port) }
}
