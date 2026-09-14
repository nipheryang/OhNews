// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("ReaderPreferences")
struct ReaderPreferencesTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "OhNewsKitTests.ReaderPreferences.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("默认字号是一倍")
    func defaultsToOne() throws {
        let preferences = ReaderPreferences(defaults: try makeDefaults())
        #expect(preferences.fontScale == 1.0)
    }

    @Test("默认值不写回偏好")
    func defaultIsNotPersisted() throws {
        let defaults = try makeDefaults()
        _ = ReaderPreferences(defaults: defaults).fontScale

        // 没动过设置的人不该被钉在当前默认值上：将来改了默认值应当跟着变。
        #expect(defaults.object(forKey: "reader.fontScale") == nil)
    }

    @Test("保存后能读回")
    func roundTripsScale() throws {
        var preferences = ReaderPreferences(defaults: try makeDefaults())
        preferences.fontScale = 1.4
        #expect(preferences.fontScale == 1.4)
    }

    @Test("超出范围的一律钳制")
    func clampsOutOfRange() throws {
        var preferences = ReaderPreferences(defaults: try makeDefaults())

        preferences.fontScale = 99
        #expect(preferences.fontScale == ReaderPreferences.maximumScale)

        preferences.fontScale = 0.01
        #expect(preferences.fontScale == ReaderPreferences.minimumScale)
    }

    @Test("存进坏值也能读出可用结果")
    func survivesCorruptValue() throws {
        let defaults = try makeDefaults()
        // 手改偏好文件或旧版本写坏都会留下这种值。
        defaults.set(Double.nan, forKey: "reader.fontScale")

        #expect(ReaderPreferences(defaults: defaults).fontScale == ReaderPreferences.defaultScale)
    }

    @Test("字号换算成 CSS 像素")
    func convertsToFontSize() {
        #expect(ReaderPreferences.fontSize(for: 1.0) == 17.0)
        #expect(ReaderPreferences.fontSize(for: 1.5) == 25.5)
        // 越界的倍数同样钳制，不能算出荒唐的字号。
        #expect(ReaderPreferences.fontSize(for: 10) == 17.0 * ReaderPreferences.maximumScale)
    }
}
