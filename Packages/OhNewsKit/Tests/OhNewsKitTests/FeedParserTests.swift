// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import OhNewsKit

@Suite("FeedParser")
struct FeedParserTests {
    private func utcDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - RSS

    @Test func parsesRSSFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>示例博客</title>
            <link>https://blog.example.com</link>
            <item>
              <title>第一篇文章</title>
              <link>https://blog.example.com/post-1</link>
              <guid isPermaLink="false">post-1</guid>
              <author>nipher</author>
              <pubDate>Thu, 01 Sep 2026 12:00:00 GMT</pubDate>
              <description>文章的摘要内容。</description>
            </item>
          </channel>
        </rss>
        """

        let feed = try FeedParser.parse(Data(xml.utf8))

        #expect(feed.title == "示例博客")
        #expect(feed.items.count == 1)

        let item = try #require(feed.items.first)
        #expect(item.identifier == "post-1")
        #expect(item.title == "第一篇文章")
        #expect(item.link?.absoluteString == "https://blog.example.com/post-1")
        #expect(item.author == "nipher")
        #expect(item.content == "文章的摘要内容。")
        #expect(item.publishedAt == utcDate("2026-09-01T12:00:00Z"))
    }

    @Test func prefersContentEncodedOverDescription() throws {
        let xml = """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <item>
              <title>标题</title>
              <link>https://blog.example.com/post-2</link>
              <description>这是摘要</description>
              <content:encoded><![CDATA[<p>这是全文</p>]]></content:encoded>
            </item>
          </channel>
        </rss>
        """

        let item = try #require(try FeedParser.parse(Data(xml.utf8)).items.first)
        #expect(item.content == "<p>这是全文</p>")
    }

    @Test func readsCDATAContent() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <title>标题</title>
              <link>https://blog.example.com/post-3</link>
              <description><![CDATA[<p>带 <b>标签</b> 的内容</p>]]></description>
            </item>
          </channel>
        </rss>
        """

        let item = try #require(try FeedParser.parse(Data(xml.utf8)).items.first)
        #expect(item.content == "<p>带 <b>标签</b> 的内容</p>")
    }

    /// 部分 feed 没有转义 description 里的 HTML，标签会被当成子元素。
    /// 这时至少要保住文本，不能让整条内容变成空。
    @Test func keepsTextFromUnescapedMarkup() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <title>标题</title>
              <link>https://blog.example.com/post-4</link>
              <description>第一段<p>第二段</p></description>
            </item>
          </channel>
        </rss>
        """

        let item = try #require(try FeedParser.parse(Data(xml.utf8)).items.first)
        let content = try #require(item.content)
        #expect(content.contains("第一段"))
        #expect(content.contains("第二段"))
    }

    // MARK: - Atom

    @Test func parsesAtomFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>示例 Atom</title>
          <link rel="self" href="https://example.com/feed.xml"/>
          <link rel="alternate" href="https://example.com/"/>
          <entry>
            <title>Atom 文章</title>
            <link rel="alternate" href="/posts/atom-1"/>
            <id>tag:example.com,2026:atom-1</id>
            <author><name>nipher</name></author>
            <published>2026-09-02T08:30:00Z</published>
            <content type="html">&lt;p&gt;正文内容&lt;/p&gt;</content>
          </entry>
        </feed>
        """

        let feed = try FeedParser.parse(Data(xml.utf8))

        #expect(feed.title == "示例 Atom")
        let item = try #require(feed.items.first)
        #expect(item.identifier == "tag:example.com,2026:atom-1")
        #expect(item.author == "nipher")
        #expect(item.content == "<p>正文内容</p>")
        #expect(item.publishedAt == utcDate("2026-09-02T08:30:00Z"))
    }

    /// Atom 里 rel="self" 指向订阅地址本身，不能当成文章链接；
    /// 条目的相对地址要基于 feed 的地址补全。
    @Test func resolvesRelativeLinkAgainstFeedURL() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>示例 Atom</title>
          <link rel="self" href="https://example.com/feed.xml"/>
          <link rel="alternate" href="https://example.com/blog/"/>
          <entry>
            <title>相对链接</title>
            <link rel="alternate" href="posts/relative-1"/>
            <id>relative-1</id>
          </entry>
        </feed>
        """

        let feed = try FeedParser.parse(Data(xml.utf8))
        let item = try #require(feed.items.first)
        #expect(item.link?.absoluteString == "https://example.com/blog/posts/relative-1")
    }

    // MARK: - 边界

    @Test func fallsBackToLinkWhenGUIDIsMissing() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <title>没有 GUID</title>
              <link>https://blog.example.com/no-guid</link>
            </item>
          </channel>
        </rss>
        """

        let item = try #require(try FeedParser.parse(Data(xml.utf8)).items.first)
        #expect(item.identifier == "https://blog.example.com/no-guid")
    }

    /// 既没有 GUID 也没有链接的条目无法生成稳定标识，只能跳过，
    /// 但不能因此让整份 feed 解析失败。
    @Test func skipsItemsWithoutIdentifierAndLink() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <title>没有任何标识</title>
            </item>
            <item>
              <title>正常条目</title>
              <link>https://blog.example.com/ok</link>
            </item>
          </channel>
        </rss>
        """

        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.items.count == 1)
        #expect(feed.items.first?.title == "正常条目")
    }

    @Test func titledItemsFallBackToIdentifierWhenTitleIsMissing() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <link>https://blog.example.com/no-title</link>
            </item>
          </channel>
        </rss>
        """

        let item = try #require(try FeedParser.parse(Data(xml.utf8)).items.first)
        #expect(item.title == "https://blog.example.com/no-title")
    }

    @Test func acceptsFeedWithoutItems() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <title>空 feed</title>
          </channel>
        </rss>
        """

        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.title == "空 feed")
        #expect(feed.items.isEmpty)
    }

    @Test func rejectsMalformedXML() {
        #expect(throws: FeedParseError.malformedXML) {
            try FeedParser.parse(Data("<rss><channel>".utf8))
        }
    }

    @Test func rejectsNonFeedXML() {
        #expect(throws: FeedParseError.unsupportedFormat) {
            try FeedParser.parse(Data("<html><body>hi</body></html>".utf8))
        }
    }
}

@Suite("FeedDateParser")
struct FeedDateParserTests {
    private func utcDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    @Test func parsesRFC822WithNamedZone() {
        #expect(FeedDateParser.parse("Thu, 01 Sep 2026 12:00:00 GMT") == utcDate("2026-09-01T12:00:00Z"))
    }

    @Test func parsesRFC822WithNumericOffset() {
        // +0800 的 12:00 等于 UTC 的 04:00。
        #expect(FeedDateParser.parse("Thu, 01 Sep 2026 12:00:00 +0800") == utcDate("2026-09-01T04:00:00Z"))
    }

    @Test func parsesRFC822WithoutSeconds() {
        #expect(FeedDateParser.parse("Thu, 01 Sep 2026 12:00 GMT") == utcDate("2026-09-01T12:00:00Z"))
    }

    @Test func parsesISO8601() {
        #expect(FeedDateParser.parse("2026-09-01T12:00:00Z") == utcDate("2026-09-01T12:00:00Z"))
    }

    @Test func parsesISO8601WithFractionalSeconds() {
        #expect(FeedDateParser.parse("2026-09-01T12:00:00.123Z") != nil)
    }

    @Test func returnsNilForUnparsableText() {
        #expect(FeedDateParser.parse("昨天下午") == nil)
        #expect(FeedDateParser.parse("") == nil)
    }
}
