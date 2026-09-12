// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 列表行内的 AI 摘要。
///
/// 处理成博客里 `blockquote` 的形态：左侧一道引线 + 缩进，**没有任何底色**。
/// 这套设计语言是单色的，所以 AI 内容不用颜色区分，而用排版区分——
/// 等宽小标签说明来源，衬线正文承接阅读。
struct SummaryBlockView: View {
    let summary: StorySummary

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.quoteIndent) {
            Rectangle()
                .fill(Palette.lineStrong)
                .frame(width: Metrics.quoteRuleWidth)

            VStack(alignment: .leading, spacing: 6) {
                label

                Text(summary.chineseTitle)
                    .font(Typography.summaryTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 不截断时一条长摘要能把行高撑到相邻行的两三倍，列表节奏就没了。
                Text(summary.summary)
                    .font(Typography.summaryBody)
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(Typography.summaryBodyLineSpacing)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let consensus = summary.commentConsensus {
                    Text("共识 · \(consensus)")
                        .font(Typography.eyebrow)
                        .tracking(Metrics.metaTracking)
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 12)
    }

    /// 标签与来源说明合到同一行等宽小字里，不再用彩色胶囊。
    private var label: some View {
        Text(labelText)
            .font(Typography.eyebrow)
            .tracking(Metrics.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
    }

    private var labelText: String {
        guard summary.tags.isEmpty == false else { return "AI 摘要" }
        return "AI 摘要 · " + summary.tags.joined(separator: " · ")
    }
}

/// 摘要生成中的占位。
///
/// 用与摘要同宽的两条灰条，而不是「转圈 + 文字」：生成完成时文字直接替换占位，
/// 行的几何形状不变，列表不会因此跳动。
struct SummarySkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.quoteIndent) {
            Rectangle()
                .fill(Palette.lineStrong)
                .frame(width: Metrics.quoteRuleWidth)

            VStack(alignment: .leading, spacing: 8) {
                bar(trailingInset: 200)
                bar(trailingInset: 40)
            }
        }
        .padding(.top, 12)
        .opacity(reduceMotion ? 0.7 : (isDimmed ? 0.55 : 1))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: isDimmed
        )
        .onAppear { if reduceMotion == false { isDimmed = true } }
        .accessibilityLabel("正在生成摘要")
    }

    private func bar(trailingInset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Palette.ink.opacity(0.08))
            .frame(height: 9)
            .padding(.trailing, trailingInset)
    }
}

/// AI 不可用时的提示条。整个列表只显示一条，不逐行重复。
///
/// 形态对齐博客 `.prose pre`：1px 线条 + 圆角，清淡但不含糊。
struct AIUnavailableBanner: View {
    let title: String
    let message: String
    /// 一次性问题（比如某次请求失败）可以关掉；配置类问题传 nil。
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.eyebrow)
                    .tracking(Metrics.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)

                Text(message)
                    .font(Typography.uiSmall)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let onDismiss {
                Button(action: onDismiss) {
                    Text("关闭").underline()
                }
                .buttonStyle(.plain)
                .font(Typography.uiSmall)
                .foregroundStyle(Palette.inkSoft)
                .help("关闭提示")
            }

            SettingsLink {
                Text("去设置").underline()
            }
            .buttonStyle(.plain)
            .font(Typography.uiSmall)
            .foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
                .stroke(Palette.line, lineWidth: Metrics.hairline)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 12)
    }
}
