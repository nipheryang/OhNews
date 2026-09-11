import Foundation

/// 列表级 AI 摘要。
///
/// 缓存有效性由 `promptVersion` 与 `modelName` 共同决定：换模型或改 prompt 后旧摘要自动失效。
public struct StorySummary: Codable, Hashable, Sendable {
    public let storyID: Int
    /// 英文标题的中文翻译。
    public let chineseTitle: String
    /// 2 到 3 句中文摘要。
    public let summary: String
    public let tags: [String]
    /// 评论区主要观点或分歧，无讨论时为 nil。
    public let commentConsensus: String?
    public let modelName: String
    public let promptVersion: String
    public let generatedAt: Date

    public init(
        storyID: Int,
        chineseTitle: String,
        summary: String,
        tags: [String],
        commentConsensus: String?,
        modelName: String,
        promptVersion: String,
        generatedAt: Date
    ) {
        self.storyID = storyID
        self.chineseTitle = chineseTitle
        self.summary = summary
        self.tags = tags
        self.commentConsensus = commentConsensus
        self.modelName = modelName
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }

    /// 该摘要是否由指定的 prompt 版本与模型生成。
    public func matches(promptVersion: String, modelName: String) -> Bool {
        self.promptVersion == promptVersion && self.modelName == modelName
    }
}
