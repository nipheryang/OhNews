// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("SummaryPreferences")
struct SummaryPreferencesTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "OhNewsKitTests.SummaryPreferences.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("默认生成全部条目")
    func defaultsToAllItems() throws {
        let preferences = SummaryPreferences(defaults: try makeDefaults())
        #expect(preferences.scope == .allItems)
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

        #expect(preferences.scope == .allItems)
    }

    @Test("默认档就是全量")
    func fallbackIsAllItems() {
        #expect(SummaryGenerationScope.fallback == .allItems)
    }

    @Test("三种范围都有展示名")
    func everyScopeHasDisplayName() {
        for scope in SummaryGenerationScope.allCases {
            #expect(scope.displayName.isEmpty == false)
        }
    }
}
