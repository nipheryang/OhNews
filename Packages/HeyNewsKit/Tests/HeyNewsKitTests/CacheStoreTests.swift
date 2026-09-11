import Foundation
import Testing
@testable import HeyNewsKit

struct CacheStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("heynews-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// 用整秒时间戳，避免 ISO8601 编码丢失亚秒精度导致断言不稳定。
    private func makeStory(id: Int, title: String = "示例标题") -> Story {
        Story(
            id: id,
            title: title,
            url: URL(string: "https://example.com/\(id)"),
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
        let story = makeStory(id: 101)

        let store = CacheStore(directory: directory)
        await store.storeStories([story])
        await store.storeListIDs([101, 102], for: .top)

        let reopened = CacheStore(directory: directory)
        let cached = await reopened.story(id: 101)
        let ids = await reopened.cachedIDs(for: .top)

        #expect(cached == story)
        #expect(ids == [101, 102])
    }

    @Test func returnsCachedStoriesInListOrder() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([makeStory(id: 1), makeStory(id: 2), makeStory(id: 3)])
        await store.storeListIDs([3, 1, 2], for: .best)

        let cached = await store.cachedStories(for: .best, limit: 2)
        #expect(cached.map(\.id) == [3, 1])
    }

    @Test func skipsUnknownIDsInListOrder() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([makeStory(id: 5)])
        await store.storeListIDs([999, 5], for: .new)

        let cached = await store.cachedStories(for: .new, limit: 10)
        #expect(cached.map(\.id) == [5])
    }

    @Test func persistsReadState() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.markRead(7)
        await store.markRead(7)
        await store.markRead(8)
        await store.markUnread(8)

        let reopened = CacheStore(directory: directory)
        let isSevenRead = await reopened.isRead(7)
        let isEightRead = await reopened.isRead(8)
        let readIDs = await reopened.readIDs()

        #expect(isSevenRead)
        #expect(isEightRead == false)
        #expect(readIDs == [7])
    }

    @Test func clearRemovesEverything() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)

        await store.storeStories([makeStory(id: 1)])
        await store.storeListIDs([1], for: .show)
        await store.markRead(1)
        await store.clear()

        let stories = await store.cachedStories(for: .show, limit: 10)
        let readIDs = await store.readIDs()

        #expect(stories.isEmpty)
        #expect(readIDs.isEmpty)
    }

    @Test func toleratesCorruptedCacheFile() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let stories = await store.cachedStories(for: .top, limit: 10)

        #expect(stories.isEmpty)
    }
}
