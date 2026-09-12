// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 把评论树渲染成阅读器可用的 HTML。
///
/// 折叠用 HTML 原生的 `<details>`：阅读器刻意关闭了 JavaScript，而 `<details>`
/// 折叠一条会连带折叠整棵子树，正好是讨论区需要的行为，不必为此引入脚本。
///
/// 时间格式化由调用方注入，包内不依赖界面层的本地化实现。
public enum CommentTreeBuilder {
    /// 渲染参数。
    public struct Options: Sendable {
        /// 最多渲染多少条（含各层子评论）。热门帖的树可能上千条，必须有上限。
        public var maxComments: Int
        /// 缩进在哪一层封顶，更深的层级不再继续内缩，避免正文被挤成窄柱。
        public var maxIndentLevel: Int
        /// 顶层评论是否默认展开。
        public var expandTopLevel: Bool
        /// 时间格式化。默认给出一个不依赖语言环境的简短格式。
        public var formatDate: @Sendable (Date) -> String

        public init(
            maxComments: Int = 400,
            maxIndentLevel: Int = 5,
            expandTopLevel: Bool = true,
            formatDate: @escaping @Sendable (Date) -> String = CommentTreeBuilder.defaultDateFormat
        ) {
            self.maxComments = maxComments
            self.maxIndentLevel = maxIndentLevel
            self.expandTopLevel = expandTopLevel
            self.formatDate = formatDate
        }

        public static let `default` = Options()
    }

    /// 渲染结果。
    public struct Result: Equatable, Sendable {
        /// 讨论区主体的 HTML（不含外层容器，由调用方决定放在哪里）。
        public let html: String
        /// 实际渲染的条数。
        public let renderedCount: Int
        /// 因超出上限而未渲染的条数。
        public let omittedCount: Int

        public init(html: String, renderedCount: Int, omittedCount: Int) {
            self.html = html
            self.renderedCount = renderedCount
            self.omittedCount = omittedCount
        }
    }

    public static func build(
        _ comments: StoryComments,
        options: Options = .default
    ) -> Result {
        var context = Context(options: options)
        let html = context.render(comments.topLevel, depth: 1)
        let omitted = max(0, comments.totalCount - context.rendered)

        return Result(
            html: html,
            renderedCount: context.rendered,
            omittedCount: omitted
        )
    }

    // MARK: - 渲染

    private struct Context {
        let options: Options
        var rendered = 0
        /// 楼层号，深度优先递增，与 HN 网页版的口径一致。
        var floor = 0

        mutating func render(_ nodes: [CommentNode], depth: Int) -> String {
            guard nodes.isEmpty == false, rendered < options.maxComments else { return "" }

            var items: [String] = []
            for node in nodes {
                guard rendered < options.maxComments else { break }
                rendered += 1
                floor += 1
                // 楼层号必须先取下来：接下来渲染子树会继续递增 floor。
                items.append(renderNode(node, floor: floor, depth: depth))
            }
            guard items.isEmpty == false else { return "" }

            let level = min(depth, options.maxIndentLevel + 1)
            // 用 `div` 而不是 `ol`/`li`：讨论区会被整段送去做翻译切分，而切分器
            // 用非贪婪正则配对 `<li>…</li>`；嵌套的列表会让 `</li>` 提前闭合、
            // 后续配对连锁错位，绝大多数段落根本切不出来（表现为多数评论翻不了，
            // 少数又被当成一整块连楼层号一起翻）。扁平的 `div` 不会参与那个配对。
            return "<div class=\"comment-list\" data-depth=\"\(level)\">\(items.joined())</div>"
        }

        mutating func renderNode(_ node: CommentNode, floor floorNumber: Int, depth: Int) -> String {
            // 先渲染子树，让它先占用渲染额度（深度优先顺序）。
            let children = render(node.children, depth: depth + 1)

            let author = CommentTreeBuilder.escape(node.author ?? "")
            let time = node.createdAt.map { options.formatDate($0) } ?? ""
            // 顶层默认展开，深层默认折叠，避免一屏塞不下。
            let isOpen = depth == 1 && options.expandTopLevel

            return """
            <div class="comment"><details\(isOpen ? " open" : "")>\
            <summary class="comment-head">\
            <span class="comment-floor">\(floorNumber)</span>\
            <span class="comment-author">\(author)</span>\
            <span class="comment-time">\(time)</span>\
            </summary>\
            <div class="comment-body">\(bodyHTML(for: node))</div>\
            \(children)\
            </details></div>
            """
        }

        /// 已删除的评论正文为空，但它的回复可能还在，所以保留节点位置而不是整条跳过。
        private func bodyHTML(for node: CommentNode) -> String {
            guard let text = node.text, text.isEmpty == false else {
                return "<p class=\"comment-deleted\">[已删除]</p>"
            }
            return CommentTreeBuilder.normalizeParagraphs(HTMLSanitizer.sanitize(text))
        }
    }

    // MARK: - 工具

    /// 把 HN 的评论正文规范成配对的 `<p>…</p>`。
    ///
    /// HN 的评论以裸文本开头，段与段之间只用不带闭合的 `<p>` 分隔；
    /// 而翻译切分器靠 `<p>…</p>` 成对来识别段落，不规范化的话绝大多数段落
    /// 根本切不出来——表现就是「评论大部分没被翻译」。
    ///
    /// 段落里含代码块等块级元素时保持原样，它们本来也不参与翻译。
    static func normalizeParagraphs(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return html }
        guard trimmed.contains("<p>") || containsBlockLevelTag(trimmed) == false else { return trimmed }

        var out: [String] = []
        for part in trimmed.components(separatedBy: "<p>") {
            let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }
            if containsBlockLevelTag(text) {
                out.append(text)
            } else {
                out.append("<p>\(text)</p>")
            }
        }
        return out.isEmpty ? trimmed : out.joined()
    }

    /// 段内含这些标签时不能再用 `<p>` 包裹（块级元素套在段落里不合法）。
    private static func containsBlockLevelTag(_ html: String) -> Bool {
        let lower = html.lowercased()
        return ["<pre", "<table", "<figure", "<ul", "<ol", "<blockquote", "<h2", "<h3", "<h4"]
            .contains { lower.contains($0) }
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 默认时间格式：不依赖语言环境，保证输出稳定（界面层会注入中文相对时间）。
    public static let defaultDateFormat: @Sendable (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
