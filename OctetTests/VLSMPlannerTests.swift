//
//  VLSMPlannerTests.swift
//  Allocation order, sizing, and the overflow / doesn't-fit paths.
//

import Testing
@testable import Octet

struct VLSMPlannerTests {

    // MARK: - Sizing

    @Test func prefixFittingMatchesUsableCounts() {
        #expect(VLSMPlanner.prefixFitting(hosts: 1) == 32)
        #expect(VLSMPlanner.prefixFitting(hosts: 2) == 31)
        #expect(VLSMPlanner.prefixFitting(hosts: 3) == 29)   // /30 holds 2, too few
        #expect(VLSMPlanner.prefixFitting(hosts: 6) == 29)
        #expect(VLSMPlanner.prefixFitting(hosts: 7) == 28)
        #expect(VLSMPlanner.prefixFitting(hosts: 30) == 27)
        #expect(VLSMPlanner.prefixFitting(hosts: 50) == 26)
        #expect(VLSMPlanner.prefixFitting(hosts: 254) == 24)
    }

    // MARK: - Allocation order

    @Test func packsLargestFirstSequentially() throws {
        // Deliberately shuffled input; output must be largest-first and packed.
        let reqs = [
            VLSMPlanner.Requirement(name: "Uplink", hosts: 2),
            VLSMPlanner.Requirement(name: "Engineering", hosts: 50),
            VLSMPlanner.Requirement(name: "Ops", hosts: 10),
            VLSMPlanner.Requirement(name: "Sales", hosts: 25),
        ]
        let plan = try VLSMPlanner.plan(baseCIDR: "10.0.0.0/24", requirements: reqs)

        #expect(plan.allocations.map(\.name) == ["Engineering", "Sales", "Ops", "Uplink"])
        #expect(plan.allocations.map(\.cidr) == [
            "10.0.0.0/26",     // 50 hosts → /26
            "10.0.0.64/27",    // 25 hosts → /27
            "10.0.0.96/28",    // 10 hosts → /28
            "10.0.0.112/31",   // 2 hosts  → /31
        ])
        // 64 + 32 + 16 + 2 used out of 256.
        #expect(plan.usedAddresses == 114)
        #expect(plan.freeAddresses == 142)
        #expect(plan.totalAddresses == 256)
    }

    @Test func equalSizesKeepInputOrder() throws {
        let reqs = [
            VLSMPlanner.Requirement(name: "A", hosts: 10),
            VLSMPlanner.Requirement(name: "B", hosts: 10),
        ]
        let plan = try VLSMPlanner.plan(baseCIDR: "10.0.0.0/24", requirements: reqs)
        #expect(plan.allocations.map(\.name) == ["A", "B"])
    }

    @Test func allocationCarriesMaskRangeAndSlack() throws {
        let plan = try VLSMPlanner.plan(
            baseCIDR: "10.0.0.0/24",
            requirements: [VLSMPlanner.Requirement(name: "Engineering", hosts: 50)]
        )
        let a = try #require(plan.allocations.first)
        #expect(a.mask == "255.255.255.192")
        #expect(a.firstUsable == "10.0.0.1")
        #expect(a.lastUsable == "10.0.0.62")
        #expect(a.broadcast == "10.0.0.63")
        #expect(a.usableHosts == 62)
        #expect(a.slack == 12)            // 62 usable − 50 requested
    }

    // MARK: - Failure paths

    @Test func requirementBiggerThanBaseThrows() {
        #expect(throws: VLSMPlanner.PlanError.requirementTooLarge(name: "Big", hosts: 20, basePrefix: 29)) {
            try VLSMPlanner.plan(
                baseCIDR: "192.168.1.0/29",
                requirements: [VLSMPlanner.Requirement(name: "Big", hosts: 20)]
            )
        }
    }

    @Test func runningOutOfSpaceThrowsCapacityExceeded() {
        // /28 = 16 addresses. Two /29s fill it; the third can't be placed.
        let reqs = [
            VLSMPlanner.Requirement(name: "a", hosts: 6),
            VLSMPlanner.Requirement(name: "b", hosts: 6),
            VLSMPlanner.Requirement(name: "c", hosts: 6),
        ]
        #expect(throws: VLSMPlanner.PlanError.capacityExceeded(name: "c")) {
            try VLSMPlanner.plan(baseCIDR: "10.0.0.0/28", requirements: reqs)
        }
    }

    @Test func emptyAndInvalidRequirements() {
        #expect(throws: VLSMPlanner.PlanError.emptyRequirements) {
            try VLSMPlanner.plan(baseCIDR: "10.0.0.0/24", requirements: [])
        }
        #expect(throws: VLSMPlanner.PlanError.invalidHostCount(name: "Zero")) {
            try VLSMPlanner.plan(
                baseCIDR: "10.0.0.0/24",
                requirements: [VLSMPlanner.Requirement(name: "Zero", hosts: 0)]
            )
        }
    }
}
