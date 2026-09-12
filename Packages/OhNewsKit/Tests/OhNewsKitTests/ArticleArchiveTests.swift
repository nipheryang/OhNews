// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("Article Archive")
struct ArticleArchiveTests {
    private func makeStore() -> (ArchiveStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsArchiveTests-\(UUID().uuidString)", isDirectory: true)
        return (ArchiveStore(directory: dir), dir)
    }

    private func story(_ id: String = "hn:49670032") -> Story {
        Story(
            id: id,
            sourceID: "hn",
            title: "A decade of database migrations",
            url: URL(string: "https://blog.example.com/migrations"),
            score: 412,
            author: "zdw",
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            commentCount: 128,
            type: .story,
            text: nil
        )
    }

    private func archive(
        _ id: String = "hn:49670032",
        translation: ArchivedTranslation? = nil,
        showsTranslation: Bool = false
    ) -> ArticleArchive {
        ArticleArchive(
            itemID: id,
            story: story(id),
            archivedAt: Date(timeIntervalSince1970: 1_700_001_000),
            bodyKind: .article,
            article: Article(
                title: "A decade of database migrations",
                byline: "zdw",
                siteName: "blog.example.com",
                html: "<p>我们最后悔的一件事，是把迁移当成一次性的项目。</p>",
                textLength: 4200,
                sourceURL: URL(string: "https://blog.example.com/migrations")
            ),
            discussionHTML: "<div class=\"comment\">第一层评论</div>",
            translation: translation,
            showsTranslation: showsTranslation,
            summary: StorySummary(
                storyID: id,
                chineseTitle: "数据库迁移的十年",
                summary: "作者回顾了十年的迁移经验。",
                tags: ["数据库"],
                commentConsensus: nil,
                modelName: "deepseek-v4-flash",
                promptVersion: "v2",
                generatedAt: Date(timeIntervalSince1970: 1_700_000_500)
            )
        )
    }

    // MARK: - 往返

    @Test("存下再读回来，内容一致")
    func roundTrip() async {
        let (store, _) = makeStore()
        let original = archive()
        await store.save(original)

        let loaded = await store.archive(itemID: original.itemID)
        #expect(loaded == original)
    }

    @Test("正文、讨论区、摘要都能读回来")
    func roundTripKeepsEverything() async {
        let (store, _) = makeStore()
        await store.save(archive())

        let loaded = await store.archive(itemID: "hn:49670032")
        #expect(loaded?.article?.html.contains("迁移") == true)
        #expect(loaded?.discussionHTML?.contains("第一层评论") == true)
        #expect(loaded?.summary?.chineseTitle == "数据库迁移的十年")
        #expect(loaded?.story.author == "zdw")
    }

    @Test("译文与显示状态一起保留")
    func keepsTranslationAndState() async {
        let (store, _) = makeStore()
        let translation = ArchivedTranslation(
            title: "数据库迁移的十年",
            articleHTML: "<p>译文正文</p>",
            discussionHTML: "<div>译文评论</div>"
        )
        await store.save(archive(translation: translation, showsTranslation: true))

        let loaded = await store.archive(itemID: "hn:49670032")
        #expect(loaded?.translation?.articleHTML == "<p>译文正文</p>")
        #expect(loaded?.translation?.discussionHTML == "<div>译文评论</div>")
        #expect(loaded?.showsTranslation == true)
    }

    @Test("没读过的内容读回来是 nil")
    func missingArchiveIsNil() async {
        let (store, _) = makeStore()
        #expect(await store.archive(itemID: "hn:404") == nil)
        #expect(await store.contains(itemID: "hn:404") == false)
    }

    @Test("重新存档会覆盖旧的")
    func saveOverwrites() async {
        let (store, _) = makeStore()
        await store.save(archive())
        await store.save(archive(translation: ArchivedTranslation(
            title: "后来翻的",
            articleHTML: "<p>后来翻的正文</p>",
            discussionHTML: nil
        )))

        let loaded = await store.archive(itemID: "hn:49670032")
        #expect(loaded?.translation?.title == "后来翻的")
    }

