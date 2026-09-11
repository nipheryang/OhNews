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

/// 一条 Hacker News 内容（story / job / poll）。
///
/// 只保留 V0 需要的字段，已是领域模型，不再对应接口原始结构。
public struct Story: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    /// 外链地址。Ask HN、Show HN 等自述帖没有外链。
    public let url: URL?
    public let score: Int
    public let author: String
    public let postedAt: Date
    /// 评论总数，对应 HN 的 `descendants`。
    public let commentCount: Int
    public let type: ItemType
    /// 自述正文（HTML），仅 Ask HN、Show HN 这类帖子有值。
    public let text: String?

    public init(
        id: Int,
        title: String,
        url: URL?,
        score: Int,
        author: String,
        postedAt: Date,
        commentCount: Int,
        type: ItemType,
        text: String?
    ) {
        self.id = id
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

    /// 是否为 HN 自述帖（无外链、正文即内容）。
    public var isSelfPost: Bool {
        url == nil && (text?.isEmpty == false)
    }
}
