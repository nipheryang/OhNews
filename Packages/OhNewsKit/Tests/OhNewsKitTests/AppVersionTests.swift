// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("App Version")
struct AppVersionTests {
    @Test("解析常规版本号")
    func parsesPlainVersions() {
        #expect(AppVersion("0.6.0") == AppVersion(major: 0, minor: 6, patch: 0))
        #expect(AppVersion("1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("带 v 前缀也能解析")
    func parsesTagWithPrefix() {
        #expect(AppVersion("v0.6.0") == AppVersion(major: 0, minor: 6, patch: 0))
        #expect(AppVersion("V0.6.0") == AppVersion(major: 0, minor: 6, patch: 0))
    }

    @Test("段数不足按 0 补")
    func padsMissingComponents() {
        #expect(AppVersion("1") == AppVersion(major: 1, minor: 0, patch: 0))
        #expect(AppVersion("1.2") == AppVersion(major: 1, minor: 2, patch: 0))
    }

    @Test("丢掉预发布与构建元数据")
    func stripsSuffixes() {
        #expect(AppVersion("v1.2.3-beta.1") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("1.2.3+build.5") == AppVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("解析不了时返回 nil")
    func rejectsGarbage() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("v1.x.0") == nil)
        #expect(AppVersion("-1.0.0") == nil)
    }

    @Test("按数字段比较，不是字符串比较")
    func comparesNumerically() {
        // 字符串比较会把 "0.10.0" 排在 "0.9.0" 前面，这正是要避免的。
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!)
        #expect(AppVersion("0.9.0")! < AppVersion("0.10.0")!)
        #expect(AppVersion("0.6.0")! > AppVersion("0.5.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.6.0")! == AppVersion("v0.6.0")!)
    }

    @Test("展示形式是点分三段")
    func describesCleanly() {
        #expect(AppVersion("v0.6.0")!.description == "0.6.0")
        #expect(AppVersion("1")!.description == "1.0.0")
    }
}

@Suite("GitHub Release Page Parser")
struct GitHubReleasePageParserTests {
    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test("从 tag 页地址取出版本")
    func parsesTagPage() throws {
        let info = try GitHubReleasePageParser.parse(
            url("https://github.com/nipheryang/OhNews/releases/tag/v0.6.0")
        )
        #expect(info.version == AppVersion(major: 0, minor: 6, patch: 0))
        #expect(info.tagName == "v0.6.0")
        #expect(info.pageURL.absoluteString.hasSuffix("/releases/tag/v0.6.0"))
    }

    @Test("带前缀与后缀的 tag 也能解析")
    func parsesDecoratedTag() throws {
        let info = try GitHubReleasePageParser.parse(
            url("https://github.com/x/y/releases/tag/v1.2.3-rc.1")
        )
        #expect(info.version == AppVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("停在发布列表页说明还没有发布")
    func rejectsReleaseListPage() throws {
        // /releases/latest 在无发布时不会跳到 tag 页，而是留在列表页。
        #expect(throws: UpdateParseError.notARelease) {
            try GitHubReleasePageParser.parse(url("https://github.com/nipheryang/OhNews/releases"))
        }
    }

    @Test("tag 不像版本号时抛错")
    func rejectsNonVersionTag() throws {
        #expect(throws: UpdateParseError.malformed) {
            try GitHubReleasePageParser.parse(url("https://github.com/x/y/releases/tag/nightly"))
        }
    }
}
