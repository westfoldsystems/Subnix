//
//  TLSInspectorTests.swift
//  Pure validity-verdict and cipher-name mapping. The handshake + metadata read
//  are I/O and validated by hand against real servers — not here.
//

import Testing
import Foundation
@testable import Octet

struct TLSInspectorTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)   // fixed reference

    @Test func validityBuckets() {
        let day: TimeInterval = 86_400
        // 100 days left → valid.
        if case .valid(let d)? = TLSInspector.validity(notBefore: now - day, notAfter: now + 100 * day, now: now) {
            #expect(d == 100)
        } else { Issue.record("expected .valid") }

        // 10 days left → expiring soon (≤ 30).
        if case .expiringSoon(let d)? = TLSInspector.validity(notBefore: now - day, notAfter: now + 10 * day, now: now) {
            #expect(d == 10)
        } else { Issue.record("expected .expiringSoon") }

        #expect(TLSInspector.validity(notBefore: now - 10 * day, notAfter: now - day, now: now) == .expired)
        #expect(TLSInspector.validity(notBefore: now + day, notAfter: now + 10 * day, now: now) == .notYetValid)
        #expect(TLSInspector.validity(notBefore: now, notAfter: nil, now: now) == nil)
    }

    @Test func cipherNames() {
        #expect(TLSInspector.cipherName(0x1301) == "TLS_AES_128_GCM_SHA256")
        #expect(TLSInspector.cipherName(0x1303) == "TLS_CHACHA20_POLY1305_SHA256")
        #expect(TLSInspector.cipherName(0xC02F) == "ECDHE_RSA_AES_128_GCM_SHA256")
        #expect(TLSInspector.cipherName(0x0000) == "0x0000")   // unknown → hex
    }
}
