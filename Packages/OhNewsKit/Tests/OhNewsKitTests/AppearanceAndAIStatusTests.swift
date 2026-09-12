// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("AIConfigurationStatus")
struct AIConfigurationStatusTests {
    @Test("关闭 AI 时不提示，也不发请求")
    func disabled() {
        let status = AIConfigurationStatus.evaluate(
            isEnabled: false,
            hasEndpoint: true,
            hasSummaryModel: true,
            requiresKey: true,
            keyState: .present
        )
        #expect(status == .disabled)
        #expect(status.canRequest == false)
        #expect(status.explanation == nil)
    }

    @Test("地址或模型缺失算配置不完整")
    func incomplete() {
        #expect(
            AIConfigurationStatus.evaluate(
                isEnabled: true,
                hasEndpoint: false,
                hasSummaryModel: true,
                requiresKey: true,
                keyState: .present
            ) == .incomplete
        )
        #expect(
            AIConfigurationStatus.evaluate(
                isEnabled: true,
                hasEndpoint: true,
                hasSummaryModel: false,
                requiresKey: true,
                keyState: .present
            ) == .incomplete
        )
    }

    @Test("本地服务不需要密钥即可就绪")
    func localServiceNeedsNoKey() {
        let status = AIConfigurationStatus.evaluate(
            isEnabled: true,
            hasEndpoint: true,
            hasSummaryModel: true,
            requiresKey: false,
            keyState: .missing
        )
        #expect(status == .ready)
        #expect(status.canRequest)
    }

    /// 这是用户实际遇到的那一类误报：密钥存在、只是当前签名读不到，
    /// 界面却提示「请设置 API Key」。
    @Test("密钥读不到与没有密钥是两种状态")
    func distinguishesUnreadableFromMissing() {
        let missing = AIConfigurationStatus.evaluate(
            isEnabled: true,
            hasEndpoint: true,
            hasSummaryModel: true,
            requiresKey: true,
            keyState: .missing
        )
        let unreadable = AIConfigurationStatus.evaluate(
            isEnabled: true,
            hasEndpoint: true,
            hasSummaryModel: true,
            requiresKey: true,
            keyState: .unreadable("钥匙串拒绝了本次读取。")
        )

        #expect(missing == .keyMissing)
        #expect(unreadable == .keyUnreadable("钥匙串拒绝了本次读取。"))
        #expect(missing != unreadable)
        #expect(missing.canRequest == false)
        #expect(unreadable.canRequest == false)
    }

    @Test("配置齐全且密钥可读时才是就绪")
    func ready() {
        let status = AIConfigurationStatus.evaluate(
            isEnabled: true,
            hasEndpoint: true,
            hasSummaryModel: true,
            requiresKey: true,
            keyState: .present
        )
        #expect(status == .ready)
        #expect(status.canRequest)
        #expect(status.explanation == nil)
    }

    @Test("需要提示的状态都有解释文案")
    func configurableStatesExplainThemselves() {
        let statuses: [AIConfigurationStatus] = [
            .incomplete,
            .keyMissing,
            .keyUnreadable("原因"),
        ]
        for status in statuses {
            #expect(status.explanation?.isEmpty == false)
        }
    }
}

@Suite("AppAppearance")
struct AppAppearanceTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "OhNewsKitTests.AppAppearance.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("默认跟随系统")
    func defaultsToSystem() throws {
        let preferences = AppearancePreferences(defaults: try makeDefaults())
        #expect(preferences.appearance == .system)
    }

    @Test("保存后能读回")
    func roundTrips() throws {
        var preferences = AppearancePreferences(defaults: try makeDefaults())

        preferences.appearance = .dark
        #expect(preferences.appearance == .dark)

        preferences.appearance = .light
        #expect(preferences.appearance == .light)
    }

    @Test("一键切换在深浅之间来回")
    func toggleSwitchesBetweenLightAndDark() {
        #expect(AppAppearance.light.toggled == .dark)
        #expect(AppAppearance.dark.toggled == .light)
        // 从「跟随系统」出发时无从判断要切哪个方向，交给界面按当前实际外观决定。
        #expect(AppAppearance.system.toggled == .dark)
    }

    @Test("存了无法识别的值时回落跟随系统")
    func fallsBackForUnknownValue() throws {
        let defaults = try makeDefaults()
        defaults.set("sepia", forKey: "ui.appearance")

        #expect(AppearancePreferences(defaults: defaults).appearance == .system)
    }
}
