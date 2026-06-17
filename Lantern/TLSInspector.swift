//
//  TLSInspector.swift
//  Open a TLS handshake to host:port (default 443), grab the certificate chain
//  the server presents, and summarize it. We accept the cert in the verify block
//  regardless of trust — the point is to inspect, including expired/untrusted
//  certs — and never complete a real data connection.
//
//  Contacts ONLY the host:port the user typed. Concurrency mirrors PortScanner:
//  the verify block runs on a background queue, captures raw DER (Sendable
//  [[UInt8]]), and we parse on the main actor with X509Certificate.
//

import Foundation
import Network
import Security
import Observation
import os

struct CertSummary: Identifiable, Sendable {
    let id = UUID()
    let subjectCN: String?
    let issuerCN: String?
    let serialHex: String?
    let notBefore: Date?
    let notAfter: Date?
    let signatureAlgorithm: String?
    let keyType: String?
    let keyBits: Int?
    let sans: [CertSAN]
}

struct TLSReport: Sendable {
    let host: String
    let port: Int
    let leaf: CertSummary?
    let chain: [CertSummary]
}

enum TLSInspectorError: LocalizedError, Equatable {
    case invalidHost
    case noCertificates
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:             return "Enter a valid host and port."
        case .noCertificates:          return "The server presented no certificates."
        case .connectionFailed(let m): return "Couldn’t complete the TLS handshake: \(m)"
        }
    }
}

@MainActor
@Observable
final class TLSInspector {

    enum State {
        case idle
        case loading
        case done(TLSReport)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    // MARK: - Control

    func inspect(host rawHost: String, port: Int = 443) {
        cancel()
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let port16 = UInt16(exactly: port) else { state = .idle; return }
        state = .loading

        task = Task { @MainActor [weak self] in
            do {
                let ders = try await Self.fetchCertChain(host: host, port: port16, timeout: 7)
                guard !Task.isCancelled else { return }
                self?.state = .done(Self.report(host: host, port: Int(port16), ders: ders))
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

    // MARK: - Report building (main actor: parse DER + read key via Security)

    static func report(host: String, port: Int, ders: [[UInt8]]) -> TLSReport {
        let chain = ders.map(summarize)
        return TLSReport(host: host, port: port, leaf: chain.first, chain: chain)
    }

    static func summarize(_ der: [UInt8]) -> CertSummary {
        let x = X509Certificate.parse(der: der)
        let (keyType, keyBits) = keyInfo(der: der)
        return CertSummary(subjectCN: x?.subjectCN, issuerCN: x?.issuerCN, serialHex: x?.serialHex,
                           notBefore: x?.notBefore, notAfter: x?.notAfter,
                           signatureAlgorithm: x?.signatureAlgorithm,
                           keyType: keyType, keyBits: keyBits, sans: x?.sans ?? [])
    }

    /// Public-key type/size via the cross-platform Security APIs (DER SPKI math
    /// is fiddly; these are reliable on both iOS and macOS).
    static func keyInfo(der: [UInt8]) -> (type: String?, bits: Int?) {
        guard let cert = SecCertificateCreateWithData(nil, Data(der) as CFData),
              let key = SecCertificateCopyKey(cert),
              let attrs = SecKeyCopyAttributes(key) as? [CFString: Any] else {
            return (nil, nil)
        }
        let bits = attrs[kSecAttrKeySizeInBits] as? Int
        let rawType = attrs[kSecAttrKeyType] as? String
        let type: String?
        if rawType == (kSecAttrKeyTypeRSA as String) {
            type = "RSA"
        } else if rawType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            type = "EC"
        } else {
            type = rawType
        }
        return (type, bits)
    }

    // MARK: - Handshake (isolation-free)

    nonisolated static func fetchCertChain(host: String,
                                           port: UInt16,
                                           timeout: TimeInterval) async throws -> [[UInt8]] {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TLSInspectorError.invalidHost }

        let queue = DispatchQueue(label: "systems.westfold.lantern.tls")
        // The verify block stashes the presented chain here; the state handler
        // reads it once the handshake is ready. Both run on `queue`.
        let captured = OSAllocatedUnfairLock(initialState: [[UInt8]]())

        // CRITICAL: the verify block must be installed BEFORE NWParameters is
        // built from these options — set afterwards it is silently ignored and
        // the handshake completes without ever calling us.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            let chain = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate]) ?? []
            let ders = chain.map { [UInt8](SecCertificateCopyData($0) as Data) }
            captured.withLock { $0 = ders }
            complete(true)   // accept regardless — inspection, not validation
        }, queue)

        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let resumed = OSAllocatedUnfairLock(initialState: false)

        enum Outcome { case certs([[UInt8]]); case failed(String) }

        let outcome: Outcome = await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
            @Sendable func finish(_ outcome: Outcome) {
                let isFirst = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if isFirst { cont.resume(returning: outcome) }
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:              finish(.certs(captured.withLock { $0 }))
                case .failed(let error):  finish(.failed(error.localizedDescription))
                case .waiting(let error): finish(.failed(error.localizedDescription))
                default:                  break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) { finish(.failed("timed out")) }
            connection.start(queue: queue)
        }

        connection.cancel()

        switch outcome {
        case .certs(let ders):
            guard !ders.isEmpty else { throw TLSInspectorError.noCertificates }
            return ders
        case .failed(let message):
            throw TLSInspectorError.connectionFailed(message)
        }
    }
}
