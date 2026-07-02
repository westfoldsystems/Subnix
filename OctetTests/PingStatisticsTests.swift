//
//  PingStatisticsTests.swift
//  Pure summary math. The ICMP socket work is validated by hand (macOS) — the
//  simulator/sandbox can't be trusted for it.
//

import Testing
import Foundation
@testable import Octet

struct PingStatisticsTests {

    @Test func computesMinAvgMaxAndLoss() {
        // 4 sent, 1 lost; rtts in seconds.
        let s = PingStatistics.compute(rtts: [0.010, 0.020, nil, 0.030])
        #expect(s.transmitted == 4)
        #expect(s.received == 3)
        #expect(s.lossPercent == 25)
        #expect(s.minMS == 10)
        #expect(s.maxMS == 30)
        #expect(s.avgMS == 20)
        // population stddev of {10,20,30} = sqrt(200/3) ≈ 8.165
        #expect((s.stddevMS! - 8.1649).magnitude < 0.001)
    }

    @Test func allLost() {
        let s = PingStatistics.compute(rtts: [nil, nil, nil])
        #expect(s.transmitted == 3)
        #expect(s.received == 0)
        #expect(s.lossPercent == 100)
        #expect(s.minMS == nil)
        #expect(s.avgMS == nil)
        #expect(s.stddevMS == nil)
    }

    @Test func emptyAndSingle() {
        let empty = PingStatistics.compute(rtts: [])
        #expect(empty.transmitted == 0)
        #expect(empty.lossPercent == 0)

        let one = PingStatistics.compute(rtts: [0.012])
        #expect(one.received == 1)
        #expect(one.minMS == 12)
        #expect(one.avgMS == 12)
        #expect(one.maxMS == 12)
        #expect(one.stddevMS == 0)
    }
}
