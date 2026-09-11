import CryptoKit
import Foundation

/// 源、频道与条目标识的生成。
///
/// 所有标识都是「源前缀 + 冒号 + 稳定键」，例如 `hn:12345`、`rss:8f3a1c2d…`。
/// 带上源前缀之后，条目 ID 天然全局唯一，已读集合与摘要缓存这类全局结构
/// 不需要再按源分区。
///
/// 哈希一律取 SHA-256 的前 8 字节（16 个十六进制字符）：够短、可读性可接受，
/// 且同一个输入永远得到同一个结果。
public enum SourceIdentifier {
    public static let separator = ":"

    /// 短哈希：SHA-256 前 8 字节。
    public static func shortHash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// 条目 ID，形如 `hn:12345`。
    public static func itemID(sourceID: String, rawID: String) -> String {
        "\(sourceID)\(separator)\(rawID)"
    }

    /// 频道 ID，形如 `hn:top`。
    public static func channelID(sourceID: String, key: String) -> String {
        "\(sourceID)\(separator)\(key)"
    }

    /// RSS 源的 ID：feed 地址的短哈希，保证同一地址重复添加得到同一 ID。
    public static func rssSourceID(feedURL: URL) -> String {
        channelID(sourceID: SourceKind.rss.rawValue, key: shortHash(normalizedFeedKey(feedURL)))
    }

    /// RSS 条目的 ID：feed 地址与条目 GUID（缺失时用链接）的联合哈希。
    public static func rssItemID(feedURL: URL, guid: String) -> String {
        let combined = "\(normalizedFeedKey(feedURL))|\(guid)"
        return itemID(sourceID: rssSourceID(feedURL: feedURL), rawID: shortHash(combined))
    }

    /// 归一化 feed 地址：去掉首尾空白、统一小写、丢弃片段与末尾斜杠。
    ///
    /// 不归一化的话，`HTTPS://Example.com/feed/` 与 `https://example.com/feed`
    /// 会被当成两个源，重复订阅看起来像缺陷。
    public static func normalizedFeedKey(_ url: URL) -> String {
        var text = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let hashIndex = text.firstIndex(of: "#") {
            text = String(text[text.startIndex..<hashIndex])
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }
}
