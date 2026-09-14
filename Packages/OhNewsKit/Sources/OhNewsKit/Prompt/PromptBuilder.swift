// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 评论进入 prompt 前的截断规则。
///
/// 评论树可能上百条、上万字符，必须固定上限，否则单次请求成本和延迟都不可控。
/// 字符预算只统计评论正文，不含 `- 作者：` 前缀。
public struct PromptLimits: Hashable, Sendable {
    public let maxComments: Int
    public let maxCharactersPerComment: Int
    public let maxTotalCommentCharacters: Int
    /// HN 自述帖正文的截断长度。
    public let maxCharactersPerBody: Int

    public init(
        maxComments: Int,
        maxCharactersPerComment: Int,
        maxTotalCommentCharacters: Int,
        maxCharactersPerBody: Int
    ) {
        self.maxComments = maxComments
        self.maxCharactersPerComment = maxCharactersPerComment
        self.maxTotalCommentCharacters = maxTotalCommentCharacters
        self.maxCharactersPerBody = maxCharactersPerBody
    }

    public static let `default` = PromptLimits(
        maxComments: 20,
        maxCharactersPerComment: 600,
        maxTotalCommentCharacters: 6000,
        maxCharactersPerBody: 1500
    )
}

public struct PromptPair: Hashable, Sendable {
    public let system: String
    public let user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

/// 摘要 prompt 的组装。
///
/// 纯函数：输入 `Story` 与评论树，输出固定结构的 system / user 两段。
/// system 段保持稳定，便于供应商侧做 prompt 缓存。
public enum PromptBuilder {
    /// 按来源种类生成 system 段。
    ///
    /// 只有开头一句随来源变化，其余部分对所有来源一致：固定前缀有利于供应商侧的
    /// prompt 缓存命中，也避免同一份需求写出几个逐渐跑偏的版本。
    public static func systemPrompt(for kind: SourceKind) -> String {
        """
        \(leadingSentence(for: kind))

        只输出一个 JSON 对象，不要 Markdown 代码块，不要输出任何解释文字。字段与类型如下：
    {"title_zh": string, "summary": string, "tags": string[], "comment_consensus": string}

    字段要求：
    - title_zh：标题的中文翻译，专有名词、人名、产品名保留英文原文。
    - summary：2 到 3 句简体中文，说明这条内容是什么，以及读者能从中得到什么。
      只能依据给出的信息作答，不要编造文章正文中的细节。
    - tags：2 到 4 个主题标签，从以下集合中挑选：AI、开发工具、编程语言、后端、前端、数据库、安全、硬件、开源、创业、科学、产品、设计、政策、文化、其他。
    - comment_consensus：一句话概括评论区的主要观点或分歧；评论区为空或没有实质讨论时填空字符串。
    """
    }

    /// system 段的首句：点明这份材料的来源，其余要求与格式不因来源而变。
    private static func leadingSentence(for kind: SourceKind) -> String {
        switch kind {
        case .hackerNews: "你是帮助中文读者判断 Hacker News 内容价值的技术编辑。"
        case .rss: "你是帮助中文读者快速判断文章价值的技术编辑。"
        case .savedPage: "你是帮助中文读者快速判断一篇文章价值的技术编辑。"
        }
    }

    public static func build(
        story: Story,
        comments: StoryComments?,
        limits: PromptLimits = .default
    ) -> PromptPair {
        let kind = SourceKind.inferred(fromSourceID: story.sourceID)

        var lines: [String] = []
        lines.append("标题：\(story.title)")
        if let host = story.sourceHost {
            lines.append("来源：\(host)")
        }
        if let url = story.url {
            lines.append("链接：\(url.absoluteString)")
        } else {
            lines.append("链接：无")
        }
        // 分数与评论数并非每个来源都有：缺哪一项就不输出哪一项，而不是输出 0，
        // 否则模型会把「没有这个数据」当成「这个数据是零」。
        var metrics: [String] = []
        if let score = story.score { metrics.append("分数：\(score)") }
        if let commentCount = story.commentCount { metrics.append("评论数：\(commentCount)") }
        if metrics.isEmpty == false {
            lines.append(metrics.joined(separator: "　"))
        }

        // 来源自带正文时一并交给模型：RSS 条目通常没有评论，正文是唯一的内容依据。
        if let body = story.text {
            let plainBody = truncate(HTMLText.plain(from: body), to: limits.maxCharactersPerBody)
            if plainBody.isEmpty == false {
                lines.append("正文：\n\(plainBody)")
            }
        }

        let commentBlock = formatComments(comments, limits: limits)
        if commentBlock.isEmpty == false {
            lines.append("评论区（按楼层顺序，已截断）：\n\(commentBlock)")
        }

        return PromptPair(system: systemPrompt(for: kind), user: lines.joined(separator: "\n"))
    }

    // MARK: - 内部

    static func formatComments(_ comments: StoryComments?, limits: PromptLimits) -> String {
        guard let comments else { return "" }

        var nodes: [CommentNode] = []
        collectDepthFirst(comments.topLevel, into: &nodes)

        var lines: [String] = []
        var usedCharacters = 0

        for (index, node) in nodes.enumerated() {
            if index >= limits.maxComments { break }
            guard let raw = node.text else { continue }

            let text = truncate(
                HTMLText.plain(from: raw),
                to: limits.maxCharactersPerComment
            )
            if text.isEmpty { continue }
            if usedCharacters + text.count > limits.maxTotalCommentCharacters { break }

            usedCharacters += text.count
            lines.append("- \(node.author ?? "匿名")：\(text)")
        }

        return lines.joined(separator: "\n")
    }

    /// 深度优先展开，保证顶层评论优先进入有限的额度。
    private static func collectDepthFirst(_ list: [CommentNode], into result: inout [CommentNode]) {
        for node in list {
            result.append(node)
            collectDepthFirst(node.children, into: &result)
        }
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
