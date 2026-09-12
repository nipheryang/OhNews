// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

/// 用真实站点的 feed 验证解析器。
///
/// 合成样本只能覆盖自己想到的写法，真实 feed 才会暴露命名空间、CDATA、
/// 意料之外的字段顺序这类问题。样本文件是按原样保存的线上响应。
@Suite("FeedParser 真实样本")
struct FeedParserRealFeedTests {
    @Test func parsesHackerNewsRSS() throws {
        let feed = try FeedParser.parse(try Fixture.data("feed-hn-rss", extension: "xml"))

        #expect(feed.title == "Hacker News")
        #expect(feed.items.count == 30)

        // 每一条都应该拿到标题、标识、链接与时间，不能出现整批字段丢失。
        for item in feed.items {
            #expect(item.title.isEmpty == false)
            #expect(item.identifier.isEmpty == false)
            #expect(item.link != nil)
            #expect(item.publishedAt != nil)
        }
    }

    @Test func parsesXkcdAtom() throws {
        let feed = try FeedParser.parse(try Fixture.data("feed-xkcd-atom", extension: "xml"))

        #expect(feed.title == "xkcd.com")
        #expect(feed.items.count == 4)

        let item = try #require(feed.items.first)
        #expect(item.identifier.isEmpty == false)
        #expect(item.link?.host == "xkcd.com")
        #expect(item.publishedAt != nil)
    }

    /// Atom 的 entry 常用 `<link rel="alternate" href=…>`，
    /// 若把自闭合标签当成空文本处理，链接会整批丢失。
    @Test func keepsEveryAtomLink() throws {
        let feed = try FeedParser.parse(try Fixture.data("feed-xkcd-atom", extension: "xml"))

        for item in feed.items {
            #expect(item.link != nil)
        }
    }
}
