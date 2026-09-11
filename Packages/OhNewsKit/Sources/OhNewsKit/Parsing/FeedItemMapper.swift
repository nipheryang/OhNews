import Foundation

/// 把解析出来的 feed 条目映射为统一的 `Story`。
///
/// 映射规则集中在这里，provider 只负责取数据，不重复决定「缺字段怎么办」。
public enum FeedItemMapper {
    /// 单条映射。源没有 feed 地址时返回 nil。
    ///
    /// - Parameter now: 条目缺少日期时的兜底时间，注入以便测试。
    public static func story(
        from item: ParsedFeedItem,
        source: NewsSource,
        now: Date = Date()
    ) -> Story? {
        guard let feedURL = source.feedURL else { return nil }

        return Story(
            id: SourceIdentifier.rssItemID(feedURL: feedURL, guid: item.identifier),
            sourceID: source.id,
            title: item.title,
            url: item.link,
            // RSS 没有分数与评论数这两个概念，留空而不是填 0：
            // 界面据此隐藏这两项，AI 也不会把它们当成真实的零。
            score: nil,
            author: item.author ?? "",
            // `Story` 的发布日期非可选，而绝大多数 feed 都有日期；
            // 少数没写的用当前时间兜底，避免为了个别 feed 放宽模型。
            postedAt: item.publishedAt ?? now,
            commentCount: nil,
            type: .story,
            // 正文既用于阅读器（条目无外链时），也用于生成摘要。
            text: item.content
        )
    }

    public static func stories(
        from feed: ParsedFeed,
        source: NewsSource,
        limit: Int,
        now: Date = Date()
    ) -> [Story] {
        feed.items
            .prefix(limit)
            .compactMap { story(from: $0, source: source, now: now) }
    }
}
