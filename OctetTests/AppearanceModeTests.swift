//
//  AppearanceModeTests.swift
//  The pure mode → ColorScheme mapping and raw-value round trip.
//

import Testing
import SwiftUI
@testable import Octet

struct AppearanceModeTests {

    @Test func colorSchemeMapping() {
        #expect(AppearanceMode.system.colorScheme == nil)   // defer to OS
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func rawValueRoundTrip() {
        for mode in AppearanceMode.allCases {
            #expect(AppearanceMode(rawValue: mode.rawValue) == mode)
        }
        #expect(AppearanceMode(rawValue: "garbage") == nil)
        #expect(AppearanceMode.allCases.count == 3)
    }
}
