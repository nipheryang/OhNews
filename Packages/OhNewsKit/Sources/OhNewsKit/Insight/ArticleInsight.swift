// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 正文解读的 prompt 版本。
///
/// 与摘要的 `PromptVersion` 分开：两者的 prompt 会各自演进，共用一个版本号
/// 会让改动互相误伤——改解读的措辞不该让所有摘要缓存一起作废。
public enum InsightPromptVersion {
    /// 改动 `InsightPromptBuilder` 的输出格式或字段含义时递增。
    ///
    /// i2：要求明显更短（总结一句话、要点最多 3 条）。不递增的话，
    /// 已经生成过的解读会一直用缓存里的旧文本，用户改了期待也看不到变化。
    public static let current = "i2"
}

/// 一篇文章的正文解读。
///
/// 与列表用的 `StorySummary` 是两份东西：那份跑在抓正文之前，只能凭标题与评论作答；
/// 这份读的是正文本身，回答「这篇文章讲了什么、大家怎么看」。
public struct ArticleInsight: Codable, Hashable, Sendable {
    public let itemID: String
    /// 正文与讨论区合并计算的内容哈希。任一部分变化都会让旧解读失效。
    public let contentHash: String
    /// 正文讲了什么：主题、主要论据与结论。
    public let articleSummary: String
    /// 正文的关键要点。
    public let keyPoints: [String]
    /// 评论区的核心观点。没有讨论时为空。
    public let discussionSummary: String?
    /// 评论区值得注意的分歧、共识或情绪走向。
    public let discussionTrends: [String]
    public let modelName: String
    public let promptVersion: String
    public let generatedAt: Date

    public init(
        itemID: String,
        contentHash: String,
        articleSummary: String,
        keyPoints: [String],
        discussionSummary: String?,
        discussionTrends: [String],
        modelName: String,
        promptVersion: String,
        generatedAt: Date
    ) {
        self.itemID = itemID
        self.contentHash = contentHash
        self.articleSummary = articleSummary
        self.keyPoints = keyPoints
        self.discussionSummary = discussionSummary
        self.discussionTrends = discussionTrends
        self.modelName = modelName
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }

    /// 这份解读是否仍然对应当前内容与配置。
    public func matches(contentHash: String, modelName: String, promptVersion: String) -> Bool {
        self.contentHash == contentHash
            && self.modelName == modelName
            && self.promptVersion == promptVersion
    }

    /// 有没有可展示的内容。模型偶尔会对没有讨论的文章给出空摘要，
    /// 这种情况不该在正文顶部留一个空壳。
    public var hasContent: Bool {
        articleSummary.isEmpty == false || keyPoints.isEmpty == false
    }
}
