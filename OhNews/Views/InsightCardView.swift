// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 正文顶部的 AI 解读。
///
/// 与列表里那份摘要不是一回事：那份跑在抓正文之前，只能凭标题与评论作答，
/// 作用是「值不值得点进去」；这份读的是正文本身，回答「讲了什么、大家怎么看」。
///
/// 排版沿用整套语言：发丝线分隔、衬线正文、等宽眉标，**不用卡片底色**。
struct InsightCardView: View {
    let state: InsightState
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch state {
            case .unavailable:
                EmptyView()
            case .generating:
                generating
            case .ready(let insight):
                content(insight)
            case .failed(let message):
                failure(message)
            }
        }
        .frame(maxWidth: Metrics.readerMaxWidth, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 18)
        .padding(.bottom, 20)
        // 与正文区之间用发丝线交代边界，不做底色分层。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: Metrics.hairline)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("AI 解读")
                .font(Typography.eyebrow)
                .tracking(Metrics.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)

            Spacer(minLength: 8)

            if case .ready = state {
                Button("重新生成", action: onRegenerate)
                    .buttonStyle(.plain)
                    .font(Typography.uiSmall)
                    .foregroundStyle(Palette.inkFaint)
                    .help("忽略缓存，让模型重新读一遍")
            }
        }
        .padding(.bottom, 10)
    }

    private var generating: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在读正文与评论区…")
                .font(Typography.meta)
                .tracking(Metrics.metaTracking)
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.vertical, 4)
    }

    private func failure(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(message)
                .font(Typography.meta)
                .tracking(Metrics.metaTracking)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button("重试", action: onRegenerate)
                .buttonStyle(.plain)
                .font(Typography.uiSmall)
                .foregroundStyle(Palette.ink)
        }
    }

    // MARK: - 内容

    private func content(_ insight: ArticleInsight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if insight.articleSummary.isEmpty == false {
                Text(insight.articleSummary)
                    .font(Typography.insightBody)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(Typography.insightBodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if insight.keyPoints.isEmpty == false {
                sectionTitle("要点")
                pointList(insight.keyPoints)
            }

            let hasDiscussion = insight.discussionSummary != nil
                || insight.discussionTrends.isEmpty == false
            if hasDiscussion {
                sectionTitle("讨论区")

                if let summary = insight.discussionSummary {
                    Text(summary)
                        .font(Typography.insightBody)
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(Typography.insightBodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if insight.discussionTrends.isEmpty == false {
                    pointList(insight.discussionTrends)
                        .padding(.top, insight.discussionSummary == nil ? 0 : 8)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Typography.eyebrow)
            .tracking(Metrics.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
            .padding(.top, 16)
            .padding(.bottom, 7)
    }

    /// 要点用悬挂的圆点：点落在文字左边，折行时文字对齐，不会顶着圆点走。
    private func pointList(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("·")
                        .font(Typography.insightBody)
                        .foregroundStyle(Palette.inkFaint)
                    Text(point)
                        .font(Typography.insightBody)
                        .foregroundStyle(Palette.inkSoft)
                        .lineSpacing(Typography.insightBodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
