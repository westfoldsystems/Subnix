//
//  LANmDNS.swift
//  Joins friendly Bonjour/mDNS instance names to LAN IPs for the LAN Scanner.
//
//  NWBrowser only yields service *names* (e.g. "Living Room Apple TV"), not
//  addresses — so for each advertised instance we open a short NWConnection to
//  its endpoint and read the resolved IPv4 off `currentPath.remoteEndpoint`,
//  then drop the connection. Time-boxed and fully on-LAN (multicast DNS); like
//  BonjourScanner, nothing leaves the device.
//
//  The service types browsed here are BonjourScanner.defaultServiceTypes, which
//  are already declared in Info.plist under NSBonjourServices — required or iOS
//  silently returns nothing.
//

import Foundation
import Network
import os

enum LANmDNS {

    /// Browse the default service types for `budget` seconds and resolve each
    /// advertised instance to its IPv4. Returns `[ip: friendly name]`.
    nonisolated static func resolve(serviceTypes: [String] = BonjourScanner.defaultServiceTypes,
                                    budget: TimeInterval = 4) async -> [String: String] {
        let queue = DispatchQueue(label: "app.subnix.mdns.join", qos: .userInitiated)
        let names = OSAllocatedUnfairLock(initialState: [String: String]())   // ip -> name
        let started = OSAllocatedUnfairLock(initialState: Set<String>())      // instances already resolving
        let conns = OSAllocatedUnfairLock(initialState: [NWConnection]())     // resolver connections (spawned on `queue`)
        var browsers: [NWBrowser] = []                                        // set up synchronously below only

        for type in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .service(serviceName, _, _, _) = result.endpoint else { continue }
                    // Resolve each distinct instance only once, no matter how many
                    // times the result set changes.
                    guard started.withLock({ $0.insert(serviceName).inserted }) else { continue }

                    let tcp = NWParameters.tcp
                    tcp.includePeerToPeer = true
                    let conn = NWConnection(to: result.endpoint, using: tcp)
                    conns.withLock { $0.append(conn) }

                    conn.stateUpdateHandler = { [weak conn] state in
                        switch state {
                        case .ready:
                            if let ip = Self.ipv4(from: conn?.currentPath?.remoteEndpoint) {
                                names.withLock { if $0[ip] == nil { $0[ip] = serviceName } }
                            }
                            conn?.cancel()
                        case .failed, .cancelled:
                            conn?.cancel()
                        default:
                            break
                        }
                    }
                    conn.start(queue: queue)
                }
            }

            browser.start(queue: queue)
            browsers.append(browser)
        }

        try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))

        for browser in browsers { browser.cancel() }
        conns.withLock { list in
            for conn in list { conn.cancel() }
            list.removeAll()
        }
        return names.withLock { $0 }
    }

    /// Dotted IPv4 from a resolved connection endpoint (ignores IPv6). Pure.
    nonisolated static func ipv4(from endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _)? = endpoint else { return nil }
        if case let .ipv4(addr) = host {
            let s = "\(addr)"
            return s.split(separator: "%").first.map(String.init)   // strip any %zone
        }
        return nil
    }
}
