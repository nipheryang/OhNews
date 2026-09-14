// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("Library Store")
struct LibraryStoreTests {
    /// 每个用例用独立目录，避免互相干扰。
    private func makeStore() -> (LibraryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsLibraryTests-\(UUID().uuidString)", isDirectory: true)
        return (LibraryStore(directory: dir), dir)
    }

    private func article(_ id: String, at time: TimeInterval = 0) -> SavedArticle {
        SavedArticle(
            story: Story(
                id: id,
                sourceID: "hn",
                title: "标题 \(id)",
                url: URL(string: "https://example.com/\(id)"),
                score: 10,
                author: "nipher",
                postedAt: Date(timeIntervalSince1970: time),
                commentCount: 3,
                type: .story,
                text: nil
            ),
            savedAt: Date(timeIntervalSince1970: time)
        )
    }

    private func passage(
        _ text: String,
        itemID: String = "hn:1",
        paragraph: Int = 0,
        at time: TimeInterval = 0
    ) -> SavedPassage {
        SavedPassage(
            itemID: itemID,
            articleTitle: "标题 \(itemID)",
            text: text,
            paragraphIndex: paragraph,
            savedAt: Date(timeIntervalSince1970: time)
        )
    }

    // MARK: - 文章级

    @Test("收藏与稍后读互不影响")
    func kindsAreIndependent() async {
        let (store, _) = makeStore()
        await store.addArticle(article("a"), kind: .collection)

        #expect(await store.containsArticle(itemID: "a", kind: .collection))
        #expect(await store.containsArticle(itemID: "a", kind: .readLater) == false)
        #expect(await store.articles(.readLater).isEmpty)
    }

    @Test("同一篇文章同时进收藏和稍后读")
    func sameArticleInBothKinds() async {
        let (store, _) = makeStore()
        await store.addArticle(article("a"), kind: .collection)
        await store.addArticle(article("a"), kind: .readLater)

        #expect(await store.articles(.collection).count == 1)
        #expect(await store.articles(.readLater).count == 1)
    }

    @Test("重复加入不产生重复项，只刷新时间")
    func addingTwiceRefreshesInsteadOfDuplicating() async {
        let (store, _) = makeStore()
        await store.addArticle(article("a", at: 100), kind: .collection)
        await store.addArticle(article("a", at: 200), kind: .collection)

        let items = await store.articles(.collection)
        #expect(items.count == 1)
        #expect(items.first?.savedAt == Date(timeIntervalSince1970: 200))
    }

    @Test("切换返回切换后的状态")
    func toggleReportsNewState() async {
        let (store, _) = makeStore()
        #expect(await store.toggleArticle(article("a"), kind: .collection))
        #expect(await store.toggleArticle(article("a"), kind: .collection) == false)
        #expect(await store.articles(.collection).isEmpty)
    }

    @Test("列表按保存时间倒序")
    func articlesAreNewestFirst() async {
        let (store, _) = makeStore()
        await store.addArticle(article("old", at: 100), kind: .readLater)
        await store.addArticle(article("new", at: 300), kind: .readLater)
        await store.addArticle(article("mid", at: 200), kind: .readLater)

        #expect(await store.articles(.readLater).map(\.id) == ["new", "mid", "old"])
    }

    // MARK: - 段落级

    @Test("保存的段落去掉首尾空白")
    func passageIsTrimmed() async {
        let (store, _) = makeStore()
        let saved = await store.addPassage(passage("  一段正文  "))
        #expect(saved?.text == "一段正文")
    }

    @Test("空白段落不被保存")
    func emptyPassageRejected() async {
        let (store, _) = makeStore()
        #expect(await store.addPassage(passage("   \n  ")) == nil)
        #expect(await store.allPassages().isEmpty)
    }

    @Test("超过长度上限的段落不被保存")
    func tooLongPassageRejected() async {
        let (store, _) = makeStore()
        let long = String(repeating: "字", count: LibraryStore.maxPassageLength + 1)
        #expect(await store.addPassage(passage(long)) == nil)
    }

