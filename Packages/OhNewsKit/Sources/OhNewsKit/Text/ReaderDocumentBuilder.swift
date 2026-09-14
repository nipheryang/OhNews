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
    /// - Parameter fontScale: 正文字号倍数。CSS 里除基准外的字号多用 `em`，
    ///   改这一处就能整体缩放；少数写死的 `rem` 不跟着变（它们只是注释时间这类小字）。
    public static func build(
        html: String,
        style: String,
        baseURL: URL? = nil,
        discussionHTML: String? = nil,
        fontScale: Double = 1.0
    ) -> String {
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        """

        if let baseURL {
            head += "\n<base href=\"\(escapeAttribute(baseURL.absoluteString))\">"
        }

        head += "\n<style>\n\(style)\n</style>"

        var overrides: [String] = []
        if fontScale != 1.0 {
            let size = ReaderPreferences.fontSize(for: fontScale)
            // 保留一位小数，整数时不要写成 `17.0px`。
            let text = size == size.rounded()
                ? String(Int(size))
                : String(format: "%.1f", size)
            overrides.append("font-size: \(text)px !important")
        }
        if overrides.isEmpty == false {
            head += "\n<style>body { \(overrides.joined(separator: "; ")); }</style>"
        }

        // 讨论区接在正文之后：读完正文接着看讨论，比另开面板更符合阅读顺序。
        let discussion = discussionHTML.map { "\n<section class=\"comments\">\n\($0)\n</section>" } ?? ""

        // 解读面板的位置先留一个空容器，内容随后由应用侧脚本填进去。
        // 不在这里直接拼面板，是因为解读总是晚于正文到位——拼进文档就等于重建
        // 整篇、丢掉阅读位置。留空容器，稍后原地填充即可。
        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        \(head)
        </head>
        <body>
        <div id="ohnews-insight"></div>
        <article>
        \(html)
        </article>\(discussion)
        </body>
        </html>
        """
    }

    /// 把一段纯文本放进 HTML 里。
    ///
    /// 解读的文字是模型给的，必须转义后再拼——它可能带着 `<`、`&`，
    /// 直接拼进去会破坏结构，甚至变成可执行的标记。
    public static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
