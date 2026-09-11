import Foundation
import Testing
@testable import OhNewsKit

@Suite("FeedItemMapper")
struct FeedItemMapperTests {
    private func makeSource(_ urlText: String = "https://blog.example.com/feed") throws -> NewsSource {
        let url = try #require(URL(string: urlText))
        return NewsSource(
            id: SourceIdentifier.rssSourceID(feedURL: url),
            kind: .rss,
            name: "示例博客",
            feedURL: url
        )
    }

    private func makeItem(
        identifier: String = "post-1",
        title: String = "标题",
        link: String? = "https://blog.example.com/post-1",
        author: String? = "nipher",
        publishedAt: Date? = Date(timeIntervalSince1970: 1_780_000_000),
        content: String? = "<p>正文</p>"
    ) -> ParsedFeedItem {
        ParsedFeedItem(
            identifier: identifier,
            title: title,
            link: link.flatMap { URL(string: $0) },
            author: author,
            publishedAt: publishedAt,
            content: content
        )
    }

    @Test func mapsFieldsAndLeavesMetricsEmpty() throws {
        let source = try makeSource()
        let feedURL = try #require(source.feedURL)
        let item = makeItem()

        let story = try #require(FeedItemMapper.story(from: item, source: source))

        #expect(story.sourceID == source.id)
        #expect(story.id == SourceIdentifier.rssItemID(feedURL: feedURL, guid: "post-1"))
        #expect(story.title == "标题")
        #expect(story.url == item.link)
        #expect(story.author == "nipher")
        #expect(story.postedAt == item.publishedAt)
        #expect(story.text == "<p>正文</p>")
        // RSS 没有这两个概念，必须留空而不是填 0，界面才会隐藏它们。
        #expect(story.score == nil)
        #expect(story.commentCount == nil)
        #expect(story.type == .story)
    }

    @Test func fallsBackToNowWhenDateIsMissing() throws {
        let source = try makeSource()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let story = try #require(
            FeedItemMapper.story(from: makeItem(publishedAt: nil), source: source, now: now)
        )
        #expect(story.postedAt == now)
    }

    @Test func returnsNilWhenSourceHasNoFeedURL() throws {
        let source = NewsSource(id: "rss:none", kind: .rss, name: "没有地址")
        #expect(FeedItemMapper.story(from: makeItem(), source: source) == nil)
    }

    @Test func appliesLimit() throws {
        let source = try makeSource()
        let items = (0..<10).map { makeItem(identifier: "post-\($0)") }
        let feed = ParsedFeed(title: "示例", items: items)

        let stories = FeedItemMapper.stories(from: feed, source: source, limit: 3)
        #expect(stories.count == 3)
        #expect(stories.first?.title == "标题")
    }

    /// 同一个 feed 里的两条不同条目必须得到不同 ID，否则会互相覆盖。
    @Test func distinctItemsGetDistinctIDs() throws {
        let source = try makeSource()
        let first = try #require(FeedItemMapper.story(from: makeItem(identifier: "a"), source: source))
        let second = try #require(FeedItemMapper.story(from: makeItem(identifier: "b"), source: source))

        #expect(first.id != second.id)
        #expect(first.id.hasPrefix("rss:"))
    }
}

@Suite("SourceKind 推断")
struct SourceKindInferenceTests {
    @Test func recognizesHackerNews() {
        #expect(SourceKind.inferred(fromSourceID: "hn") == .hackerNews)
        #expect(SourceKind.inferred(fromSourceID: "hn:top") == .hackerNews)
    }

    @Test func recognizesRSS() {
        #expect(SourceKind.inferred(fromSourceID: "rss:9a1f2b3c") == .rss)
    }

    @Test func fallsBackToRSSForUnknownPrefix() {
        #expect(SourceKind.inferred(fromSourceID: "something:else") == .rss)
        #expect(SourceKind.inferred(fromSourceID: "") == .rss)
    }

    @Test func prefixMatchesBuiltInIdentifiers() {
        #expect(SourceKind.hackerNews.identifierPrefix == HackerNewsSource.sourceID)
        #expect(SourceKind.rss.identifierPrefix == "rss")
    }
}
