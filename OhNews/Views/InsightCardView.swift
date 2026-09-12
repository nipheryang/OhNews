// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 正文顶部的 AI 解读浮层。
///
/// 形态是一块玻璃面板：**固定高度**、内容在内部滚动、浮在正文之上。正文在它后面
/// 滑过，文字经过下边缘时被材质遮住，形成层次。
///
/// 高度必须固定，不能随解读字数变化：它浮在正文上，高度一变就会推挤下面的阅读
/// 位置——正读着的一句可能被顶走。超出部分交给面板内部的滚动。
///
/// 与列表里那份摘要不是一回事：那份跑在抓正文之前，只能凭标题与评论作答，作用是
/// 「值不值得点进去」；这份读的是正文本身，回答「讲了什么、大家怎么看」。
struct InsightCardView: View {
    let state: InsightState
    let onRegenerate: () -> Void

    /// 面板高度。约占 780pt 窗口的三分之一：够看完总结与要点，
    /// 又不至于把正文压得只剩一条缝。
    static let height: CGFloat = 236

    var body: some View {
        VStack(spacing: 0) {
            // 眉标与按钮钉在顶部，不跟着内容滚走：面板滚到底时也要能找到「重新生成」。
            header

            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(height: Self.height, alignment: .top)
        .background(glass)
        .clipShape(panelShape)
        .overlay { glassEdge }
        .overlay(alignment: .bottom) { bottomEdge }
        // 让面板从正文里「浮起来」：一层往下投的浅影，不用描边围一圈，
        // 那会把它变成一张卡片，与整套发丝线语言冲突。
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 5)
    }

    /// 沿边缘的一圈细高光。
    ///
    /// 这是玻璃区别于「半透明色块」的地方：光在边缘聚一下，材质就有了厚度。
    /// 用 `ink` 而不是白色常量：浅色主题下它会自然变成一道暗描边。
    private var glassEdge: some View {
        panelShape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Palette.ink.opacity(0.14),
                        Palette.ink.opacity(0.05),
                        Palette.ink.opacity(0.18),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
            .allowsHitTesting(false)
    }

    /// 顶部贴边、底部圆角：面板悬在正文区顶端，上与标题栏相接。
    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 18,
            style: .continuous
        )
    }

    // MARK: - 玻璃

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            // 系统更新后优先用原生的液态玻璃。
            Rectangle().fill(.clear).glassEffect(.regular, in: .rect(cornerRadii: .init(
                bottomLeading: 18,
                bottomTrailing: 18
            )))
        } else {
            // macOS 15：用极薄材质。它本身就会把身后的正文模糊透出来，
            // 正是这里需要的效果。
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    /// 下边缘一道高光，把「玻璃有厚度」这件事交代出来。
    private var bottomEdge: some View {
        LinearGradient(
            colors: [
                Palette.line.opacity(0.0),
                Palette.line.opacity(0.55),
                Palette.ink.opacity(0.12),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 2)
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
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unavailable:
            EmptyView()
        case .generating:
            generating
        case .ready(let insight):
            ready(insight)
        case .failed(let message):
            failure(message)
        }
    }

    private var generating: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在读正文与评论区…")
                .font(Typography.meta)
                .tracking(Metrics.metaTracking)
                .foregroundStyle(Palette.inkSoft)
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

    private func ready(_ insight: ArticleInsight) -> some View {
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
            .padding(.top, 14)
            .padding(.bottom, 6)
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
