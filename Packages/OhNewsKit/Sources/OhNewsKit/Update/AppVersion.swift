// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 语义化版本号。
///
/// 只比较数字段，忽略 `v` 前缀与预发布后缀（`-beta.1` 之类）：用来自动判断
/// 「远端是不是比本地新」，不需要处理预发布的完整排序规则。
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// 解析版本字符串。`v0.6.0`、`0.6.0`、`0.6` 都接受；段数不足按 0 补。
    /// 解析不出数字时返回 nil，调用方据此安静地放弃这次检查。
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed = String(trimmed.dropFirst())
        }
        // 去掉预发布与构建元数据：1.2.3-beta.1+5 → 1.2.3
        if let cut = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            trimmed = String(trimmed[trimmed.startIndex..<cut])
        }
        guard trimmed.isEmpty == false else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.isEmpty == false else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        guard numbers.isEmpty == false else { return nil }

        self.major = numbers.count > 0 ? numbers[0] : 0
        self.minor = numbers.count > 1 ? numbers[1] : 0
        self.patch = numbers.count > 2 ? numbers[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// 远端最新版本的信息。
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    /// 版本号原文，用于展示（例如 `v0.6.0`）。
    public let tagName: String
    /// 发布页面地址，用户点「查看」时打开。
    public let pageURL: URL

    public init(version: AppVersion, tagName: String, pageURL: URL) {
        self.version = version
        self.tagName = tagName
        self.pageURL = pageURL
    }
}

/// 一次版本检查的结果。
public enum UpdateCheckResult: Equatable, Sendable {
    /// 远端比本地新。
    case newer(ReleaseInfo)
    /// 已经是最新。
    case upToDate
    /// 检查没做成（网络不通、接口变了、本地版本号解析失败等）。
    ///
    /// 与「已是最新」严格区分：这两件事对用户的意义完全不同，前者是确认，
    /// 后者是未知。界面只在真正确认时才说「已是最新」。
    case failed(String)
}

/// GitHub Releases 页面的解析。
///
/// 不解析 HTML，只看地址：`/releases/latest` 会 302 跳到最新版本的 tag 页，
/// 从最终 URL 里取出 tag 即可。
///
/// 用网页端点而不是 API：API 有「每 IP 每小时 60 次」的限额，未认证请求共享
/// 同一个额度，公司或学校网络下的用户会互相影响。这个端点没有限额，
/// 且同样会跳过草稿与预览版。
public enum GitHubReleasePageParser {
    public static func parse(_ url: URL) throws -> ReleaseInfo {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "tag"),
              parts.count > index + 1
        else {
            // 没有 tag 段，说明这个仓库还没有任何发布。
            throw UpdateParseError.notARelease
        }

        let tag = parts[index + 1]
        guard let version = AppVersion(tag) else {
            throw UpdateParseError.malformed
        }

        return ReleaseInfo(version: version, tagName: tag, pageURL: url)
    }
}

public enum UpdateParseError: Error, Equatable {
    /// 应答结构与预期不符。
    case malformed
    /// 还没有可供提示的发布。
    case notARelease
}
