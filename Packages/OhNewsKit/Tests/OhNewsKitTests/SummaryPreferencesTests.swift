// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing

@testable import OhNewsKit

@Suite("SummaryPreferences")
struct SummaryPreferencesTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "OhNewsKitTests.SummaryPreferences.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("默认只生成最前面若干条")
    func defaultsToLeadingItems() throws {
        let preferences = SummaryPreferences(defaults: try makeDefaults())
        #expect(preferences.scope == .leadingItems)
    }

    @Test("保存后能读回所选范围")
    func roundTripsScope() throws {
        var preferences = SummaryPreferences(defaults: try makeDefaults())

        preferences.scope = .allItems
        #expect(preferences.scope == .allItems)

        preferences.scope = .manual
        #expect(preferences.scope == .manual)
    }

    @Test("存了无法识别的值时回落到默认档")
    func fallsBackForUnknownValue() throws {
        let defaults = try makeDefaults()
        defaults.set("something-else", forKey: "ai.summaryScope")
        let preferences = SummaryPreferences(defaults: defaults)

        #expect(preferences.scope == .leadingItems)
    }

    @Test("三种范围都有展示名")
    func everyScopeHasDisplayName() {
        for scope in SummaryGenerationScope.allCases {
            #expect(scope.displayName.isEmpty == false)
        }
    }
}
