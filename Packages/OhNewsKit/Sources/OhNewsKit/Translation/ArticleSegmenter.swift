// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 把正文 HTML 切成可翻译的片段，并能按原结构拼回去。
///
/// 翻译是文本操作，而正文是 HTML——整篇直接交给模型会破坏标签结构。所以这里
/// 只挑结构简单、边界清晰的块级元素（段落、标题、列表项、引用）取出文字，
/// 其余（代码块、表格、图片、嵌套块）一律原样保留：翻译是锦上添花，
/// 不能冒把正文弄坏的风险。
///
/// 段内的链接换成 `[[n]]` 占位符，链接文字单独作为一个片段一起送翻，
/// 回来后再还原成 `<a>` 标签——否则译文里的链接会整片消失。
public enum ArticleSegmenter {
    /// 一个待翻译的文本片段。
    public struct Segment: Equatable, Sendable {
        public let index: Int
        /// 送翻文本，其中的 `[[n]]` 是链接占位符。
        public let text: String
        public let links: [LinkToken]

        public init(index: Int, text: String, links: [LinkToken]) {
            self.index = index
            self.text = text
            self.links = links
        }
    }

    /// 段内链接的信息。
    public struct LinkToken: Equatable, Sendable {
        /// 出现在译文里的占位标记，例如 `[[0]]`。
        public let marker: String
        public let href: String
        /// 链接文字的译文在片段数组中的位置。
        public let labelSegmentIndex: Int
    }

    /// 切分结果：模板 + 待翻片段。
    public struct Plan: Equatable, Sendable {
        /// 原文骨架，可翻译位置被替换成了唯一标记。
        public let template: String
        public let segments: [Segment]

        public var isEmpty: Bool { segments.isEmpty }

        public init(template: String, segments: [Segment]) {
            self.template = template
            self.segments = segments
        }
    }

    /// 只处理这几类块级元素。
    private static let blockPattern = try! NSRegularExpression(
        pattern: "<(p|h2|h3|h4|li|blockquote)(\\s[^>]*)?>(.*?)</\\1>",
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )

    private static let codeBlockPattern = try! NSRegularExpression(
        pattern: "<pre[^>]*>.*?</pre>",
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )

    private static let linkPattern = try! NSRegularExpression(
        pattern: "<a\\s[^>]*href\\s*=\\s*\"([^\"]*)\"[^>]*>(.*?)</a>",
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )

    /// 内层出现这些标签就说明这个块不是叶子，交给更内层处理。
    private static let nestedTags = [
        "<p", "<li", "<blockquote", "<h2", "<h3", "<h4", "<pre", "<table", "<figure", "<ul", "<ol"
    ]

    // MARK: - 切分

    public static func plan(_ html: String) -> Plan {
        guard html.isEmpty == false else { return Plan(template: html, segments: []) }

        var template = html
        // 代码块先整体挪走：里面的内容不该被翻译，形状也不该被正则碰到。
        let codeBlocks = protectCodeBlocks(&template)

        var segments: [Segment] = []
        var processed = process(template, segments: &segments)
        restoreCodeBlocks(codeBlocks, into: &processed)

        return Plan(template: processed, segments: segments)
    }