    @Test("同一篇文章的同一段文字不重复收藏")
    func duplicatePassageRejected() async {
        let (store, _) = makeStore()
        #expect(await store.addPassage(passage("同一段")) != nil)
        #expect(await store.addPassage(passage("同一段")) == nil)
        #expect(await store.allPassages().count == 1)
    }

    @Test("不同文章的相同文字可以各自收藏")
    func sameTextDifferentArticles() async {
        let (store, _) = makeStore()
        #expect(await store.addPassage(passage("同一段", itemID: "hn:1")) != nil)
        #expect(await store.addPassage(passage("同一段", itemID: "hn:2")) != nil)
        #expect(await store.allPassages().count == 2)
    }

    @Test("按文章筛选段落")
    func passagesForArticle() async {
        let (store, _) = makeStore()
        await store.addPassage(passage("A", itemID: "hn:1"))
        await store.addPassage(passage("B", itemID: "hn:1"))
        await store.addPassage(passage("C", itemID: "hn:2"))

        #expect(await store.passages(itemID: "hn:1").count == 2)
        #expect(await store.passages(itemID: "hn:2").count == 1)
    }

    @Test("删除段落收藏")
    func removePassage() async {
        let (store, _) = makeStore()
        let saved = await store.addPassage(passage("一段正文"))
        await store.removePassage(id: saved!.id)
        #expect(await store.allPassages().isEmpty)
    }

    // MARK: - 持久化

    @Test("重新打开后内容还在")
    func persistsAcrossLoads() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsLibraryPersist-\(UUID().uuidString)", isDirectory: true)

        let first = LibraryStore(directory: dir)
        await first.addArticle(article("a", at: 100), kind: .collection)
        await first.addArticle(article("b", at: 200), kind: .readLater)
        await first.addPassage(passage("一段正文", paragraph: 7))

        let second = LibraryStore(directory: dir)
        #expect(await second.articles(.collection).map(\.id) == ["a"])
        #expect(await second.articles(.readLater).map(\.id) == ["b"])

