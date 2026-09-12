// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

struct CacheStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ohnews-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func itemID(_ number: Int) -> String {
        SourceIdentifier.itemID(sourceID: HackerNewsSource.sourceID, rawID: String(number))
    }

    private func channelID(_ list: StoryList) -> String {
        HackerNewsSource.channelID(for: list)
    }

    /// 用整秒时间戳，避免 ISO8601 编码丢失亚秒精度导致断言不稳定。
    private func makeStory(number: Int, title: String = "示例标题") -> Story {
        Story(
            id: itemID(number),
            sourceID: HackerNewsSource.sourceID,
            title: title,
            url: URL(string: "https://example.com/\(number)"),
            score: 42,
            author: "nipher",
            postedAt: Date(timeIntervalSince1970: 1_160_418_111),
            commentCount: 7,
            type: .story,
            text: nil
        )
    }

    @Test func roundTripsStoriesAcrossInstances() async throws {
        let directory = makeTempDirectory()
        let story = makeStory(number: 101)

        let store = CacheStore(directory: directory)
        await store.storeStories([story])
        await store.storeItemIDs([itemID(101), itemID(102)], forChannel: channelID(.top))

        let reopened = CacheStore(directory: directory)
        let cached = await reopened.story(id: itemID(101))
        let ids = await reopened.cachedItemIDs(forChannel: channelID(.top))

        #expect(cached == story)
        #expect(ids == [itemID(101), itemID(102)])
    }

    @Test func returnsCachedStoriesInChannelOrder() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([
            makeStory(number: 1),
            makeStory(number: 2),
            makeStory(number: 3)
        ])
        await store.storeItemIDs(
            [itemID(3), itemID(1), itemID(2)],
            forChannel: channelID(.best)
        )

        let cached = await store.cachedStories(forChannel: channelID(.best), limit: 2)
        #expect(cached.map(\.id) == [itemID(3), itemID(1)])
    }

    @Test func skipsUnknownIDsInChannelOrder() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([makeStory(number: 5)])
        await store.storeItemIDs([itemID(999), itemID(5)], forChannel: channelID(.new))

        let cached = await store.cachedStories(forChannel: channelID(.new), limit: 10)
        #expect(cached.map(\.id) == [itemID(5)])
    }

    @Test func persistsReadState() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.markRead(itemID(7))
        await store.markRead(itemID(7))
        await store.markRead(itemID(8))
        await store.markUnread(itemID(8))

        let reopened = CacheStore(directory: directory)
        let isSevenRead = await reopened.isRead(itemID(7))
        let isEightRead = await reopened.isRead(itemID(8))
        let readIDs = await reopened.readIDs()

        #expect(isSevenRead)
        #expect(isEightRead == false)
        #expect(readIDs == [itemID(7)])
    }

    @Test func clearRemovesEverything() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([makeStory(number: 1)])
        await store.storeItemIDs([itemID(1)], forChannel: channelID(.show))
        await store.markRead(itemID(1))
        await store.clear()

        let stories = await store.cachedStories(forChannel: channelID(.show), limit: 10)
        let readIDs = await store.readIDs()

        #expect(stories.isEmpty)
        #expect(readIDs.isEmpty)
    }

    @Test func toleratesCorruptedCacheFile() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let stories = await store.cachedStories(forChannel: channelID(.top), limit: 10)

        #expect(stories.isEmpty)
    }

    /// 0.1.0 的缓存结构里条目 ID 是纯数字、频道键是榜单名。
    /// 升级后内容无法迁移，但已读记录必须保留下来。
    @Test func migratesReadStateFromLegacySnapshot() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = """
        {"stories":{"7":{"id":7}},"listOrder":{"top":[7,8]},"readIDs":[7,8],\
        "summaries":{},"updatedAt":"2026-09-11T14:28:23Z"}
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let readIDs = await store.readIDs()
        let items = await store.cachedItemIDs(forChannel: channelID(.top))
        let story = await store.story(id: itemID(7))

        #expect(readIDs == [itemID(7), itemID(8)])
        // 旧内容没有源信息，无法迁移，因此被丢弃而不是留下半成品。
        #expect(items.isEmpty)
        #expect(story == nil)
    }

    @Test func reportsCacheFileSize() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        // 还没有写过任何东西时没有文件，报 0。
        let empty = await store.cacheSizeInBytes()
        #expect(empty == 0)

        await store.storeStories([makeStory(number: 1)])
        let filled = await store.cacheSizeInBytes()
        #expect(filled > 0)
    }
}
