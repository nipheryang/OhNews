// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 把正文 HTML 组装成一个完整的阅读文档。
///
/// 阅读视图用 `loadHTMLString` 呈现，所以这里要补上编码声明、`<base>`（让相对路径的图片
/// 能加载）以及排版样式。
public enum ReaderDocumentBuilder {
    public static func build(
        article: Article,
        style: String,
        discussionHTML: String? = nil
    ) -> String {
        build(
            html: article.html,
            style: style,
            baseURL: article.sourceURL,
            discussionHTML: discussionHTML
        )
    }

    /// - Parameter discussionHTML: 讨论区段落，已经包含标题与评论树；为 nil 时不渲染。
    /// - Parameter topInset: 正文顶部预留的高度。阅读器顶部浮着一块固定高度的面板时，
    ///   用它把正文推开，让内容从面板下边缘开始——滚动时文字就会从面板后面穿过。
    public static func build(
        html: String,
        style: String,
        baseURL: URL? = nil,
        discussionHTML: String? = nil,
        topInset: CGFloat = 0
    ) -> String {
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        """

        if let baseURL {
            head += "\n<base href=\"\(escapeAttribute(baseURL.absoluteString))\">"
        }

        head += "\n<style>\n\(style)\n</style>"

        if topInset > 0 {
            // 用 padding 而不是 margin：留白要算在 `body` 自己的高度里，
            // 否则最后一段容易滑不到面板下方。
            head += "\n<style>body { padding-top: \(Int(topInset))px !important; }</style>"
        }

        // 讨论区接在正文之后：读完正文接着看讨论，比另开面板更符合阅读顺序。
        let discussion = discussionHTML.map { "\n<section class=\"comments\">\n\($0)\n</section>" } ?? ""

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        \(head)
        </head>
        <body>
        <article>
        \(html)
        </article>\(discussion)
        </body>
        </html>
        """
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
