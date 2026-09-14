// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 阅读器的显示偏好。
///
/// 只影响正文，不动列表：列表的密度是版式的一部分，而正文字号是每个人
/// 的阅读条件，两者不该绑在一起调。
public struct ReaderPreferences {
    private static let scaleKey = "reader.fontScale"

    /// 字号的可调范围与默认值。
    ///
    /// 下限保住「一屏能看多少」，上限到两倍再往上单行就太短了。
    public static let minimumScale = 0.85
    public static let maximumScale = 1.8
    public static let defaultScale = 1.0

    /// 正文的基准字号（CSS 像素），与 `reader.css` 里 `body` 的取值一致。
    public static let baseFontSize = 17.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 正文字号的倍数。
    ///
    /// 没存过时返回默认值而不写回：默认值改了（比如以后放宽范围），
    /// 没动过设置的人应当跟着变。
    public var fontScale: Double {
        get {
            guard defaults.object(forKey: Self.scaleKey) != nil else {
                return Self.defaultScale
            }
            return Self.clamped(defaults.double(forKey: Self.scaleKey))
        }
        set {
            defaults.set(Self.clamped(newValue), forKey: Self.scaleKey)
        }
    }

    /// 把越界与非数值挡在外面。存进去过一次坏值，之后每次读数都会受影响。
    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScale }
        return min(max(value, minimumScale), maximumScale)
    }

    /// 正文实际使用的字号，直接写进 CSS。
    public static func fontSize(for scale: Double) -> Double {
        baseFontSize * clamped(scale)
    }
}
