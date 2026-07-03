//
//  HTTPSecurityTests.swift
//  Security-header classification (pure). The network walk in HTTPInspector is
//  exercised by hand against live hosts, not here.
//

import Testing
import Foundation
@testable import Octet

struct HTTPSecurityTests {

    @Test func redirectTargetOnlyFollowsHTTP() throws {
        let base = try #require(URL(string: "https://example.com/a"))

        // http/https targets are allowed (absolute + relative + scheme-relative).
        #expect(HTTPInspector.safeRedirectTarget(location: "https://elsewhere.test/x", relativeTo: base)?.absoluteString == "https://elsewhere.test/x")
        #expect(HTTPInspector.safeRedirectTarget(location: "http://plain.test/", relativeTo: base)?.scheme == "http")
        #expect(HTTPInspector.safeRedirectTarget(location: "/b", relativeTo: base)?.absoluteString == "https://example.com/b")
        #expect(HTTPInspector.safeRedirectTarget(location: "//cdn.test/c", relativeTo: base)?.absoluteString == "https://cdn.test/c")

        // Anything off the web is refused.
        #expect(HTTPInspector.safeRedirectTarget(location: "file:///etc/passwd", relativeTo: base) == nil)
        #expect(HTTPInspector.safeRedirectTarget(location: "data:text/html,<b>x</b>", relativeTo: base) == nil)
        #expect(HTTPInspector.safeRedirectTarget(location: "javascript:alert(1)", relativeTo: base) == nil)
        #expect(HTTPInspector.safeRedirectTarget(location: "mailto:a@b.test", relativeTo: base) == nil)
        #expect(HTTPInspector.safeRedirectTarget(location: "ftp://host.test/f", relativeTo: base) == nil)
    }

    @Test func surfacesPresentAndAbsentHeaders() {
        // Mixed-case names to prove the lookup is case-insensitive.
        let headers = [
            "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
            "x-frame-options": "DENY",
            "Content-Security-Policy": "default-src 'self'",
            "Server": "nginx",
        ]
        let result = HTTPSecurity.securityHeaders(from: headers)
        let byName = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0) })

        let hsts = byName["HSTS (Strict-Transport-Security)"]
        #expect(hsts?.isPresent == true)
        #expect(hsts?.value == "max-age=63072000; includeSubDomains")

        #expect(byName["X-Frame-Options"]?.value == "DENY")
        #expect(byName["Content-Security-Policy"]?.isPresent == true)

        // Not supplied → flagged absent, not dropped.
        #expect(byName["Referrer-Policy"]?.isPresent == false)
        #expect(byName["Permissions-Policy"]?.value == nil)
        #expect(byName["X-Content-Type-Options"]?.isPresent == false)
    }

    @Test func alwaysReturnsEverySurfacedHeader() {
        let result = HTTPSecurity.securityHeaders(from: [:])
        #expect(result.count == HTTPSecurity.surfaced.count)
        #expect(result.allSatisfy { !$0.isPresent })
    }

    @Test func extractsServerCaseInsensitively() {
        #expect(HTTPSecurity.server(from: ["server": "Apache/2.4"]) == "Apache/2.4")
        #expect(HTTPSecurity.server(from: ["SERVER": "cloudflare"]) == "cloudflare")
        #expect(HTTPSecurity.server(from: ["X-Other": "x"]) == nil)
    }
}
