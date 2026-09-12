// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// AI 摘要的生成范围。
public enum SummaryGenerationScope: String, CaseIterable, Codable, Sendable {
    /// 只为列表最前面若干条自动生成，成本可预期。
    case leadingItems
    /// 为列表中全部条目自动生成。
    case allItems
    /// 不自动生成，完全由用户在右键菜单里手动触发。
    case manual

    public var displayName: String {
        switch self {
        case .leadingItems: "只生成最前面若干条"
        case .allItems: "生成全部条目"
        case .manual: "不自动生成"
        }
    }
}

/// 摘要生成偏好。
///
/// 自动生成的条数直接影响 AI 调用成本：HN 一个榜单 30 条，全量生成是前 12 条的
/// 两倍多，订阅多了之后差距更明显。因此把选择权交给用户，而不是替他决定。
public struct SummaryPreferences {
    /// `.leadingItems` 时自动生成的条数。
    public static let automaticLimit = 12

    private static let scopeKey = "ai.summaryScope"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 存了无法识别的值时回落到默认档，避免手工改坏偏好后摘要完全不生成。
    public var scope: SummaryGenerationScope {
        get {
            guard let raw = defaults.string(forKey: Self.scopeKey),
                  let value = SummaryGenerationScope(rawValue: raw)
            else { return .leadingItems }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.scopeKey)
        }
    }
}