    /// 递归处理一段 HTML。
    ///
    /// 正则的 `matches(in:)` 不会返回嵌套匹配，所以 `<li><p>text</p></li>` 里的
    /// `<p>` 根本不会被单独匹配到。这里改为：外层块若还套着别的块，就把它交给
    /// 内层递归处理，自己只负责把结果拼回去。
    private static func process(_ html: String, segments: inout [Segment]) -> String {
        var output = html
        let range = NSRange(html.startIndex..., in: html)
        var edits: [(range: Range<String.Index>, replacement: String)] = []

        for match in blockPattern.matches(in: html, range: range) {
            guard let contentRange = Range(match.range(at: 3), in: html) else { continue }
            let inner = String(html[contentRange])

            if containsNestedBlock(inner) {
                edits.append((contentRange, process(inner, segments: &segments)))
                continue
            }
            guard containsTranslatableText(inner) else { continue }

            let (text, links, labels) = extractLinks(from: inner, offset: segments.count + 1)
            // 剥掉其余内联标签，只留纯文本与链接占位符。否则模型会把 `<span>`
            // 这类标签一并带进译文，最终在页面上显示成可见的标签文本。
            let plain = HTMLText.plain(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard plain.isEmpty == false else { continue }

            let index = segments.count
            segments.append(Segment(index: index, text: plain, links: links))
            // 链接文字排在正文之后，一起送翻。
            for label in labels {
                segments.append(Segment(index: segments.count, text: label.text, links: []))
            }
            edits.append((contentRange, marker(for: index)))
        }

        // 正序收集、倒序应用：替换会改变后续位置。
        for edit in edits.reversed() {
            output.replaceSubrange(edit.range, with: edit.replacement)
        }
        return output
    }

    // MARK: - 重组

    /// 把译文按原顺序填回模板。译文数量与片段不一致时返回 nil，由调用方决定怎么处理。
    public static func assemble(plan: Plan, translations: [String]) -> String? {
        guard translations.count == plan.segments.count else { return nil }

        var output = plan.template
        for segment in plan.segments {
            var text = escapeHTML(translations[segment.index])

            for link in segment.links {
                let label = link.labelSegmentIndex < translations.count
                    ? escapeHTML(translations[link.labelSegmentIndex])
                    : ""
                let anchor = "<a href=\"\(escapeAttribute(link.href))\">\(label)</a>"
                text = text.replacingOccurrences(of: link.marker, with: anchor)
            }

            output = output.replacingOccurrences(of: marker(for: segment.index), with: text)
        }
        return output
    }

    // MARK: - 内部

    /// 可翻译位置在模板里的标记。用不可见字符包裹，避免与正文内容撞车。
    static func marker(for index: Int) -> String {
        "\u{0}SEG\(index)\u{0}"
    }

    /// 抽出段内链接，返回替换成占位符的文本、链接信息与待翻的链接文字。
    private static func extractLinks(
        from html: String,
        offset: Int
    ) -> (text: String, links: [LinkToken], labels: [(text: String, index: Int)]) {
        var text = html
        var links: [LinkToken] = []
        var labels: [(text: String, index: Int)] = []

        let matches = linkPattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var edits: [(range: Range<String.Index>, replacement: String)] = []

        for (order, match) in matches.enumerated() {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html),
                  let wholeRange = Range(match.range, in: html)
            else { continue }

            let marker = "[[\(order)]]"
            let labelText = HTMLText.plain(from: String(html[labelRange]))
            let labelIndex = offset + labels.count

            links.append(
                LinkToken(marker: marker, href: String(html[hrefRange]), labelSegmentIndex: labelIndex)
            )
            // 链接文字为空时也补一个占位片段，保证索引与译文数量对得上。
            labels.append((text: labelText.isEmpty ? " " : labelText, index: labelIndex))
            edits.append((wholeRange, marker))
        }

        for edit in edits.reversed() {
            text.replaceSubrange(edit.range, with: edit.replacement)
        }

        return (text.trimmingCharacters(in: .whitespacesAndNewlines), links, labels)
    }

    /// 内层还套着别的块级元素时跳过：那段文字会由内层那次匹配处理，
    /// 否则同一段会被翻译两遍，重组时也互相盖。
    private static func containsNestedBlock(_ html: String) -> Bool {
        let lower = html.lowercased()
        return nestedTags.contains { lower.contains($0) }
    }

    /// 判断这段 HTML 里是否真的有需要翻译的文字。
    private static func containsTranslatableText(_ html: String) -> Bool {
        let plain = HTMLText.plain(from: html)
        let letters = plain.filter { $0.isLetter }
        guard letters.count >= 2 else { return false }

        // 已经是中文的段落不需要翻译。
        let cjkCount = letters.filter { $0.isCJK }.count
        return Double(cjkCount) / Double(letters.count) < 0.5
    }

    private static func protectCodeBlocks(_ html: inout String) -> [String] {
        var blocks: [String] = []
        let matches = codeBlockPattern.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var edits: [(range: Range<String.Index>, replacement: String)] = []
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let token = "\u{0}PRE\(blocks.count)\u{0}"
            blocks.append(String(html[range]))
            edits.append((range, token))
        }
        for edit in edits.reversed() {
            html.replaceSubrange(edit.range, with: edit.replacement)
        }
        return blocks
    }

    private static func restoreCodeBlocks(_ blocks: [String], into html: inout String) {
        for (index, block) in blocks.enumerated() {
            html = html.replacingOccurrences(of: "\u{0}PRE\(index)\u{0}", with: block)
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension Character {
    /// 中日韩字符（含全角标点），用于判断段落是不是已经是中文。
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}
