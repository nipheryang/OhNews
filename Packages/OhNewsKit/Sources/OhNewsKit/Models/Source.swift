import Foundation

/// 信息源的种类。
///
/// 新增来源时在这里扩展，并在 app 层提供对应的 `NewsSourceProvider` 实现。
public enum SourceKind: String, Codable, Hashable, Sendable {
    /// Hacker News 官方接口。
    case hackerNews
    /// RSS 2.0 或 Atom 1.0 订阅源。
    case rss

    /// 展示用名称。
    public var displayName: String {
        switch self {
        case .hackerNews: "Hacker News"
        case .rss: "RSS 订阅"
        }
    }
}

/// 一个信息源。
///
/// `id` 全局唯一且稳定：内置源用固定字符串，RSS 用 feed 地址的短哈希，
/// 因此同一个 feed 无论添加多少次都会得到同一个 `id`。
public struct NewsSource: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: SourceKind
    /// 显示名。RSS 源在首次抓取成功后会被替换为 feed 自身的标题。
    public var name: String
    /// 仅 RSS 源有值。
    public var feedURL: URL?

    public init(id: String, kind: SourceKind, name: String, feedURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.feedURL = feedURL
    }
}

/// 源内的一个频道。
///
/// Hacker News 有五个频道（对应原来的五个榜单）；一个 RSS 源对应一个频道。
/// 把「频道」独立出来，是为了将来能在同一个源下挂多个频道（例如某个社区源的多个板块）。
public struct SourceChannel: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let sourceID: String
    /// 显示名，例如「首页」或 feed 标题。
    public var name: String

    public init(id: String, sourceID: String, name: String) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
    }
}
