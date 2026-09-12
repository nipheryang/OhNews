// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// feed 条目里的日期解析。
///
/// RSS 用 RFC 822（`Thu, 01 Sep 2026 12:00:00 GMT`），Atom 用 ISO 8601
/// （`2026-09-01T12:00:00Z`）。真实 feed 的写法相当随意——缺秒、带时区名、
/// 带小数秒、只有日期——所以按多个格式依次尝试。
///
/// 全部失败时返回 `nil`，由调用方决定兜底策略，而不是猜一个时间。
enum FeedDateParser {
    /// `ISO8601DateFormatter` 在严格并发下未标注 `Sendable`，这里只读使用，因此显式声明为安全。
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `DateFormatter` 已标注为 `Sendable`，这里只读使用，可以安全共享。
    private static let rfc822Formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd HH:mm:ss Z"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }

        if let date = iso8601.date(from: text) { return date }
        if let date = iso8601Fractional.date(from: text) { return date }

        for formatter in rfc822Formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
