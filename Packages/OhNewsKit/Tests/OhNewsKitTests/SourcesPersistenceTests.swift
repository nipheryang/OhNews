import Foundation
import Testing
@testable import OhNewsKit

@Suite("SourcesPersistence")
struct SourcesPersistenceTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ohnews-sources-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSource(_ host: String) throws -> NewsSource {
        let url = try #require(URL(string: "https://\(host)/feed"))
        return NewsSource(
            id: SourceIdentifier.rssSourceID(feedURL: url),
            kind: .rss,
            name: host,
            feedURL: url
        )
    }

    @Test func startsEmpty() async throws {
        let store = SourcesPersistence(directory: makeTempDirectory())
        #expect(await store.all().isEmpty)
    }

    @Test func persistsAcrossInstances() async throws {
        let directory = makeTempDirectory()
        let source = try makeSource("a.example.com")

        let store = SourcesPersistence(directory: directory)
        await store.upsert(source)

        let reopened = SourcesPersistence(directory: directory)
        let all = await reopened.all()
        #expect(all.count == 1)
        #expect(all.first?.name == "a.example.com")
        #expect(all.first?.feedURL == source.feedURL)
    }

    /// 重复添加同一个 feed 应当更新而不是产生第二条记录。
    @Test func upsertReplacesSameIDInsteadOfDuplicating() async throws {
        let store = SourcesPersistence(directory: makeTempDirectory())
        let url = try #require(URL(string: "https://a.example.com/feed"))

        let first = NewsSource(
            id: SourceIdentifier.rssSourceID(feedURL: url),
            kind: .rss,
            name: "抓取前的占位名",
            feedURL: url
        )
        let renamed = NewsSource(
            id: SourceIdentifier.rssSourceID(feedURL: url),
            kind: .rss,
            name: "抓取后的 feed 标题",
            feedURL: url
        )

        await store.upsert(first)
        await store.upsert(renamed)

        let all = await store.all()
        #expect(all.count == 1)
        #expect(all.first?.name == "抓取后的 feed 标题")
    }

    @Test func removesSource() async throws {
        let store = SourcesPersistence(directory: makeTempDirectory())
        let first = try makeSource("a.example.com")
        let second = try makeSource("b.example.com")

        await store.upsert(first)
        await store.upsert(second)
        await store.remove(id: first.id)

        let all = await store.all()
        #expect(all.map(\.id) == [second.id])
    }

    @Test func toleratesCorruptedFile() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("sources.json"))

        let store = SourcesPersistence(directory: directory)
        #expect(await store.all().isEmpty)
    }
}
