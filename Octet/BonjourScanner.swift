//
//  BonjourScanner.swift
//  Discovers Bonjour/mDNS services on the local network via NWBrowser.
//
//  Privacy: this talks ONLY to the local multicast-DNS group. No server, no
//  account, nothing leaves the device. The browse stays on the LAN.
//
//  iOS gotcha baked in: every service type you browse here MUST also be listed
//  in Info.plist under `NSBonjourServices`, AND the app needs
//  `NSLocalNetworkUsageDescription`, or iOS silently returns nothing on first
//  run. See SupportingFiles/Info-plist-setup.md.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class BonjourScanner {

    struct DiscoveredService: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let type: String
        let domain: String
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        case stopped
        case failed(String)
    }

    /// A curated starting set for a home / SMB / lab network. Add to taste —
    /// and mirror every addition in Info.plist `NSBonjourServices`.
    nonisolated static let defaultServiceTypes: [String] = [
        "_http._tcp",
        "_https._tcp",
        "_ssh._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_ipp._tcp",
        "_printer._tcp",
        "_airplay._tcp",
        "_raop._tcp",          // AirPlay audio
        "_googlecast._tcp",
        "_homekit._tcp",
        "_hap._tcp",           // HomeKit Accessory Protocol
        "_rfb._tcp",           // VNC / screen sharing
        "_device-info._tcp",
    ]

    private(set) var services: [DiscoveredService] = []
    private(set) var state: ScanState = .idle

    private var browsers: [NWBrowser] = []
    private let queue = DispatchQueue(label: "systems.westfold.octet.bonjour",
                                      qos: .userInitiated)

    // MARK: - Control

    func start(serviceTypes: [String] = BonjourScanner.defaultServiceTypes) {
        stop()
        services.removeAll()
        state = .scanning

        for type in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true

            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: params)

            browser.stateUpdateHandler = { [weak self] newState in
                guard case let .failed(error) = newState else { return }
                Task { @MainActor [weak self] in
                    self?.state = .failed(error.localizedDescription)
                }
            }

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { Self.service(from: $0, type: type) }
                Task { @MainActor [weak self] in
                    self?.merge(found)
                }
            }

            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    func stop() {
        for browser in browsers { browser.cancel() }
        browsers.removeAll()
        if state == .scanning { state = .stopped }
    }

    // MARK: - Internals

    private func merge(_ found: [DiscoveredService]) {
        for svc in found where !services.contains(where: {
            $0.name == svc.name && $0.type == svc.type && $0.domain == svc.domain
        }) {
            services.append(svc)
        }
        services.sort { ($0.type, $0.name) < ($1.type, $1.name) }
    }

    /// Bonjour endpoints arrive as `.service(name:type:domain:interface:)`.
    /// Pure and isolation-free: called from `browseResultsChangedHandler`, which
    /// runs on `queue` (a background DispatchQueue), so it must be nonisolated.
    nonisolated private static func service(from result: NWBrowser.Result,
                                            type: String) -> DiscoveredService? {
        if case let .service(name, _, domain, _) = result.endpoint {
            return DiscoveredService(name: name, type: type, domain: domain)
        }
        return nil
    }
}
