import Foundation

/// 列表展示相关的偏好。
///
/// 「一次抓多少条」与「列表最多保留多少条」用同一个值：分成两个设置会让
/// 用户遇到「抓了 100 条却只看到 30 条」这种不好解释的状态。
public struct ListPreferences {
    /// 允许的条数档位。
    public static let allowedLimits = [30, 50, 100]
    public static let defaultLimit = 30

    private static let limitKey = "ui.listLimit"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 列表条数上限。存了非法值时回落到默认档，避免手工改坏偏好后列表直接空白。
    public var listLimit: Int {
        get {
            let stored = defaults.integer(forKey: Self.limitKey)
            return Self.allowedLimits.contains(stored) ? stored : Self.defaultLimit
        }
        set {
            guard Self.allowedLimits.contains(newValue) else { return }
            defaults.set(newValue, forKey: Self.limitKey)
        }
    }
}
