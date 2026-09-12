// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import OhNewsKit

@Suite("HackerNewsSource")
struct HackerNewsSourceTests {
    @Test func mapsStoryListsToChannelIDs() {
        for list in StoryList.allCases {
            let channelID = HackerNewsSource.channelID(for: list)
            #expect(channelID == "hn:\(list.rawValue)")
            #expect(HackerNewsSource.list(forChannelID: channelID) == list)
        }
    }

    @Test func returnsNilForForeignChannel() {
        #expect(HackerNewsSource.list(forChannelID: "rss:9a1f2b3c") == nil)
        #expect(HackerNewsSource.list(forChannelID: "top") == nil)
        #expect(HackerNewsSource.list(forChannelID: "") == nil)
    }

    @Test func buildsItemID() {
        #expect(HackerNewsSource.itemID(for: 42) == "hn:42")
    }

    @Test func readsNumericIDBack() {
        #expect(HackerNewsSource.numericID(fromItemID: "hn:12345") == 12345)
        #expect(HackerNewsSource.numericID(fromItemID: "hn:42") == 42)
    }

    @Test func rejectsUnknownIdentifiers() {
        // 非 HN 来源、非数字后缀、以及频道 ID 都不应该被当成条目 ID。
        #expect(HackerNewsSource.numericID(fromItemID: "rss:9a1f2b3c") == nil)
        #expect(HackerNewsSource.numericID(fromItemID: "hn:abc") == nil)
        #expect(HackerNewsSource.numericID(fromItemID: "hn:top") == nil)
        #expect(HackerNewsSource.numericID(fromItemID: "12345") == nil)
    }

    @Test func exposesBuiltInSource() {
        #expect(HackerNewsSource.source.id == "hn")
        #expect(HackerNewsSource.source.kind == .hackerNews)
        #expect(HackerNewsSource.source.feedURL == nil)
    }
}
