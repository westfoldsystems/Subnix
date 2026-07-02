//
//  VLSMPlanner.swift
//  Variable-Length Subnet Mask planner. Pure, offline, unit-tested.
//
//  Given a base block and a set of named host requirements, lay out subnets
//  largest-first, each in the smallest block that fits, packed sequentially.
//  Because we allocate biggest-first and every block is a power of two, the
//  running pointer stays naturally aligned to each next (smaller-or-equal)
//  block — the classic property that makes sequential VLSM allocation correct
//  without re-aligning. Address math is borrowed from SubnetCalculator so the
//  two tools can never disagree.
//

import Foundation

struct VLSMPlanner {

    /// One named ask: "Sales needs 50 hosts."
    struct Requirement: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var hosts: Int
    }

    /// One laid-out subnet.
    struct Allocation: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let requestedHosts: Int

        let network: String
        let prefix: Int
        let mask: String
        let firstUsable: String?
        let lastUsable: String?
        let broadcast: String?       // nil for /31, /32
        let usableHosts: UInt64

        var cidr: String { "\(network)/\(prefix)" }
        /// Usable addresses left over after the request — the cost of rounding
        /// up to a power of two.
        var slack: UInt64 { usableHosts - UInt64(requestedHosts) }
    }

    enum PlanError: LocalizedError, Equatable {
        case emptyRequirements
        case invalidHostCount(name: String)
        /// A single ask is bigger than the whole base block, so it can never fit.
        case requirementTooLarge(name: String, hosts: Int, basePrefix: Int)
        /// We ran out of room partway through packing.
        case capacityExceeded(name: String)

        var errorDescription: String? {
            switch self {
            case .emptyRequirements:
                return "Add at least one host requirement to plan."
            case .invalidHostCount(let name):
                return "“\(name)” needs a host count of 1 or more."
            case .requirementTooLarge(let name, let hosts, let basePrefix):
                return "“\(name)” (\(hosts) hosts) is larger than the base /\(basePrefix) block."
            case .capacityExceeded(let name):
                return "Ran out of space before “\(name)” could be placed."
            }
        }
    }

    struct Plan: Equatable {
        let base: String                 // canonical "network/prefix"
        let allocations: [Allocation]
        let totalAddresses: UInt64
        let usedAddresses: UInt64
        var freeAddresses: UInt64 { totalAddresses - usedAddresses }
    }

    // MARK: - Planning

    static func plan(baseCIDR: String, requirements: [Requirement]) throws -> Plan {
        guard !requirements.isEmpty else { throw PlanError.emptyRequirements }
        for req in requirements where req.hosts < 1 {
            throw PlanError.invalidHostCount(name: req.name)
        }

        // Canonicalise the base block via the shared engine.
        let baseResult = try SubnetCalculator.calculate(baseCIDR)
        let basePrefix = baseResult.prefix
        let baseNetwork = try SubnetCalculator.parseIPv4(baseResult.networkAddress)
        let baseSize = UInt64(1) << UInt64(32 - basePrefix)
        let baseEnd = UInt64(baseNetwork) + baseSize        // one-past-the-end

        // Largest first; keep input order for equal sizes (stable).
        let ordered = requirements.enumerated().sorted { lhs, rhs in
            lhs.element.hosts != rhs.element.hosts
                ? lhs.element.hosts > rhs.element.hosts
                : lhs.offset < rhs.offset
        }.map(\.element)

        var pointer = UInt64(baseNetwork)
        var allocations: [Allocation] = []

        for req in ordered {
            let prefix = prefixFitting(hosts: req.hosts)
            // A block longer than the base would be larger than the base itself.
            guard prefix >= basePrefix else {
                throw PlanError.requirementTooLarge(name: req.name,
                                                    hosts: req.hosts,
                                                    basePrefix: basePrefix)
            }
            let blockSize = UInt64(1) << UInt64(32 - prefix)
            guard pointer + blockSize <= baseEnd else {
                throw PlanError.capacityExceeded(name: req.name)
            }

            let netStr = SubnetCalculator.format(UInt32(pointer))
            let r = try SubnetCalculator.calculate("\(netStr)/\(prefix)")
            allocations.append(Allocation(
                name: req.name,
                requestedHosts: req.hosts,
                network: r.networkAddress,
                prefix: r.prefix,
                mask: r.subnetMask,
                firstUsable: r.firstUsableHost,
                lastUsable: r.lastUsableHost,
                broadcast: r.broadcastAddress,
                usableHosts: r.usableHostCount
            ))
            pointer += blockSize
        }

        let used = pointer - UInt64(baseNetwork)
        return Plan(base: baseResult.cidr,
                    allocations: allocations,
                    totalAddresses: baseSize,
                    usedAddresses: used)
    }

    // MARK: - Sizing

    /// The longest prefix (smallest block) whose usable-host capacity covers
    /// `hosts`. Mirrors SubnetCalculator's usable-count rules: /32 holds 1,
    /// /31 holds 2 (RFC 3021), everything else is 2^h − 2.
    static func prefixFitting(hosts: Int) -> Int {
        if hosts <= 1 { return 32 }
        if hosts == 2 { return 31 }
        var prefix = 30
        while prefix > 0 {
            let usable = (UInt64(1) << UInt64(32 - prefix)) - 2
            if usable >= UInt64(hosts) { return prefix }
            prefix -= 1
        }
        return 0
    }
}
