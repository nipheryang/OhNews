// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 正文解读偏好。
public struct InsightPreferences {
    private static let enabledKey = "ai.insightEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 打开正文后自动生成解读。
    ///
    /// 默认开：默认关的话这个功能等于不存在，用户根本不会发现它。但它每打开一篇
    /// 都会调一次 AI，所以给一个关闭的开关；关掉后在正文里仍可手动生成。
    public var isEnabled: Bool {
        get {
            // 不能直接用 `bool(forKey:)`：键不存在时它返回 false，会把「没设置过」
            // 误判成「用户关掉了」。
            guard defaults.object(forKey: Self.enabledKey) != nil else { return true }
            return defaults.bool(forKey: Self.enabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
        }
    }
}
