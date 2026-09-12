// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

@Suite("CacheStore 译文")
struct CacheStoreTranslationTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ohnews-translation-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeTranslation(
        itemID: String = "hn:1",
        contentHash: String = "hash-a",
        modelName: String = "deepseek-v4-flash",
        version: String = TranslationVersion.current,
        title: String? = "中文标题",
        html: String = "<p>译文</p>",
        discussionHTML: String? = "<p>译文讨论</p>"
    ) -> ArticleTranslation {
        ArticleTranslation(
            itemID: itemID,
            contentHash: contentHash,
            modelName: modelName,
            version: version,
            title: title,
            html: html,
            discussionHTML: discussionHTML,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    @Test func roundTripsTranslation() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeTranslation(makeTranslation())

        let reopened = CacheStore(directory: directory)
        let found = await reopened.translation(
            itemID: "hn:1",
            contentHash: "hash-a",
            modelName: "deepseek-v4-flash",
            version: TranslationVersion.current
        )

        #expect(found?.html == "<p>译文</p>")
        // 标题与讨论区也要完整往返，不能只存正文。
        #expect(found?.title == "中文标题")
        #expect(found?.discussionHTML == "<p>译文讨论</p>")
    }

    @Test func toleratesMissingOptionalParts() async throws {
        let directory = makeTempDirectory()
        let store = CacheStore(directory: directory)
        await store.storeTranslation(makeTranslation(title: nil, discussionHTML: nil))

        let reopened = CacheStore(directory: directory)
        let found = await reopened.translation(
            itemID: "hn:1",
            contentHash: "hash-a",
            modelName: "deepseek-v4-flash",
            version: TranslationVersion.current
        )

        #expect(found?.title == nil)
        #expect(found?.discussionHTML == nil)
    }

    /// 正文变了（先抽到摘要版、后抓到完整版）旧译文必须作废。
    @Test func invalidatesWhenContentChanged() async throws {
        let store = CacheStore(directory: makeTempDirectory())
        await store.storeTranslation(makeTranslation(contentHash: "hash-a"))

        let stale = await store.translation(
            itemID: "hn:1",
            contentHash: "hash-b",
            modelName: "deepseek-v4-flash",
            version: TranslationVersion.current
        )

        #expect(stale == nil)
    }

    @Test func invalidatesOnModelChange() async throws {
        let store = CacheStore(directory: makeTempDirectory())
        await store.storeTranslation(makeTranslation(modelName: "deepseek-v4-flash"))

        let stale = await store.translation(
            itemID: "hn:1",
            contentHash: "hash-a",
            modelName: "gpt-5-mini",
            version: TranslationVersion.current
        )

        #expect(stale == nil)
    }

    @Test func invalidatesOnVersionChange() async throws {
        let store = CacheStore(directory: makeTempDirectory())
        await store.storeTranslation(makeTranslation(version: "t0"))

        let stale = await store.translation(
            itemID: "hn:1",
            contentHash: "hash-a",
            modelName: "deepseek-v4-flash",
            version: TranslationVersion.current
        )

        #expect(stale == nil)
    }

    @Test func keepsTranslationsForDifferentItems() async throws {
        let store = CacheStore(directory: makeTempDirectory())
        await store.storeTranslation(makeTranslation(itemID: "hn:1", html: "<p>甲</p>"))
        await store.storeTranslation(makeTranslation(itemID: "hn:2", html: "<p>乙</p>"))

        let first = await store.translation(
            itemID: "hn:1", contentHash: "hash-a",
            modelName: "deepseek-v4-flash", version: TranslationVersion.current
        )
        let second = await store.translation(
            itemID: "hn:2", contentHash: "hash-a",
            modelName: "deepseek-v4-flash", version: TranslationVersion.current
        )

        #expect(first?.html == "<p>甲</p>")
        #expect(second?.html == "<p>乙</p>")
    }

    /// 旧版本的缓存文件里没有 translations 字段，仍要能正常打开。
    @Test func decodesSnapshotWithoutTranslations() async throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = """
        {"schemaVersion":\(CacheStore.currentSchemaVersion),"stories":{},\
        "channelOrder":{},"readIDs":[],"summaries":{},\
        "updatedAt":"2026-09-11T14:28:23Z"}
        """
        try Data(snapshot.utf8).write(to: directory.appendingPathComponent("cache.json"))

        let store = CacheStore(directory: directory)
        let missing = await store.translation(
            itemID: "hn:1", contentHash: "hash-a",
            modelName: "m", version: TranslationVersion.current
        )

        #expect(missing == nil)
    }
}
