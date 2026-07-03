//
//  OUIStore.swift
//  Owns the live MAC-vendor table for the app: it starts from the previously
//  downloaded copy (Application Support) if present, otherwise the bundled
//  IEEE table, and offers an OPT-IN refresh from the IEEE registry.
//
//  Privacy: the bundled table is fully offline and used by default. The refresh
//  is the ONLY outside connection this feature makes, and only when the user
//  taps "Update" — mirroring the What's My IP opt-in.
//

import Foundation
import Observation

enum OUIUpdateError: LocalizedError, Equatable {
    case badResponse
    case tooFewRows(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:       return "The registry didn’t return the expected data."
        case .tooFewRows(let n): return "Only \(n) entries parsed — keeping the current database."
        }
    }
}

@MainActor
@Observable
final class OUIStore {

    /// Shared app-wide table (OUIView + LAN Scanner read this).
    static let shared = OUIStore()

    enum Source: Equatable {
        case bundled
        case updated(Date)
    }
    enum State: Equatable {
        case idle
        case updating
        case failed(String)
    }

    private(set) var lookup: OUILookup
    private(set) var source: Source
    private(set) var state: State = .idle

    var count: Int { lookup.count }
    var isEmpty: Bool { lookup.isEmpty }
    var isUpdating: Bool { state == .updating }

    private var task: Task<Void, Never>?

    init() {
        // Prefer a previously downloaded copy; fall back to the bundled table.
        if let url = Self.cacheURL,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let parsed = OUILookup.parse(text)
            if !parsed.isEmpty {
                lookup = parsed
                let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
                source = .updated(modified ?? Date())
                return
            }
        }
        lookup = OUILookup.bundled()
        source = .bundled
    }

    func vendor(for mac: MACAddress) -> String? { lookup.vendor(for: mac) }

    // MARK: - Opt-in update

    func update() {
        guard state != .updating else { return }
        state = .updating
        task = Task { @MainActor [weak self] in
            do {
                let tsv = try await Self.fetchAndConvert()
                guard !Task.isCancelled else { return }
                let parsed = OUILookup.parse(tsv)
                guard parsed.count >= 10_000 else { throw OUIUpdateError.tooFewRows(parsed.count) }
                try Self.writeCache(tsv)
                guard let self else { return }
                self.lookup = parsed
                self.source = .updated(Date())
                self.state = .idle
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .updating { state = .idle }
    }

    // MARK: - Networking + cache (isolation-free)

    nonisolated static let sourceURL = URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!

    nonisolated static func fetchAndConvert() async throws -> String {
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OUIUpdateError.badResponse
        }
        return OUICSV.toTSV(String(decoding: data, as: UTF8.self))
    }

    /// `<AppSupport>/oui-mal-cache.tsv`, or nil if the directory can't be resolved.
    nonisolated static var cacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("oui-mal-cache.tsv")
    }

    nonisolated static func writeCache(_ tsv: String) throws {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try tsv.write(to: dir.appendingPathComponent("oui-mal-cache.tsv"), atomically: true, encoding: .utf8)
    }
}
