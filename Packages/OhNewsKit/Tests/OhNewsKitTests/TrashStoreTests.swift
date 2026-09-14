// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("Trash Store")
struct TrashStoreTests {
    /// 每个用例用独立目录，避免互相干扰。
    private func makeStore() -> (TrashStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhNewsTrashTests-\(UUID().uuidString)", isDirectory: true)
        return (TrashStore(directory: dir), dir)
    }

    private func story(_ id: String, title: String = "标题") -> Story {
        Story(
            id: id,
            sourceID: "hn",
            title: title,
            url: URL(string: "https://example.com/\(id)"),
            score: 10,
            author: "nipher",
            postedAt: Date(timeIntervalSince1970: 0),
            commentCount: 3,
            type: .story,
            text: nil
        )
    }

    private func article(
        _ id: String,
        translatedTitle: String? = nil,
        at time: TimeInterval = 0
    ) -> SavedArticle {
        SavedArticle(
            story: story(id),
            savedAt: Date(timeIntervalSince1970: time),
            translatedTitle: translatedTitle
        )
    }

    private func trashed(
        _ id: String,
        origin: TrashedItem.Origin = .collection,
        article: SavedArticle? = nil,
        page: SavedPage? = nil,
        at time: TimeInterval = 0
    ) -> TrashedItem {
        TrashedItem(
            itemID: id,
            origin: origin,
            article: article,
            page: page,
            deletedAt: Date(timeIntervalSince1970: time)
        )
    }

    // MARK: - 进出

    @Test("放进回收站后能读出来")
    func putAndRead() async {
        let (store, _) = makeStore()
        await store.put(trashed("a", article: article("a")))

        let items = await store.all()
        #expect(items.count == 1)
        #expect(items.first?.itemID == "a")
        #expect(items.first?.origin == .collection)
    }

    @Test("按删除时间倒序")
    func newestFirst() async {
        let (store, _) = makeStore()
        await store.put(trashed("old", at: 100))
        await store.put(trashed("new", at: 200))

        #expect(await store.all().map(\.itemID) == ["new", "old"])
    }

    @Test("同一件东西重复放入只留一条，且刷新删除时间")
    func putReplacesSameItem() async {
        let (store, _) = makeStore()
        await store.put(trashed("a", at: 100))
        await store.put(trashed("a", at: 300))

        let items = await store.all()
        #expect(items.count == 1)
        #expect(items.first?.deletedAt == Date(timeIntervalSince1970: 300))
    }

    @Test("同一篇文章的星标与收藏夹是两条")
    func differentOriginsAreSeparate() async {
        let (store, _) = makeStore()
        await store.put(trashed("a", origin: .collection, article: article("a")))
        await store.put(trashed("a", origin: .savedPage, page: SavedPage(story: story("a"), savedAt: Date())))

        // 用条目 ID 去重会把它们并成一条，那样放回时就不知道该回哪儿了。
        #expect(await store.count() == 2)
    }

    @Test("取出即移除")
    func takeRemoves() async {
        let (store, _) = makeStore()
        await store.put(trashed("a"))

        let taken = await store.take(id: (await store.all()[0]).id)
        #expect(taken?.itemID == "a")
        #expect(await store.count() == 0)
    }

    @Test("取不存在的条目返回 nil，也不改动任何东西")
    func takeMissingIsNil() async {
        let (store, _) = makeStore()
        await store.put(trashed("a"))

        #expect(await store.take(id: "不存在") == nil)
        #expect(await store.count() == 1)
    }

    @Test("彻底删除一条")
    func removeOne() async {
        let (store, _) = makeStore()
        await store.put(trashed("a"))
        await store.put(trashed("b"))

        await store.remove(id: (await store.all().first { $0.itemID == "a" })!.id)
        #expect(await store.all().map(\.itemID) == ["b"])
    }

    @Test("清空")
    func removeAll() async {
        let (store, _) = makeStore()
        await store.put(trashed("a"))
        await store.put(trashed("b"))

        await store.removeAll()
        #expect(await store.count() == 0)
    }

    // MARK: - 过期

    @Test("只清掉早于截止时间的条目")
    func removesOnlyExpired() async {
        let (store, _) = makeStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tenDaysAgo = now.addingTimeInterval(-10 * 24 * 60 * 60)

        await store.put(trashed("old", at: tenDaysAgo.timeIntervalSince1970))
        await store.put(trashed("new", at: now.timeIntervalSince1970))

        let removed = await store.removeItems(deletedBefore: now.addingTimeInterval(-7 * 24 * 60 * 60))
        #expect(removed == 1)
        #expect(await store.all().map(\.itemID) == ["new"])
    }

    @Test("没有过期的条目时不做改动")
    func nothingExpired() async {
        let (store, _) = makeStore()
        await store.put(trashed("a", at: 1_000_000))

        #expect(await store.removeItems(deletedBefore: Date(timeIntervalSince1970: 0)) == 0)
        #expect(await store.count() == 1)
    }

    // MARK: - 落盘

    @Test("重新打开仍然读得到")
    func survivesReload() async {
        let (store, dir) = makeStore()
        await store.put(trashed("a", article: article("a", translatedTitle: "译文标题")))

        let reopened = TrashStore(directory: dir)
        let items = await reopened.all()
        #expect(items.count == 1)
        #expect(items.first?.article?.translatedTitle == "译文标题")
    }

    @Test("来源是收藏夹时带的是单篇快照")
    func keepsPageSnapshot() async {
        let (store, dir) = makeStore()
        await store.put(trashed("p", origin: .savedPage, page: SavedPage(story: story("p"), savedAt: Date())))

        let reopened = TrashStore(directory: dir)
        let item = await reopened.all().first
        #expect(item?.page?.story.id == "p")
        #expect(item?.article == nil)
    }

    // MARK: - 显示

    @Test("标题优先用译文标题")
    func titlePrefersTranslation() {
        let withTranslation = trashed("a", article: article("a", translatedTitle: "译文"))
        #expect(withTranslation.title == "译文")

        let without = trashed("b", article: article("b"))
        #expect(without.title == "标题")
    }

    // MARK: - 保留档位

    private func makeDefaults() -> UserDefaults {
        let suite = "OhNewsTrashPrefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("默认 30 天，且不写回磁盘")
    func defaultRetentionIsThirtyDays() {
        let defaults = makeDefaults()
        let prefs = TrashPreferences(defaults: defaults)

        #expect(prefs.retention == .thirtyDays)
        #expect(defaults.object(forKey: "trash.retention") == nil)
    }

    @Test("存进去的档位能读回来")
    func retentionRoundTrip() {
        let defaults = makeDefaults()
        var prefs = TrashPreferences(defaults: defaults)
        prefs.retention = .manual

        #expect(TrashPreferences(defaults: defaults).retention == .manual)
    }

    @Test("认不出来的档位回落到默认值")
    func invalidRetentionFallsBack() {
        let defaults = makeDefaults()
        defaults.set("99d", forKey: "trash.retention")

        #expect(TrashPreferences(defaults: defaults).retention == .thirtyDays)
    }

    @Test("手动清空时算不出截止时间")
    func manualHasNoCutoff() {
        let defaults = makeDefaults()
        var prefs = TrashPreferences(defaults: defaults)

        prefs.retention = .manual
        #expect(prefs.cutoff() == nil)

        prefs.retention = .sevenDays
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(prefs.cutoff(now: now) == now.addingTimeInterval(-7 * 24 * 60 * 60))
    }
}
