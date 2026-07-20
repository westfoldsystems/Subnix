//
//  VLSMView.swift
//  Thin SwiftUI shell over VLSMPlanner. Edit a base block and a list of named
//  host requirements; the plan recomputes live. All output is copyable
//  ResultRows.
//

import SwiftUI

struct VLSMView: View {
    @State private var baseCIDR = "10.0.0.0/24"
    @State private var requirements: [VLSMPlanner.Requirement] = [
        .init(name: "Engineering", hosts: 50),
        .init(name: "Sales", hosts: 25),
        .init(name: "Ops", hosts: 10),
        .init(name: "Uplink", hosts: 2),
    ]
    @State private var plan: VLSMPlanner.Plan?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Base block") {
                TextField("e.g. 10.0.0.0/16", text: $baseCIDR)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }

            Section("Host requirements") {
                ForEach($requirements) { $req in
                    HStack {
                        TextField("Name", text: $req.name)
                        Spacer(minLength: 12)
                        TextField("Hosts", value: $req.hosts, format: .number)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                .onDelete { requirements.remove(atOffsets: $0) }

                Button("Add subnet", systemImage: "plus") {
                    requirements.append(.init(name: "Subnet \(requirements.count + 1)", hosts: 10))
                }
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.statusTimeout)
                }
            }

            if let plan {
                Section("Summary") {
                    ResultRow("Base block", plan.base)
                    ResultRow("Subnets", plan.allocations.count.formatted())
                    ResultRow("Used addresses", plan.usedAddresses.formatted())
                    ResultRow("Free addresses", plan.freeAddresses.formatted())
                }

                ForEach(plan.allocations) { alloc in
                    Section(alloc.name) {
                        ResultRow("CIDR", alloc.cidr)
                        ResultRow("Subnet mask", alloc.mask)
                        if let first = alloc.firstUsable, let last = alloc.lastUsable {
                            ResultRow("Usable range", "\(first) – \(last)")
                        }
                        if let broadcast = alloc.broadcast {
                            ResultRow("Broadcast", broadcast)
                        }
                        ResultRow("Usable hosts", alloc.usableHosts.formatted())
                        ResultRow("Requested", alloc.requestedHosts.formatted())
                        ResultRow("Slack", alloc.slack.formatted())
                    }
                }
            }
        }
        .formStyle(.grouped)
        .subnixScreen()
        .onChange(of: baseCIDR) { _, _ in recompute() }
        .onChange(of: requirements) { _, _ in recompute() }
        .onAppear(perform: recompute)
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }

    private func recompute() {
        do {
            plan = try VLSMPlanner.plan(baseCIDR: baseCIDR, requirements: requirements)
            errorText = nil
        } catch {
            plan = nil
            errorText = (error as? LocalizedError)?.errorDescription
                      ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { VLSMView() }
}
