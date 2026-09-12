// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 正文解读 prompt 的组装。
///
/// 与摘要 prompt 的关键差别是**输入包含正文**：摘要跑在抓正文之前，只能凭标题与
/// 评论作答；这份要回答「正文讲了什么」，没有正文就没有意义。
public enum InsightPromptBuilder {
    /// 正文最多取多少字送进模型。太长的正文会把评论挤出去，而评论正是这份解读
    /// 的另一半。超出部分截断。
    public static let maxArticleCharacters = 6000

    public static func systemPrompt() -> String {
        """
        你是一位替中文读者精读文章、并代读评论区的编辑。

        只输出一个 JSON 对象，不要 Markdown 代码块，不要输出任何解释文字。字段与类型如下：
        {"article_summary": string, "key_points": string[], "discussion_summary": string, "discussion_trends": string[]}

        字段要求：
        - article_summary：3 到 5 句简体中文，说明正文讲了什么：主题、主要论据与结论。
          只能依据给出的正文作答，不要补充正文里没有的背景，也不要评价写得如何。
        - key_points：3 到 5 条正文的关键要点，每条一句。要具体，不要写成「文章讨论了……」
          这种什么都没有的话。
        - discussion_summary：2 到 3 句简体中文，概括评论区的核心观点。没有评论区时填空字符串。
        - discussion_trends：2 到 4 条评论区值得注意的分歧、共识或情绪走向，每条一句。
          没有评论区时填空数组。不要把个别评论当成整体趋势。
        """
    }

    /// - Parameters:
    ///   - articleHTML: 正文 HTML。会先剥成纯文本再截断。
    ///   - discussionHTML: 讨论区 HTML（已渲染的评论树）。为 nil 时不送入。
    public static func build(
        story: Story,
        articleHTML: String?,
        discussionHTML: String?,
        limits: CommentLimits = .default
    ) -> PromptPair {
        var lines: [String] = []

        lines.append("标题：\(story.title)")
        if let host = story.sourceHost {
            lines.append("来源：\(host)")
        }

        if let body = articleHTML {
            let plain = truncate(
                HTMLText.plain(from: body),
                to: maxArticleCharacters
            )
            lines.append("正文：\n\(plain.isEmpty ? "（未能取到正文）" : plain)")
        } else {
            lines.append("正文：\n（未能取到正文）")
        }

        let comments = commentExcerpt(from: discussionHTML, limits: limits)
        if comments.isEmpty == false {
            lines.append("评论区（按楼层顺序，已截断）：\n\(comments)")
        }

        return PromptPair(system: systemPrompt(), user: lines.joined(separator: "\n"))
    }

    /// 讨论区 HTML 已经在渲染时拼好，这里只做剥离与限量：
    /// 评论树里还带着楼层号、作者与时间，对判断观点没有帮助，反而占额度。
    static func commentExcerpt(
        from discussionHTML: String?,
        limits: CommentLimits
    ) -> String {
        guard let discussionHTML else { return "" }

        let plain = HTMLText.plain(from: discussionHTML)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var lines: [String] = []
        var used = 0
        for line in plain {
            if lines.count >= limits.maxBlocks { break }
            let text = truncate(line, to: limits.maxCharactersPerBlock)
            used += text.count
            if used > limits.totalCharacters { break }
            lines.append(text)
        }
        return lines.joined(separator: "\n")
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "……"
    }

    /// 讨论区的送模型上限。
    public struct CommentLimits: Sendable {
        public let maxBlocks: Int
        public let maxCharactersPerBlock: Int
        public let totalCharacters: Int

        public init(maxBlocks: Int, maxCharactersPerBlock: Int, totalCharacters: Int) {
            self.maxBlocks = maxBlocks
            self.maxCharactersPerBlock = maxCharactersPerBlock
            self.totalCharacters = totalCharacters
        }

        public static let `default` = CommentLimits(
            maxBlocks: 40,
            maxCharactersPerBlock: 600,
            totalCharacters: 6000
        )
    }
}
