// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 抽取结果的清理。
///
/// 虽然在阅读视图里关闭了 JavaScript，但把第三方页面的脚本、表单、事件属性带进应用
/// 没有任何好处，因此在数据边界上就剥掉。
public enum HTMLSanitizer {
    /// 整体移除的元素。
    private static let removedElements = ["script", "iframe", "object", "embed", "form", "noscript"]

    /// 需要单独移除的空元素（自闭合写法）。
    private static let removedVoidElements = ["meta", "base", "link"]

    public static func sanitize(_ html: String) -> String {
        var result = html

        for name in removedElements {
            result = result.replacingOccurrences(
                of: "<\(name)\\b[^>]*>[\\s\\S]*?</\(name)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: "<\(name)\\b[^>]*/?>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        for name in removedVoidElements {
            result = result.replacingOccurrences(
                of: "<\(name)\\b[^>]*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 事件属性：onclick、onerror 等
        result = result.replacingOccurrences(
            of: "\\son[a-z]+\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "\\son[a-z]+\\s*=\\s*'[^']*'",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "\\son[a-z]+\\s*=\\s*[^\\s>]+",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // javascript: 链接只处理 href / src，不碰正文里出现的同名普通文本
        result = result.replacingOccurrences(
            of: "(href|src)\\s*=\\s*(\"|')\\s*javascript:[^\"']*(\"|')",
            with: "$1=\"#\"",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }
}
