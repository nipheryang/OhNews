import Foundation
import Testing
@testable import OhNewsKit

struct CacheStoreSummaryTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ohnews-summary-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSummary(
        storyID: Int,
        modelName: String = "deepseek-v4-flash",
        promptVersion: String = PromptVersion.current
    ) -> StorySummary {
        StorySummary(
            storyID: storyID,
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
        await store.storeSummary(makeSummary(storyID: 7))

        let reopened = CacheStore(directory: directory)
        let summary = await reopened.summary(
            storyID: 7,
            promptVersion: PromptVersion.current,
            modelName: "deepseek-v4-flash"
        )

        #expect(summary?.chineseTitle == "中文标题")
        #expect(summary?.tags == ["AI"])
    }

    @Test func invalidatesSummaryOnModelChange() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(storyID: 7))

        let stale = await store.summary(
            storyID: 7,
            promptVersion: PromptVersion.current,
            modelName: "gpt-5-mini"
        )
        #expect(stale == nil)
    }

    @Test func invalidatesSummaryOnPromptVersionChange() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(storyID: 7, promptVersion: "v0"))

        let stale = await store.summary(
            storyID: 7,
            promptVersion: PromptVersion.current,
            modelName: "deepseek-v4-flash"
        )
        #expect(stale == nil)
    }

    @Test func returnsSummariesForRequestedStoriesOnly() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeSummary(makeSummary(storyID: 1))
        await store.storeSummary(makeSummary(storyID: 2))

        let found = await store.summaries(forStoryIDs: [2, 3])

        #expect(found.keys.sorted() == [2])
        #expect(found[2]?.storyID == 2)
    }

    @Test func decodesSnapshotWrittenBeforeSummariesExisted() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 模拟旧版本写出的缓存文件：没有 summaries 字段。
        let legacy = """
        {"stories":{},"listOrder":{"top":[1]},"readIDs":[1],"updatedAt":"2026-09-11T14:28:23Z"}
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let ids = await store.cachedIDs(for: .top)
        let readIDs = await store.readIDs()

        #expect(ids == [1])
        #expect(readIDs == [1])
    }
}
