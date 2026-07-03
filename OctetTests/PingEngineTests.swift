//
//  PingEngineTests.swift
//  Pure echo-reply matching. The socket loop is I/O and validated by hand.
//

import Testing
@testable import Octet

struct PingEngineTests {

    /// Build an ICMP echo-reply message (no IP header) at offset 0.
    private func reply(type: UInt8, seq: UInt16, payload: [UInt8]) -> [UInt8] {
        var msg: [UInt8] = [type, 0, 0, 0, 0, 0, UInt8(seq >> 8), UInt8(seq & 0xFF)]
        msg += payload
        return msg
    }

    @Test func acceptsOurReply() {
        let buf = reply(type: 129, seq: 7, payload: PingEngine.echoPayload)
        #expect(PingEngine.isEchoReply(buf, offset: 0, available: buf.count, expectSeq: 7, isV6: true))
    }

    @Test func rejectsWrongSequence() {
        let buf = reply(type: 129, seq: 7, payload: PingEngine.echoPayload)
        #expect(!PingEngine.isEchoReply(buf, offset: 0, available: buf.count, expectSeq: 8, isV6: true))
    }

    @Test func rejectsWrongType() {
        // Echo *request* (128) is not a reply.
        let buf = reply(type: 128, seq: 7, payload: PingEngine.echoPayload)
        #expect(!PingEngine.isEchoReply(buf, offset: 0, available: buf.count, expectSeq: 7, isV6: true))
    }

    @Test func rejectsForgedPayload() {
        // Right type + seq, but the payload wasn't echoed back → spoof, rejected.
        var forged = PingEngine.echoPayload
        forged[0] ^= 0xFF
        let buf = reply(type: 129, seq: 7, payload: forged)
        #expect(!PingEngine.isEchoReply(buf, offset: 0, available: buf.count, expectSeq: 7, isV6: true))
    }

    @Test func rejectsTruncated() {
        let buf = reply(type: 129, seq: 7, payload: PingEngine.echoPayload)
        // Claim only the header is present — payload can't be verified.
        #expect(!PingEngine.isEchoReply(buf, offset: 0, available: 8, expectSeq: 7, isV6: true))
    }

    @Test func honorsIPv4HeaderOffset() {
        // 20-byte IPv4 header then the ICMP reply (type 0 for v4).
        let header = [UInt8](repeating: 0, count: 20)
        let buf = header + reply(type: 0, seq: 3, payload: PingEngine.echoPayload)
        #expect(PingEngine.isEchoReply(buf, offset: 20, available: buf.count, expectSeq: 3, isV6: false))
    }
}
