import Foundation
import Testing
@testable import OhNewsKit

struct CacheStoreSummaryTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ohnews-summary-\(UUID().uuidString)", isDirectory: true)
    }

    private func itemID(_ number: Int) -> String {
        SourceIdentifier.itemID(sourceID: HackerNewsSource.sourceID, rawID: String(number))
    }

    private func makeSummary(
        itemNumber: Int,
        modelName: String = "deepseek-v4-flash",
        promptVersion: String = PromptVersion.current
    ) -> StorySummary {
        StorySummary(
            storyID: itemID(itemNumber),
            chineseTitle: "中文标题",
            summary: "摘要内容。",
            tags: ["AI"],
            commentConsensus: "评论有分歧。",
            modelName: modelName,
            promptVersion: promptVersion,
            generatedAt: Date(timeIntervalSince1970: 1_160_418_111)
        )
    }

    @Test func persistsSummaries() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(itemNumber: 7))

        let reopened = CacheStore(directory: directory)
        let summary = await reopened.summary(
            itemID: itemID(7),
            promptVersion: PromptVersion.current,
            modelName: "deepseek-v4-flash"
        )

        #expect(summary?.chineseTitle == "中文标题")
        #expect(summary?.tags == ["AI"])
    }

    @Test func invalidatesSummaryOnModelChange() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(itemNumber: 7))

        let stale = await store.summary(
            itemID: itemID(7),
            promptVersion: PromptVersion.current,
            modelName: "gpt-5-mini"
        )
        #expect(stale == nil)
    }

    @Test func invalidatesSummaryOnPromptVersionChange() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(itemNumber: 7, promptVersion: "v0"))

        let stale = await store.summary(
            itemID: itemID(7),
            promptVersion: PromptVersion.current,
            modelName: "deepseek-v4-flash"
        )
        #expect(stale == nil)
    }

    @Test func returnsSummariesForRequestedItemsOnly() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(itemNumber: 1))
        await store.storeSummary(makeSummary(itemNumber: 2))

        let found = await store.summaries(forItemIDs: [itemID(2), itemID(3)])

        #expect(found.keys.sorted() == [itemID(2)])
        #expect(found[itemID(2)]?.storyID == itemID(2))
    }

    /// 当前版本的快照缺少可选字段时，应当能正常解码，而不是丢掉整份缓存。
    @Test func decodesCurrentSnapshotMissingOptionalFields() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = """
        {"schemaVersion":\(CacheStore.currentSchemaVersion),"stories":{},\
        "channelOrder":{"hn:top":["hn:1"]},"readIDs":["hn:1"],\
        "updatedAt":"2026-09-11T14:28:23Z"}
        """
        try Data(snapshot.utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let ids = await store.cachedItemIDs(forChannel: HackerNewsSource.channelID(for: .top))
        let readIDs = await store.readIDs()

        #expect(ids == [itemID(1)])
        #expect(readIDs == [itemID(1)])
    }
}
