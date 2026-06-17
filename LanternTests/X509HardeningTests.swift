//
//  X509HardeningTests.swift
//  Adversarial / malformed DER. Every case must fail gracefully — return nil or
//  a partial value, never crash, loop, or read out of bounds. (A hard crash here
//  would take down the whole test run, so these passing IS the proof.)
//

import Testing
import Foundation
@testable import Lantern

private final class _X509Anchor {}

struct X509HardeningTests {

    @Test func rejectsStructurallyBrokenDER() {
        let cases: [[UInt8]] = [
            [],                                   // empty
            [0x30],                               // tag only
            [0x30, 0x82, 0xFF, 0xFF],             // SEQUENCE claims 65535 bytes, none present
            [0x30, 0x84, 0x00, 0x00, 0x00, 0x10], // 4-byte length 16, no content
            [0x30, 0x80, 0x00, 0x00],             // indefinite length (illegal in DER)
            [0x30, 0x85, 0x01, 0x02, 0x03, 0x04, 0x05], // 5-byte length (>4) rejected
            [0x02, 0x01, 0x05],                   // top-level INTEGER, not a SEQUENCE
            Array(repeating: 0xFF, count: 64),    // garbage
            [0x30, 0x03, 0x30, 0x01, 0x30],       // nested SEQUENCE whose child overruns
        ]
        for input in cases {
            // No crash; not a valid cert.
            #expect(X509Certificate.parse(der: input) == nil)
        }
    }

    @Test func deeplyNestedDoesNotOverflow() {
        // 200 nested SEQUENCE headers then nothing — must not recurse-crash.
        var bytes: [UInt8] = []
        for _ in 0..<200 { bytes += [0x30, 0x82, 0x00, 0x00] }
        #expect(X509Certificate.parse(der: bytes) == nil)
    }

    @Test func everyTruncationOfRealCertIsSafe() throws {
        let url = try #require(Bundle(for: _X509Anchor.self).url(forResource: "sample-cert", withExtension: "der"))
        let full = try [UInt8](Data(contentsOf: url))
        // Parse every prefix; bounds bugs surface as a crash, otherwise nil/partial.
        for length in 0...full.count {
            _ = X509Certificate.parse(der: Array(full.prefix(length)))
        }
        // The complete cert still parses correctly after the hardening pass.
        #expect(X509Certificate.parse(der: full)?.subjectCN == "lantern.example")
    }

    @Test func byteFlipsNeverCrash() throws {
        let url = try #require(Bundle(for: _X509Anchor.self).url(forResource: "sample-cert", withExtension: "der"))
        var bytes = try [UInt8](Data(contentsOf: url))
        // Deterministically corrupt one byte at a time across the whole cert.
        for i in bytes.indices {
            let original = bytes[i]
            bytes[i] = original ^ 0xFF
            _ = X509Certificate.parse(der: bytes)   // must just return
            bytes[i] = original
        }
    }

    @Test func pseudoRandomFuzzNeverCrashes() {
        // Simple deterministic LCG so the run is reproducible.
        var seed: UInt64 = 0x1234_5678_9abc_def0
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
        for _ in 0..<2000 {
            let count = Int(next() % 300)
            let bytes = (0..<count).map { _ in UInt8(next() & 0xFF) }
            _ = X509Certificate.parse(der: bytes)   // must just return
        }
    }
}