    // MARK: - 形态

    @Test("自述帖与降级也能存档")
    func storesOtherBodyKinds() async {
        let (store, _) = makeStore()
        let selfPost = ArticleArchive(
            itemID: "hn:1",
            story: story("hn:1"),
            archivedAt: Date(),
            bodyKind: .selfPost,
            selfPostHTML: "<p>Ask HN: 你们怎么做迁移？</p>"
        )
        let degraded = ArticleArchive(
            itemID: "hn:2",
            story: story("hn:2"),
            archivedAt: Date(),
            bodyKind: .degraded,
            degradedLevel: .titleAndComments
        )
        await store.save(selfPost)
        await store.save(degraded)

        #expect(await store.archive(itemID: "hn:1")?.selfPostHTML?.contains("Ask HN") == true)
        #expect(await store.archive(itemID: "hn:2")?.degradedLevel == .titleAndComments)
    }

    @Test("hasBody 只在真存到正文时为真")
    func hasBodyReflectsContent() {
        #expect(archive().hasBody)

        let degraded = ArticleArchive(
            itemID: "hn:2",
            story: story("hn:2"),
            archivedAt: Date(),
            bodyKind: .degraded,
            degradedLevel: .titleOnly
        )
        #expect(degraded.hasBody == false)

        let empty = ArticleArchive(
            itemID: "hn:3",
            story: story("hn:3"),
            archivedAt: Date(),
            bodyKind: .selfPost,
            selfPostHTML: ""
        )
        #expect(empty.hasBody == false)
    }

    // MARK: - 文件名

    @Test("条目 ID 里的冒号不会进文件名")
    func fileNameIsSafe() {
        let name = ArchiveStore.fileName(for: "hn:49670032")
        #expect(name.contains(":") == false)
        #expect(name.hasSuffix(".json"))
    }

    @Test("不同条目 ID 得到不同文件名")
    func fileNameIsUnique() {
        let ids = ["hn:1", "hn:2", "rss:abc", "rss:def", "hn:1.0", "hn-1", "hn_1"]
        let names = ids.map(ArchiveStore.fileName(for:))
        #expect(Set(names).count == ids.count)
    }

    @Test("同一个 ID 永远得到同一个文件名")
    func fileNameIsStable() {
        #expect(ArchiveStore.fileName(for: "rss:a1b2c3") == ArchiveStore.fileName(for: "rss:a1b2c3"))
    }

    @Test("名字里带冒号或斜杠也不会写出目录外")
    func fileNameRejectsPathSeparators() {
        let name = ArchiveStore.fileName(for: "rss:../../etc/passwd")
        #expect(name.contains("/") == false)
        #expect(name.contains("..") == false)
    }

    // MARK: - 管理

    @Test("删除存档")
    func remove() async {
        let (store, _) = makeStore()
        await store.save(archive())
        await store.remove(itemID: "hn:49670032")
        #expect(await store.contains(itemID: "hn:49670032") == false)
    }

    @Test("列出全部存档")
    func listsAll() async {
        let (store, _) = makeStore()
        await store.save(archive("hn:1"))
        await store.save(archive("rss:abc"))

        let ids = Set(await store.itemIDs())
        #expect(ids == ["hn:1", "rss:abc"])
    }

    @Test("统计占用与清空")
    func sizeAndClear() async {
        let (store, _) = makeStore()
        #expect(await store.totalSizeInBytes() == 0)

        await store.save(archive())
        #expect(await store.totalSizeInBytes() > 0)

        await store.removeAll()
        #expect(await store.totalSizeInBytes() == 0)
        #expect(await store.archive(itemID: "hn:49670032") == nil)
    }

    @Test("存档与缓存、收藏清单分属不同文件")
    func archiveLivesInItsOwnDirectory() async {
        let (store, dir) = makeStore()
        await store.save(archive())

        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(files.isEmpty == false)
        #expect(files.contains("cache.json") == false)
        #expect(files.contains("library.json") == false)
    }
}
