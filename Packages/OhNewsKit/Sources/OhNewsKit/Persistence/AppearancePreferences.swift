// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 应用外观。
public enum AppAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// 一键切换的目标：在浅色与深色之间来回，不再回到「跟随系统」。
    public var toggled: AppAppearance {
        switch self {
        case .light: .dark
        case .dark: .light
        case .system: .dark
        }
    }
}

/// 外观偏好。
public struct AppearancePreferences {
    private static let key = "ui.appearance"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 存了无法识别的值时回落到跟随系统。
    public var appearance: AppAppearance {
        get {
            guard let raw = defaults.string(forKey: Self.key),
                  let value = AppAppearance(rawValue: raw)
            else { return .system }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
