//
//  WakeOnLANTests.swift
//  Pure magic-packet construction and target selection. The UDP send is I/O and
//  validated by hand (macOS / real LAN) — not here.
//

import Testing
@testable import Subnix

struct WakeOnLANTests {

    @Test func magicPacketShape() throws {
        let mac = try MACAddress.parse("a4:2b:1c:00:11:22")
        let pkt = WakeOnLAN.magicPacket(for: mac.bytes)

        #expect(pkt.count == 102)                              // 6 + 16 × 6
        #expect(pkt.prefix(6).allSatisfy { $0 == 0xFF })       // sync stream
        for rep in 0..<16 {                                    // MAC × 16
            let start = 6 + rep * 6
            #expect(Array(pkt[start..<start + 6]) == mac.bytes)
        }
    }

    @Test func subnetBroadcastIsDot255() {
        #expect(WakeOnLAN.subnetBroadcast(for: "192.168.0.151") == "192.168.0.255")
        #expect(WakeOnLAN.subnetBroadcast(for: "10.4.7.9") == "10.4.7.255")
        #expect(WakeOnLAN.subnetBroadcast(for: nil) == nil)
        #expect(WakeOnLAN.subnetBroadcast(for: "not.an.ip") == nil)
    }

    @Test func targetsUseOverrideOrDefaults() {
        // Explicit override wins and is used verbatim.
        #expect(WakeOnLAN.targets(override: "10.0.0.255", primaryIPv4: "10.0.0.5") == ["10.0.0.255"])
        // Otherwise: directed broadcast + global broadcast.
        #expect(WakeOnLAN.targets(override: "", primaryIPv4: "192.168.1.20") == ["192.168.1.255", "255.255.255.255"])
        // No known address → global only.
        #expect(WakeOnLAN.targets(override: "  ", primaryIPv4: nil) == ["255.255.255.255"])
    }
}
