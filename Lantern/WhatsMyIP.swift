//
//  WhatsMyIP.swift
//  Local interface addresses (offline, automatic) plus an OPT-IN public-IP
//  reflection. The public lookup is the project's only deliberate external call:
//  it never runs automatically, IPv4 and IPv6 are independent taps, and the UI
//  names the provider being contacted. Endpoints are documented in
//  SupportingFiles/Info-plist-setup.md.
//

import Foundation
import Observation

enum IPFamily: String, Sendable {
    case v4 = "IPv4"
    case v6 = "IPv6"
}

/// Pure parsing of the reflection responses — unit-tested without the network.
enum PublicIPParser {
    /// Cloudflare's `/cdn-cgi/trace` is `key=value` lines; pull `ip=`.
    nonisolated static func parseTrace(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let value = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// ipify with `?format=json` returns `{"ip":"…"}`.
    nonisolated static func parseIPify(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = object["ip"] as? String, !ip.isEmpty else {
            return nil
        }
        return ip
    }
}

private struct ReflectionEndpoint: Sendable {
    let url: URL
    let provider: String
    let isTrace: Bool
}

enum WhatsMyIPError: LocalizedError, Equatable {
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "Couldn’t determine public address: \(why)"
        }
    }
}

@MainActor
@Observable
final class WhatsMyIP {

    enum Lookup: Equatable {
        case idle
        case loading
        case value(ip: String, provider: String)
        case failed(String)
    }

    private(set) var interfaces: [NetInterface] = []
    private(set) var v4: Lookup = .idle
    private(set) var v6: Lookup = .idle

    private var tasks: [IPFamily: Task<Void, Never>] = [:]

    /// Best-guess primary outbound address: first global IPv4, else global IPv6.
    /// Purely a heuristic over the local list — no routing-table probe.
    var primaryAddress: String? {
        interfaces.first { $0.isIPv4 && !$0.isLoopback && !$0.isLinkLocal }?.address
            ?? interfaces.first { !$0.isIPv4 && !$0.isLoopback && !$0.isLinkLocal }?.address
    }

    // MARK: - Local (offline, automatic)

    func loadInterfaces() {
        interfaces = LocalInterfaces.all()
    }

    // MARK: - Public (opt-in, per family)

    func lookup(for family: IPFamily) -> Lookup {
        family == .v4 ? v4 : v6
    }

    func revealPublic(_ family: IPFamily) {
        tasks[family]?.cancel()
        setLookup(.loading, for: family)
        tasks[family] = Task { @MainActor [weak self] in
            do {
                let (ip, provider) = try await Self.fetchPublicIP(family)
                guard !Task.isCancelled else { return }
                self?.setLookup(.value(ip: ip, provider: provider), for: family)
            } catch {
                guard !Task.isCancelled else { return }
                self?.setLookup(.failed((error as? LocalizedError)?.errorDescription
                                        ?? error.localizedDescription), for: family)
            }
        }
    }

    private func setLookup(_ value: Lookup, for family: IPFamily) {
        if family == .v4 { v4 = value } else { v6 = value }
    }

    // MARK: - Reflection (isolation-free)

    /// Provider + fallback per family. IP literals pin the address family without
    /// any low-level socket fiddling: 1.1.1.1 / the v6 literal are valid SANs on
    /// Cloudflare's cert, and api/api6.ipify.org are family-specific hostnames.
    nonisolated private static func endpoints(_ family: IPFamily) -> [ReflectionEndpoint] {
        switch family {
        case .v4:
            return [
                ReflectionEndpoint(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, provider: "Cloudflare (1.1.1.1)", isTrace: true),
                ReflectionEndpoint(url: URL(string: "https://api.ipify.org?format=json")!, provider: "ipify (api.ipify.org)", isTrace: false),
            ]
        case .v6:
            return [
                ReflectionEndpoint(url: URL(string: "https://[2606:4700:4700::1111]/cdn-cgi/trace")!, provider: "Cloudflare (2606:4700:4700::1111)", isTrace: true),
                ReflectionEndpoint(url: URL(string: "https://api6.ipify.org?format=json")!, provider: "ipify (api6.ipify.org)", isTrace: false),
            ]
        }
    }

    nonisolated static func fetchPublicIP(_ family: IPFamily) async throws -> (ip: String, provider: String) {
        let session = URLSession(configuration: .ephemeral)
        var lastReason = "no endpoint reachable"

        for endpoint in endpoints(family) {
            do {
                var request = URLRequest(url: endpoint.url)
                request.timeoutInterval = 8
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    lastReason = "unexpected response"
                    continue
                }
                let ip = endpoint.isTrace
                    ? PublicIPParser.parseTrace(String(decoding: data, as: UTF8.self))
                    : PublicIPParser.parseIPify(data)
                if let ip { return (ip, endpoint.provider) }
                lastReason = "couldn’t parse response"
            } catch {
                lastReason = error.localizedDescription
            }
        }
        throw WhatsMyIPError.unavailable(lastReason)
    }
}
