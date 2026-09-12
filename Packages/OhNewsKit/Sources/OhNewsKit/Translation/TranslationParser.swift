// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

public enum TranslationParseError: Error, Equatable {
    /// 输出里找不到可解析的 JSON 对象。
    case unparsable
    /// 条数与输入对不上。宁可整批作废，也不能猜对应关系——错位会让整篇译文对不上。
    case countMismatch(expected: Int, got: Int)
}

/// 解析模型返回的译文数组。
public enum TranslationParser {
    /// 按固定顺序容错：剥掉代码围栏 → 提取首个平衡的 JSON 对象 → 取 `translations`。
    ///
    /// - Parameter expectedCount: 该批输入的片段数，用于校验一一对应。
    public static func parse(_ raw: String, expectedCount: Int) throws -> [String] {
        guard let json = SummaryParser.extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = translations(in: object)
        else {
            throw TranslationParseError.unparsable
        }

        guard list.count == expectedCount else {
            throw TranslationParseError.countMismatch(expected: expectedCount, got: list.count)
        }
        return list
    }

    /// 兼容几种常见字段名，以及「数组被写成了字符串」这类脏数据。
    private static func translations(in object: [String: Any]) -> [String]? {
        for key in ["translations", "translation", "result", "results", "译文"] {
            guard let value = object[key] else { continue }

            if let array = value as? [String] {
                return array
            }
            if let array = value as? [Any] {
                return array.map { $0 as? String ?? "" }
            }
            if let text = value as? String {
                // 单个字符串：按行拆，至少不会因为形状不对而整批失败。
                let lines = text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.isEmpty == false }
                return lines.isEmpty ? nil : lines
            }
        }
        return nil
    }
}
