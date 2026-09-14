// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 回收站的自动清理档位。
///
/// 给「手动清空」留一档，是因为有人就是不想让程序替他删东西；默认给 30 天，
/// 既不至于一删就没了，也不会让回收站无限涨下去。
public enum TrashRetention: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sevenDays: "7 天后自动清空"
        case .thirtyDays: "30 天后自动清空"
        case .manual: "手动清空"
        }
    }

    /// 多少秒之后算过期。`manual` 不过期。
    public var expiry: TimeInterval? {
        switch self {
        case .sevenDays: 7 * 24 * 60 * 60
        case .thirtyDays: 30 * 24 * 60 * 60
        case .manual: nil
        }
    }

    /// 没设置过时用哪一档。
    public static let fallback: TrashRetention = .thirtyDays
}

/// 回收站的偏好。
public struct TrashPreferences {
    private static let retentionKey = "trash.retention"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 保留档位。
    ///
    /// 没存过时返回默认值而不写回：默认值以后改了，没动过设置的人应当跟着变。
    /// 存进去的字符串认不出来时（手改过偏好、或以后删掉某一档）也回落到默认值。
    public var retention: TrashRetention {
        get {
            guard let raw = defaults.string(forKey: Self.retentionKey),
                  let value = TrashRetention(rawValue: raw)
            else { return TrashRetention.fallback }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.retentionKey)
        }
    }

    /// 早于这个时刻的条目该被清掉；手动清空时返回 nil。
    public func cutoff(now: Date = Date()) -> Date? {
        guard let expiry = retention.expiry else { return nil }
        return now.addingTimeInterval(-expiry)
    }
}
