// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit

/// 正文顶部那块 AI 解读面板的 HTML。
///
/// 面板是**正文文档里的一段**，不是 SwiftUI 浮层：这样才能随正文一起滚，
/// 而不是钉在阅读区顶上。正文文档给它留了一个空容器（`#ohnews-insight`），
/// 解读到位后由 `ReaderScript.setInsightHTML` 原地填进去——不重建文档，
/// 所以不会丢掉阅读位置。
///
/// 与列表里那份摘要不是一回事：那份跑在抓正文之前，只能凭标题与评论作答，
/// 回答「值不值得点进去」；这份读的是正文本身，回答「讲了什么、大家怎么看」。
enum InsightPanel {
    /// 面板的 HTML。返回空串表示「这块不占位置」——容器会被清空。
    static func html(for state: InsightState) -> String {
        switch state {
        case .unavailable:
            return ""

        case .generating:
            return shell(body: #"<p class="ohnews-insight-note">正在读正文与评论区…</p>"#)

        case .ready(let insight):
            return shell(body: content(for: insight), showsRegenerate: true)

        case .failed(let message):
            return shell(body: """
            <p class="ohnews-insight-note">\(escape(message))
              <span class="ohnews-insight-action" data-ohnews-action="regenerateInsight">重试</span>
            </p>
            """)
        }
    }

    // MARK: - 组装

    private static func shell(body: String, showsRegenerate: Bool = false) -> String {
        // 「重新生成」是页面上的可点元素，命中判定与高亮工具条共用一条路径
        // （应用侧认 data-ohnews-action）。
        let action = showsRegenerate
            ? """
              <span class="ohnews-insight-action" data-ohnews-action="regenerateInsight" \
              title="忽略缓存，让模型重新读一遍">重新生成</span>
              """
            : ""

        return """
        <div class="ohnews-insight">
          <div class="ohnews-insight-head">
            <span class="ohnews-insight-eyebrow">AI 解读</span>
            \(action)
          </div>
          \(body)
        </div>
        """
    }

    private static func content(for insight: ArticleInsight) -> String {
        var parts: [String] = []

        if insight.articleSummary.isEmpty == false {
            parts.append("<p>\(escape(insight.articleSummary))</p>")
        }

        if insight.keyPoints.isEmpty == false {
            parts.append(#"<p class="ohnews-insight-section">要点</p>"#)
            parts.append(list(insight.keyPoints))
        }

        let hasDiscussion = insight.discussionSummary != nil
            || insight.discussionTrends.isEmpty == false
        if hasDiscussion {
            parts.append(#"<p class="ohnews-insight-section">讨论区</p>"#)

            if let summary = insight.discussionSummary {
                parts.append("<p>\(escape(summary))</p>")
            }

            if insight.discussionTrends.isEmpty == false {
                parts.append(list(insight.discussionTrends))
            }
        }

        return parts.joined(separator: "\n")
    }

    private static func list(_ items: [String]) -> String {
        let rows = items.map { "<li>\(escape($0))</li>" }.joined(separator: "\n")
        return "<ul>\n\(rows)\n</ul>"
    }

    /// 解读的文字是模型给的，一律转义后再拼。
    private static func escape(_ text: String) -> String {
        ReaderDocumentBuilder.escapeText(text)
    }
}
