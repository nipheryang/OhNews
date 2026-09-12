// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

/// 内容哈希。
///
/// 译文缓存靠它判断「正文是否还是当初翻译的那一份」：同一条目可能先抽到摘要版
/// 正文、重抓后拿到完整版，哈希一变旧译文就该作废。
public enum ContentHash {
    /// 完整 SHA-256（64 个十六进制字符）。这里不截短，避免不同文章撞上同一哈希。
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
