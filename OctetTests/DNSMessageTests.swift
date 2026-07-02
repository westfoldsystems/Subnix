//
//  DNSMessageTests.swift
//  Codec tests against REAL captured responses (compression pointers and all),
//  a hand-built SRV, and a battery of malformed/adversarial inputs proving the
//  decoder fails gracefully — never crashes, loops, or reads out of bounds.
//

import Testing
import Foundation
@testable import Octet

private func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

struct DNSMessageTests {

    // MARK: - Real captured responses (1.1.1.1 / 8.8.8.8)

    @Test func decodesARecords() throws {
        let r = try DNSMessage.decode(hex("123481800001000200000000076578616d706c6503636f6d0000010001c00c000100010000007b0004ac4293f3c00c000100010000007b00046814179a"))
        #expect(r.responseCode == 0)
        #expect(r.answers.count == 2)
        #expect(r.answers.allSatisfy { $0.type == .a })
        #expect(r.answers.map(\.data).contains("172.66.147.243"))
        #expect(r.answers.map(\.data).contains("104.20.23.154"))
        #expect(r.answers.first?.ttl == 123)
    }

    @Test func decodesAAAARecordsCompressed() throws {
        let r = try DNSMessage.decode(hex("123481800001000200000000076578616d706c6503636f6d00001c0001c00c001c00010000010000102606470000100000000000006814179ac00c001c0001000001000010260647000010000000000000ac4293f3"))
        let data = r.answers.map(\.data)
        #expect(r.answers.allSatisfy { $0.type == .aaaa })
        #expect(data.contains("2606:4700:10::6814:179a"))   // reuses IPv6Toolkit compression
        #expect(data.contains("2606:4700:10::ac42:93f3"))
    }

    @Test func decodesCNAMEThroughPointer() throws {
        let r = try DNSMessage.decode(hex("123481800001000100000000037777770667697468756203636f6d0000050001c00c0005000100000e100002c010"))
        #expect(r.answers.first?.type == .cname)
        #expect(r.answers.first?.data == "github.com")        // c010 pointer resolved
    }

    @Test func decodesPTR() throws {
        let r = try DNSMessage.decode(hex("123481800001000100000000013801380138013807696e2d61646472046172706100000c0001c00c000c000100013e5a000c03646e7306676f6f676c6500"))
        #expect(r.answers.first?.type == .ptr)
        #expect(r.answers.first?.data == "dns.google")
    }

    @Test func decodesTXT() throws {
        let r = try DNSMessage.decode(hex("123481800001000200000000076578616d706c6503636f6d0000100001c00c001000010000012c000c0b763d73706631202d616c6cc00c001000010000012c0021205f6b326e31793476773371746234736b6478396537647874393771726d6d7139"))
        #expect(r.answers.contains { $0.type == .txt && $0.data.contains("v=spf1 -all") })
    }

    @Test func decodesNS() throws {
        let r = try DNSMessage.decode(hex("123481800001000200000000076578616d706c6503636f6d0000020001c00c000200010001349c00150468657261026e730a636c6f7564666c617265c014c00c000200010001349c000a07656c6c696f7474c02e"))
        #expect(r.answers.count == 2)
        #expect(r.answers.allSatisfy { $0.type == .ns })
        #expect(r.answers.allSatisfy { $0.data.contains("cloudflare.com") })
    }

    @Test func decodesSOA() throws {
        let r = try DNSMessage.decode(hex("123481800001000100000000076578616d706c6503636f6d0000060001c00c0006000100000149003207656c6c696f7474026e730a636c6f7564666c617265c01403646e73c0348f64d468000027100000096000093a8000000708"))
        let soa = try #require(r.answers.first { $0.type == .soa })
        #expect(soa.data.contains("serial="))
        #expect(soa.data.contains("cloudflare.com"))
    }

    @Test func decodesMX() throws {
        let r = try DNSMessage.decode(hex("12348180000100050000000005676d61696c03636f6d00000f0001c00c000f0001000002e40020001404616c74320d676d61696c2d736d74702d696e016c06676f6f676c65c012c00c000f0001000002e40009001e04616c7433c02ec00c000f0001000002e40009002804616c7434c02ec00c000f0001000002e400040005c02ec00c000f0001000002e40009000a04616c7431c02e"))
        #expect(r.answers.count == 5)
        #expect(r.answers.allSatisfy { $0.type == .mx })
        #expect(r.answers.contains { $0.data.contains("gmail-smtp-in.l.google.com") })
    }

    @Test func decodesCAA() throws {
        let r = try DNSMessage.decode(hex("12348180000100010000000006676f6f676c6503636f6d0001010001c00c0101000100013051000f00056973737565706b692e676f6f67"))
        let caa = try #require(r.answers.first { $0.rawType == 257 })
        #expect(caa.data.contains("issue"))
        #expect(caa.data.contains("pki.goog"))
    }

    @Test func decodesSRVWithPointerTarget() throws {
        // Hand-built: question _sip._tcp.example.com SRV; one answer
        // prio=10 weight=20 port=5060 target=(pointer to example.com).
        let bytes = hex(
            "123481800001000100000000" +          // header: QD=1 AN=1
            "045f736970045f746370" +              // _sip _tcp
            "076578616d706c6503636f6d00" +        // example com root  (example@22, com@30)
            "00210001" +                          // qtype SRV, qclass IN
            "c00c00210001000003e8" +              // answer: name->12, SRV, IN, ttl=1000
            "0008" +                              // rdlength = 8
            "000a001413c4" +                      // prio=10 weight=20 port=5060
            "c016"                                // target -> offset 22 = example.com
        )
        let r = try DNSMessage.decode(bytes)
        #expect(r.answers.first?.type == .srv)
        #expect(r.answers.first?.data == "10 20 5060 example.com")
    }

    // MARK: - Malformed / adversarial — must fail gracefully

    @Test func tooShortHeaderThrows() {
        #expect(throws: DNSError.truncatedMessage) { try DNSMessage.decode([0x12, 0x34]) }
        #expect(throws: DNSError.self) { try DNSMessage.decode([]) }
    }

    @Test func answerCountLiesAboutData() {
        // Header claims 1 answer, but nothing follows the question.
        let bytes = hex("123481800001000100000000076578616d706c6503636f6d0000010001")
        #expect(throws: DNSError.self) { try DNSMessage.decode(bytes) }
    }

    @Test func selfReferentialPointerDoesNotLoop() {
        // 12-byte header, then question name = C0 0C (a pointer to offset 12 — itself).
        let bytes = hex("123481800001000000000000c00c00010001")
        #expect(throws: DNSError.pointerLoop) { try DNSMessage.decode(bytes) }
    }

    @Test func mutualPointerLoopDoesNotHang() {
        // name@12 = C0 0E (->14); @14 = C0 0C (->12). Mutual loop.
        let bytes = hex("123481800001000000000000c00ec00c00010001")
        #expect(throws: DNSError.self) { try DNSMessage.decode(bytes) }
    }

    @Test func labelLengthPastBufferThrows() {
        // A label claims length 0x10 with far fewer bytes remaining.
        let bytes = hex("123481800001000000000000" + "10ffffff")
        #expect(throws: DNSError.self) { try DNSMessage.decode(bytes) }
    }

    @Test func bogusRDLengthThrows() {
        // Valid question, answer with rdlength 0xFFFF but no data.
        let bytes = hex("123481800001000100000000076578616d706c6503636f6d0000010001c00c0001000100000001ffff")
        #expect(throws: DNSError.badRDLength) { try DNSMessage.decode(bytes) }
    }
}
