//
//  HTTPSecurityTests.swift
//  Security-header classification (pure). The network walk in HTTPInspector is
//  exercised by hand against live hosts, not here.
//

import Testing
@testable import Octet

struct HTTPSecurityTests {

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
