//
//  HTTPInspector.swift
//  Walk a URL's HTTP redirect chain and inspect the final response's headers,
//  surfacing the security-relevant ones. Contacts ONLY the URL the user typed
//  (and whatever it redirects to — each hop is shown).
//
//  We follow redirects MANUALLY rather than letting URLSession do it: a stateless
//  delegate vetoes automatic redirects, and we resolve each Location ourselves.
//  That way every hop is recorded — including cross-scheme (http→https) and
//  cross-host jumps — instead of only seeing the final landing page.
//

import Foundation
import Observation

// File-scope Sendable value types so the nonisolated fetch can build and return
// them across the actor boundary.

struct HTTPHop: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: String
    let status: Int
    let statusText: String
    let location: String?    // the Location header that pointed onward
}

struct HTTPSecurityHeader: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let value: String?       // nil ⇒ header absent
    var isPresent: Bool { value != nil }
}

struct HTTPReport: Sendable {
    let finalURL: String
    let method: String       // "HEAD" or "GET" — what produced the final response
    let status: Int
    let statusText: String
    let server: String?
    let chain: [HTTPHop]
    let security: [HTTPSecurityHeader]
    let headers: [HeaderField]
}

/// A single response header (kept as an ordered list — header names can repeat).
struct HeaderField: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let value: String
}

enum HTTPInspectorError: LocalizedError, Equatable {
    case invalidURL
    case notHTTP
    case tooManyRedirects

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "That isn’t a valid http/https URL."
        case .notHTTP:          return "The server didn’t return an HTTP response."
        case .tooManyRedirects: return "Too many redirects — stopped to avoid a loop."
        }
    }
}

/// Pure classification of which security headers are present. No I/O, so it's
/// unit-tested directly.
enum HTTPSecurity {
    /// (lowercased lookup key, display label) for the headers we surface.
    nonisolated static let surfaced: [(key: String, label: String)] = [
        ("strict-transport-security", "HSTS (Strict-Transport-Security)"),
        ("content-security-policy", "Content-Security-Policy"),
        ("x-frame-options", "X-Frame-Options"),
        ("x-content-type-options", "X-Content-Type-Options"),
        ("referrer-policy", "Referrer-Policy"),
        ("permissions-policy", "Permissions-Policy"),
    ]

    nonisolated static func securityHeaders(from headers: [String: String]) -> [HTTPSecurityHeader] {
        let ci = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        return surfaced.map { HTTPSecurityHeader(name: $0.label, value: ci[$0.key]) }
    }

    nonisolated static func server(from headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == "server" }?.value
    }
}

@MainActor
@Observable
final class HTTPInspector {

    enum State {
        case idle
        case loading
        case done(HTTPReport)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    // MARK: - Control

    func inspect(urlString: String) {
        cancel()
        let input = urlString.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { state = .idle; return }
        state = .loading

        task = Task { @MainActor [weak self] in
            do {
                let report = try await Self.fetch(urlString: input)
                guard !Task.isCancelled else { return }
                self?.state = .done(report)
            } catch is CancellationError {
                // left as-is
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed((error as? LocalizedError)?.errorDescription
                                      ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Fetch (isolation-free)

    nonisolated static func fetch(urlString: String, maxRedirects: Int = 10) async throws -> HTTPReport {
        // Be forgiving: default to https:// when the user omits the scheme.
        var normalized = urlString
        if !normalized.lowercased().contains("://") { normalized = "https://" + normalized }
        guard let start = URL(string: normalized),
              let scheme = start.scheme?.lowercased(), scheme == "http" || scheme == "https",
              start.host != nil else {
            throw HTTPInspectorError.invalidURL
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let delegate = NoAutoRedirect()

        var current = start
        var chain: [HTTPHop] = []

        for _ in 0...maxRedirects {
            try Task.checkCancellation()
            let (method, http) = try await request(current, session: session, delegate: delegate)
            let statusText = HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized

            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current)?.absoluteURL {
                chain.append(HTTPHop(url: current.absoluteString,
                                     status: http.statusCode,
                                     statusText: statusText,
                                     location: location))
                current = next
                continue
            }

            return buildReport(finalURL: current, method: method, http: http,
                               statusText: statusText, chain: chain)
        }
        throw HTTPInspectorError.tooManyRedirects
    }

    /// HEAD first; fall back to GET if the server rejects HEAD.
    nonisolated private static func request(_ url: URL,
                                            session: URLSession,
                                            delegate: URLSessionTaskDelegate) async throws -> (method: String, http: HTTPURLResponse) {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        if let (_, response) = try? await session.data(for: head, delegate: delegate),
           let http = response as? HTTPURLResponse,
           http.statusCode != 405, http.statusCode != 501 {
            return ("HEAD", http)
        }

        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        let (_, response) = try await session.data(for: get, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw HTTPInspectorError.notHTTP }
        return ("GET", http)
    }

    nonisolated private static func buildReport(finalURL: URL,
                                                method: String,
                                                http: HTTPURLResponse,
                                                statusText: String,
                                                chain: [HTTPHop]) -> HTTPReport {
        let fields: [HeaderField] = http.allHeaderFields.compactMap { key, value in
            guard let name = key as? String else { return nil }
            return HeaderField(name: name, value: "\(value)")
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }

        let plain = Dictionary(fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })

        return HTTPReport(
            finalURL: finalURL.absoluteString,
            method: method,
            status: http.statusCode,
            statusText: statusText,
            server: HTTPSecurity.server(from: plain),
            chain: chain,
            security: HTTPSecurity.securityHeaders(from: plain),
            headers: fields
        )
    }
}

/// Stateless delegate that vetoes URLSession's automatic redirect following so
/// the inspector can record and resolve every hop itself. No mutable state, so
/// no synchronization needed.
private final class NoAutoRedirect: NSObject, URLSessionTaskDelegate {
    // Completion-handler (not async) variant on purpose: the @objc async thunk
    // for this delegate method currently crashes SILGen under the project's
    // experimental concurrency flags. Passing nil declines the redirect.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
