// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 从外链页面抽取出来的正文。
public struct Article: Codable, Hashable, Sendable {
    public let title: String?
    public let byline: String?
    public let siteName: String?
    /// 已清理过脚本与事件属性的正文 HTML。
    public let html: String
    /// Readability 统计的正文纯文本长度，用来判断抽取质量。
    public let textLength: Int
    public let sourceURL: URL?

    public init(
        title: String?,
        byline: String?,
        siteName: String?,
        html: String,
        textLength: Int,
        sourceURL: URL?
    ) {
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.html = html
        self.textLength = textLength
        self.sourceURL = sourceURL
    }
}