        let passages = await second.allPassages()
        #expect(passages.count == 1)
        #expect(passages.first?.text == "一段正文")
        #expect(passages.first?.paragraphIndex == 7)
    }

    @Test("收藏保留完整条目，重启后仍可阅读")
    func articleKeepsFullStory() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsLibraryStory-\(UUID().uuidString)", isDirectory: true)

        let first = LibraryStore(directory: dir)
        await first.addArticle(article("hn:1", at: 100), kind: .collection)

        let restored = await LibraryStore(directory: dir).articles(.collection).first?.story
        #expect(restored?.id == "hn:1")
        #expect(restored?.url?.absoluteString == "https://example.com/hn:1")
        #expect(restored?.sourceHost == "example.com")
        #expect(restored?.score == 10)
        #expect(restored?.commentCount == 3)
    }

    @Test("收藏不会写进缓存文件")
    func libraryFileIsSeparate() async {
        let (store, dir) = makeStore()
        await store.addArticle(article("a"), kind: .collection)

        let library = dir.appendingPathComponent("library.json")
        #expect(FileManager.default.fileExists(atPath: library.path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cache.json").path) == false)
    }

    @Test("更新译文标题与摘要，不动保存时间")  
    func updateMetadataKeepsSavedAt() async {
        let (store, _) = makeStore()
        await store.addArticle(article("a", at: 100), kind: .collection)

        await store.updateMetadata(
            itemID: "a",
            translatedTitle: "中文标题",
            summary: StorySummary(
                storyID: "a",
                chineseTitle: "中文标题",
                summary: "摘要",
                tags: [],
                commentConsensus: nil,
                modelName: "m",
                promptVersion: "v2",
                generatedAt: Date(timeIntervalSince1970: 1)
            )
        )

        let item = await store.articles(.collection).first
        #expect(item?.translatedTitle == "中文标题")
        #expect(item?.summary?.chineseTitle == "中文标题")
        // 排序靠 savedAt，不能被改掉。
        #expect(item?.savedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("更新时传 nil 不会抹掉已有的值")
    func updateMetadataIgnoresNil() async {
        let (store, _) = makeStore()
        await store.addArticle(
            SavedArticle(story: article("a").story, savedAt: Date(), translatedTitle: "原有标题"),
            kind: .collection
        )

        await store.updateMetadata(itemID: "a", translatedTitle: nil, summary: nil)
        #expect(await store.articles(.collection).first?.translatedTitle == "原有标题")
    }

    @Test("同一篇同时在收藏与稍后读时，两边都更新")
    func updateMetadataCoversBothKinds() async {
        let (store, _) = makeStore()
        await store.addArticle(article("a"), kind: .collection)
        await store.addArticle(article("a"), kind: .readLater)

        await store.updateMetadata(itemID: "a", translatedTitle: "中文标题", summary: nil)
        #expect(await store.articles(.collection).first?.translatedTitle == "中文标题")
        #expect(await store.articles(.readLater).first?.translatedTitle == "中文标题")
    }

    @Test("清单里的中文信息能存下来")
    func metadataPersists() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsLibraryMeta-\(UUID().uuidString)", isDirectory: true)

        let first = LibraryStore(directory: dir)
        await first.addArticle(
            SavedArticle(
                story: article("a").story,
                savedAt: Date(),
                translatedTitle: "中文标题"
            ),
            kind: .collection
        )

        let restored = await LibraryStore(directory: dir).articles(.collection).first
        #expect(restored?.translatedTitle == "中文标题")
    }

    @Test("旧数据没有这两个字段也能读出来")
    func decodesLegacyWithoutMetadata() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsLibraryLegacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 模拟这两个字段存在之前写下的 library.json。
        let legacy = """
        {"version":1,"collections":[{"savedAt":"2026-09-13T00:00:00Z","story":{"id":"hn:1","sourceID":"hn","title":"T","author":"a","postedAt":"2026-09-13T00:00:00Z","type":"story"}}],"readLater":[],"passages":[]}
        """
        try legacy.data(using: .utf8)?.write(to: dir.appendingPathComponent("library.json"))

        let store = LibraryStore(directory: dir)
        let items = await store.articles(.collection)
        #expect(items.count == 1)
        #expect(items.first?.translatedTitle == nil)
        #expect(items.first?.summary == nil)
    }

    // MARK: - 侧栏入口

    @Test("侧栏入口的选择值不与频道冲突")
    func entryIDsAreNamespaced() {
        for entry in LibraryEntry.allCases {
            #expect(entry.rawValue.hasPrefix("library:"))
            #expect(entry.rawValue.contains(":"))
        }
        #expect(Set(LibraryEntry.allCases.map(\.rawValue)).count == LibraryEntry.allCases.count)
    }

    @Test("选择值能翻译回侧栏入口")
    func matchingEntry() {
        #expect(LibraryEntry.matching("library:collection") == .collection)
        #expect(LibraryEntry.matching("library:readLater") == .readLater)
        #expect(LibraryEntry.matching("hn:top") == nil)
        #expect(LibraryEntry.matching(nil) == nil)
        #expect(LibraryEntry.matching("library:unknown") == nil)
    }

    @Test("只有收藏夹有添加入口")
    func onlySavedPagesHasAddAction() {
        #expect(LibraryEntry.savedPages.addActionTitle != nil)
        #expect(LibraryEntry.collection.addActionTitle == nil)
        #expect(LibraryEntry.readLater.addActionTitle == nil)
    }

    @Test("侧栏入口的顺序就是显示顺序")
    func entryOrderIsStable() {
        // 星标在最前，收藏夹在稍后读之前。
        #expect(LibraryEntry.allCases == [.collection, .savedPages, .readLater])
    }
}