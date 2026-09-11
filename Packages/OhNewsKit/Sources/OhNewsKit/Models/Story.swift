import Foundation

/// Hacker News 条目类型。
///
/// 未知类型归入 `unknown`，避免接口新增类型时整个条目解析失败。
public enum ItemType: String, Codable, Hashable, Sendable {
    case story
    case comment
    case poll
    case pollopt
    case job
    case unknown

    public init(lenient raw: String?) {
        guard let raw, let value = ItemType(rawValue: raw) else {
            self = .unknown
            return
        }
        self = value
    }
}

/// 一条内容。
///
/// 字段结构沿用 Hacker News 的条目形态，但已做成多源可用的形式：
/// 来源没有分数或评论数概念时（例如 RSS）这些字段留空，而不是填 0，
/// 这样界面才能区分「没有这个数据」和「这个数据是零」。
public struct Story: Codable, Identifiable, Hashable, Sendable {
    /// 全局唯一标识，带源前缀，例如 `hn:12345`、`rss:8f3a1c2d…`。
    public let id: String
    /// 所属源的 ID。
    public let sourceID: String
    public let title: String
    /// 外链地址。Ask HN、Show HN 等自述帖以及部分源没有外链。
    public let url: URL?
    /// 分数。来源没有这个概念时为 nil。
    public let score: Int?
    public let author: String
    public let postedAt: Date
    /// 评论总数，对应 HN 的 `descendants`。来源没有评论或数量未知时为 nil。
    public let commentCount: Int?
    public let type: ItemType
    /// 自述正文（HTML），仅 Ask HN、Show HN 这类帖子有值。
    public let text: String?

    public init(
        id: String,
        sourceID: String,
        title: String,
        url: URL?,
        score: Int?,
        author: String,
        postedAt: Date,
        commentCount: Int?,
        type: ItemType,
        text: String?
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.url = url
        self.score = score
        self.author = author
        self.postedAt = postedAt
        self.commentCount = commentCount
        self.type = type
        self.text = text
    }

    /// 展示用域名，例如 `github.blog`。无外链时返回 nil。
    public var sourceHost: String? {
        guard let host = url?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// 是否为自述帖（无外链、正文即内容）。
    public var isSelfPost: Bool {
        url == nil && (text?.isEmpty == false)
    }
}
