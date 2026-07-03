//
//  OctetAppIntents.swift
//  Exposes a few tools to Shortcuts and Siri as App Intents. Each reuses a pure
//  engine — no UI — and runs in the background, returning a spoken/visible
//  result. Privacy is unchanged: What's My IP and Subnet are fully offline;
//  Host Reachable makes a single TCP connect to the host you name.
//

import AppIntents
import Foundation

// MARK: - What's My IP

struct WhatsMyIPIntent: AppIntent {
    static let title: LocalizedStringResource = "What’s My IP"
    static let description = IntentDescription("Return this device’s local IPv4 address(es).")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let addresses = LocalInterfaces.all()
            .filter { $0.isIPv4 && !$0.isLoopback && !$0.isLinkLocal }
            .map(\.address)
        let primary = addresses.first ?? "none"
        let spoken = addresses.isEmpty
            ? "No active local IPv4 address."
            : "Your local IP is \(addresses.joined(separator: ", "))."
        return .result(value: primary, dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - Subnet lookup

struct SubnetLookupIntent: AppIntent {
    static let title: LocalizedStringResource = "Subnet Calculator"
    static let description = IntentDescription("Compute network, broadcast, mask, and usable-host count for a CIDR.")

    @Parameter(title: "CIDR", inputOptions: String.IntentInputOptions(capitalizationType: .none, autocorrect: false))
    var cidr: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let r = try SubnetCalculator.calculate(cidr)
            let spoken = "\(r.cidr): network \(r.networkAddress), broadcast \(r.broadcastAddress ?? "none"), "
                       + "\(r.usableHostCount) usable hosts, mask \(r.subnetMask)."
            return .result(value: r.cidr, dialog: IntentDialog(stringLiteral: spoken))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "That isn’t a valid CIDR."
            return .result(value: "", dialog: IntentDialog(stringLiteral: message))
        }
    }
}

// MARK: - Host reachable (TCP)

struct HostReachableIntent: AppIntent {
    static let title: LocalizedStringResource = "Is Host Reachable"
    static let description = IntentDescription("Check whether a host answers a TCP connection on a port.")

    @Parameter(title: "Host", inputOptions: String.IntentInputOptions(capitalizationType: .none, autocorrect: false))
    var host: String

    @Parameter(title: "Port", default: 443)
    var port: Int

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let result = await PortScanner.probe(host: host, port: port, timeout: 2)
        // .open or .closed both mean the host answered (pattern-match avoids the
        // main-actor-isolated Equatable conformance in this nonisolated context).
        let reachable: Bool = switch result.status {
        case .open, .closed: true
        default:             false
        }
        let rtt = result.latency.map { String(format: " in %.0f ms", $0 * 1000) } ?? ""
        let spoken = reachable
            ? "\(host) port \(port) is reachable\(rtt)."
            : "\(host) port \(port) is not reachable."
        return .result(value: reachable, dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - Shortcuts / Siri phrases

struct OctetAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsMyIPIntent(),
            phrases: [
                "What’s my IP in \(.applicationName)",
                "Show my local IP with \(.applicationName)",
            ],
            shortTitle: "What’s My IP",
            systemImageName: "globe"
        )
        AppShortcut(
            intent: SubnetLookupIntent(),
            phrases: [
                "Subnet calculator in \(.applicationName)",
                "Calculate a subnet with \(.applicationName)",
            ],
            shortTitle: "Subnet Calculator",
            systemImageName: "function"
        )
        AppShortcut(
            intent: HostReachableIntent(),
            phrases: [
                "Check a host with \(.applicationName)",
                "Is a host reachable in \(.applicationName)",
            ],
            shortTitle: "Is Host Reachable",
            systemImageName: "wave.3.right"
        )
    }
}
