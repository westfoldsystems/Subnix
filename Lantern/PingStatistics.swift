//
//  PingStatistics.swift
//  Pure summary math over a sequence of ping outcomes (rtt or loss). No I/O,
//  so it's unit-tested independently of the ICMP socket work.
//

import Foundation

struct PingStatistics: Equatable, Sendable {
    let transmitted: Int
    let received: Int
    let lossPercent: Double
    // Round-trip times in milliseconds; nil when nothing came back.
    let minMS: Double?
    let avgMS: Double?
    let maxMS: Double?
    let stddevMS: Double?

    /// `rtts` is one entry per probe sent: the round-trip time in seconds, or
    /// nil for a lost/timed-out probe.
    static func compute(rtts: [TimeInterval?]) -> PingStatistics {
        let transmitted = rtts.count
        let samples = rtts.compactMap { $0 }.map { $0 * 1000 }   // → ms
        let received = samples.count
        let loss = transmitted == 0 ? 0 : Double(transmitted - received) / Double(transmitted) * 100

        guard !samples.isEmpty else {
            return PingStatistics(transmitted: transmitted, received: 0, lossPercent: loss,
                                  minMS: nil, avgMS: nil, maxMS: nil, stddevMS: nil)
        }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(samples.count)
        return PingStatistics(transmitted: transmitted, received: received, lossPercent: loss,
                              minMS: samples.min(), avgMS: avg, maxMS: samples.max(),
                              stddevMS: variance.squareRoot())
    }
}
