// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 抽取质量闸门。
///
/// Readability 在 JS 应用外壳页面（GitHub、X 这类）上会「成功」返回一大坨页面框架标记，
/// 而实际文字很少。实测 GitHub 仓库页：正文 HTML 115747 字符、其中文字只有 1919 字符；
/// 而正常文章的这个比例在 0.4 以上。这类结果直接渲染只会让用户看到无关内容，
/// 不如降级成「没有取到正文 + 浏览器打开」。
public enum ExtractionQuality {
    /// 低于这个 HTML 规模时不做比例判断，避免把本身就简短的页面误判掉。
    public static let minimumInspectionSize = 2000
    /// 文字 / 标记的最低比例。
    public static let minimumTextRatio = 0.04

    public static func isReadable(_ article: Article) -> Bool {
        guard article.textLength >= 0 else { return false }
        guard article.html.count >= minimumInspectionSize else { return true }
        guard article.textLength > 0 else { return false }
        let ratio = Double(article.textLength) / Double(article.html.count)
        return ratio >= minimumTextRatio
    }
}
