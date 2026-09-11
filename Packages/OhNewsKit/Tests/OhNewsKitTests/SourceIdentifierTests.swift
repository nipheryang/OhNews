import Foundation
import Testing
@testable import OhNewsKit

@Suite("SourceIdentifier")
struct SourceIdentifierTests {
    @Test func shortHashIsStableAndFixedLength() {
        let first = SourceIdentifier.shortHash("https://example.com/feed")
        let second = SourceIdentifier.shortHash("https://example.com/feed")

        #expect(first == second)
        #expect(first.count == 16)
        #expect(first != SourceIdentifier.shortHash("https://example.com/other"))
    }

    @Test func itemIDCarriesSourcePrefix() {
        #expect(SourceIdentifier.itemID(sourceID: "hn", rawID: "12345") == "hn:12345")
        #expect(SourceIdentifier.channelID(sourceID: "hn", key: "top") == "hn:top")
    }

    @Test func normalizesFeedURLVariants() throws {
        let uppercase = try #require(URL(string: "HTTPS://Example.com/feed/"))
        let lowercase = try #require(URL(string: "https://example.com/feed"))

        #expect(
            SourceIdentifier.normalizedFeedKey(uppercase)
                == SourceIdentifier.normalizedFeedKey(lowercase)
        )
    }

    @Test func dropsFragmentWhenNormalizing() throws {
        let withFragment = try #require(URL(string: "https://example.com/feed#section"))
        let withoutFragment = try #require(URL(string: "https://example.com/feed"))

        #expect(
            SourceIdentifier.rssSourceID(feedURL: withFragment)
                == SourceIdentifier.rssSourceID(feedURL: withoutFragment)
        )
    }

    /// 同一个 feed 换一种写法再添加，必须落在同一个源上，否则会冒出重复订阅。
    @Test func sameFeedInDifferentFormYieldsSameSourceID() throws {
        let trailingSlash = try #require(URL(string: "https://Example.com/feed/"))
        let plain = try #require(URL(string: "https://example.com/feed"))

        #expect(
            SourceIdentifier.rssSourceID(feedURL: trailingSlash)
                == SourceIdentifier.rssSourceID(feedURL: plain)
        )
    }

    @Test func rssItemIDIsStableAndDistinct() throws {
        let feed = try #require(URL(string: "https://example.com/feed"))

        let first = SourceIdentifier.rssItemID(feedURL: feed, guid: "post-1")
        #expect(first == SourceIdentifier.rssItemID(feedURL: feed, guid: "post-1"))
        #expect(first != SourceIdentifier.rssItemID(feedURL: feed, guid: "post-2"))
        #expect(first.hasPrefix("rss:"))
    }

    /// 同一个 GUID 出现在两个不同 feed 里时，必须是两条不同的条目。
    @Test func sameGUIDInDifferentFeedsYieldsDifferentItemIDs() throws {
        let firstFeed = try #require(URL(string: "https://a.example.com/feed"))
        let secondFeed = try #require(URL(string: "https://b.example.com/feed"))

        #expect(
            SourceIdentifier.rssItemID(feedURL: firstFeed, guid: "post-1")
                != SourceIdentifier.rssItemID(feedURL: secondFeed, guid: "post-1")
        )
    }
}
