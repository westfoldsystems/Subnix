//
//  IPv4Converter.swift
//  Pure, offline IPv4 base conversion: dotted ↔ hex ↔ binary ↔ integer.
//
//  Everything funnels through a single UInt32, so the four renderings are always
//  consistent. Dotted parsing/formatting is borrowed from SubnetCalculator to
//  keep one source of truth for what a valid octet is.
//

import Foundation

struct IPv4Converter {

    /// Which notation an input string is written in.
    enum Format: String, CaseIterable, Identifiable {
        case dotted  = "Dotted"
        case hex     = "Hex"
        case binary  = "Binary"
        case integer = "Integer"

        var id: String { rawValue }
    }

    /// All four renderings of one address.
    struct Forms: Equatable {
        let dotted: String      // 192.168.1.0
        let hex: String         // 0xC0A80100
        let binary: String      // 11000000.10101000.00000001.00000000
        let integer: String     // 3232235776

        /// The rendering for a given format — used to transcode a field when the
        /// user flips the input format.
        func string(for format: Format) -> String {
            switch format {
            case .dotted:  return dotted
            case .hex:     return hex
            case .binary:  return binary
            case .integer: return integer
            }
        }
    }

    enum ConvertError: LocalizedError, Equatable {
        case empty
        case malformed(Format, String)
        case outOfRange(String)

        var errorDescription: String? {
            switch self {
            case .empty:                    return "Enter a value to convert."
            case .malformed(let f, let s):  return "“\(s)” isn’t valid \(f.rawValue.lowercased())."
            case .outOfRange(let s):        return "“\(s)” doesn’t fit in 32 bits."
            }
        }
    }

    // MARK: - Rendering

    static func forms(from value: UInt32) -> Forms {
        Forms(
            dotted: SubnetCalculator.format(value),
            hex: String(format: "0x%08X", value),
            binary: binaryString(value),
            integer: String(value)
        )
    }

    private static func binaryString(_ value: UInt32) -> String {
        (0..<4).map { byteIndex -> String in
            let byte = UInt8((value >> (8 * (3 - byteIndex))) & 0xFF)
            let bits = String(byte, radix: 2)
            return String(repeating: "0", count: 8 - bits.count) + bits
        }.joined(separator: ".")
    }

    // MARK: - Parsing

    /// Parse a string written in `format` to the underlying 32-bit value.
    static func parse(_ raw: String, as format: Format) throws -> UInt32 {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw ConvertError.empty }

        switch format {
        case .dotted:
            do { return try SubnetCalculator.parseIPv4(s) }
            catch { throw ConvertError.malformed(.dotted, s) }

        case .hex:
            var hex = s.lowercased()
            if hex.hasPrefix("0x") { hex.removeFirst(2) }
            guard !hex.isEmpty, hex.count <= 8, hex.allSatisfy(\.isHexDigit),
                  let value = UInt32(hex, radix: 16) else {
                throw ConvertError.malformed(.hex, s)
            }
            return value

        case .binary:
            let bits = s.filter { $0 != "." && $0 != " " }
            guard !bits.isEmpty, bits.count <= 32,
                  bits.allSatisfy({ $0 == "0" || $0 == "1" }),
                  let value = UInt32(bits, radix: 2) else {
                throw ConvertError.malformed(.binary, s)
            }
            return value

        case .integer:
            guard s.allSatisfy(\.isNumber) else { throw ConvertError.malformed(.integer, s) }
            guard let value = UInt32(s) else { throw ConvertError.outOfRange(s) }
            return value
        }
    }
}
