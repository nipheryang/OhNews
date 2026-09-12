// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 相对时间的显示。
///
/// 界面文案全部是中文，日期也必须跟着中文。之前直接用 `Date.formatted`，
/// 它跟随系统语言，于是中文界面里会冒出「3 DAYS AGO」——在等宽大写的眉标里
/// 尤其刺眼。
enum RelativeTime {
    /// 应用尚无本地化（界面字符串全部硬编码中文），所以这里固定中文区域。
    private static let locale = Locale(identifier: "zh_Hans_CN")

    static func text(for date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }
}
