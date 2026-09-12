// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing

@testable import OhNewsKit

@Suite("ListPreferences")
struct ListPreferencesTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "OhNewsKitTests.ListPreferences.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("没有存过时使用默认档")
    func usesDefaultWhenNothingStored() throws {
        let preferences = ListPreferences(defaults: try makeDefaults())
        #expect(preferences.listLimit == 30)
    }

    @Test("保存后能读回所选档位")
    func roundTripsSelectedLimit() throws {
        var preferences = ListPreferences(defaults: try makeDefaults())

        preferences.listLimit = 100

        #expect(preferences.listLimit == 100)
    }

    @Test("只接受允许的档位")
    func ignoresUnsupportedValue() throws {
        var preferences = ListPreferences(defaults: try makeDefaults())

        preferences.listLimit = 42

        #expect(preferences.listLimit == 30)
    }

    @Test("存了非法值时回落到默认档")
    func fallsBackWhenStoredValueIsInvalid() throws {
        let defaults = try makeDefaults()
        defaults.set(7, forKey: "ui.listLimit")
        let preferences = ListPreferences(defaults: defaults)

        #expect(preferences.listLimit == 30)
    }
}
