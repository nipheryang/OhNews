// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 版本检查偏好。
public struct UpdatePreferences {
    /// 两次自动检查之间的最小间隔。
    ///
    /// 应用可能一天被打开很多次，每次都请求接口既无必要也不礼貌。
    public static let interval: TimeInterval = 24 * 60 * 60

    private static let lastCheckKey = "update.lastCheckAt"
    private static let dismissedKey = "update.dismissedTag"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 上次检查的时间。没有记录时返回 nil。
    public var lastCheckAt: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    /// 用户已经关掉提示的那个版本号。
    ///
    /// 关掉后这一版不再提示，直到出现更新的版本——否则用户每次启动都要
    /// 再关一遍同一件事。
    public var dismissedTag: String? {
        get { defaults.string(forKey: Self.dismissedKey) }
        set { defaults.set(newValue, forKey: Self.dismissedKey) }
    }

    /// 现在是否该自动检查。
    public func shouldCheck(now: Date = Date()) -> Bool {
        guard let last = lastCheckAt else { return true }
        return now.timeIntervalSince(last) >= Self.interval
    }
}
