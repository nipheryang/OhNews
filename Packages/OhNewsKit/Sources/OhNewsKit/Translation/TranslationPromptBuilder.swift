// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 翻译 prompt 的版本号。
///
/// 改动 prompt 或输出格式时递增，已缓存的译文会自动失效——与摘要的
/// `PromptVersion` 各自独立，因为两者变化的时机不同。
public enum TranslationVersion {
    public static let current = "t1"
}

/// 组装翻译请求。
///
/// system 段固定不变（有利于 provider 侧的 prompt 缓存命中），待译内容整体
/// 放在 user 段。输入输出都用 JSON，形状对称，模型更容易保持一一对应。
public enum TranslationPromptBuilder {
    public struct Request: Equatable, Sendable {
        public let system: String
        public let user: String
    }

    public static let systemPrompt = """
    你是专业的技术文章翻译。把用户给出的文本片段逐条翻译成简体中文。

    只输出一个 JSON 对象，不要 Markdown 代码块，不要输出任何解释文字。格式如下：
    {"translations": ["第一段译文", "第二段译文"]}

    要求：
    - translations 的条数与顺序必须与输入的 segments 完全一致，不得合并、拆分或遗漏。
    - 只输出译文本身，不要附带原文，不要加编号或引号。
    - 文本里的 [[0]]、[[1]] 这类标记是链接占位符，必须原样保留，不得翻译、删除或移动位置。
    - 技术术语、产品名、代码标识符（如 SwiftUI、PostgreSQL、pip install）保留英文原文。
    - 已经是中文的片段原样返回。
    - 单个片段内部保持原有的标点与换行习惯，不要自行添加小标题或列表。
    """

    public static func build(
        segments: [ArticleSegmenter.Segment]
    ) -> Request {
        let payload = segments.map(\.text)
        let user: String
        if let data = try? JSONSerialization.data(withJSONObject: ["segments": payload], options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            user = text
        } else {
            // 兜底：极端情况下退回按行列出，仍然是可解析的输入。
            user = payload.map { "- \($0)" }.joined(separator: "\n")
        }

        return Request(system: systemPrompt, user: user)
    }
}
