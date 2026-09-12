import OhNewsKit
import SwiftUI

/// 列表里的一条内容。
///
/// 形态对齐博客的 `.post-card`：**没有卡片底色**，条目之间只有一条 1px 发丝线，
/// 秩序来自留白与线条，而不是明度分层。
///
/// 层级全部由排版承担：
///
/// | 层 | 字体 | 颜色 |
/// | --- | --- | --- |
/// | 来源与时间 | 等宽大写、宽字距 | `inkFaint` |
/// | 标题 | **衬线** 半粗 | `ink`（已读或悬浮时降到 `inkSoft`） |
/// | AI 摘要 | 衬线，带引线 | `inkSoft` |
/// | 分数／评论／作者 | 等宽 | `inkFaint` |
struct StoryRowView: View {
    let story: Story
    let isRead: Bool
    let isSelected: Bool
    let summary: StorySummary?
    let isGeneratingSummary: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow

            Text(story.title)
                .font(Typography.rowTitle)
                .foregroundStyle(titleColor)
                .lineSpacing(Typography.rowTitleLineSpacing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            summarySection

            metaLine
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: Metrics.hairline)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            // 只改颜色，不改尺寸，也不会把相邻条目推开。
            withAnimation(Motion.standard) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var background: Color {
        if isSelected { return Palette.selectedWash }
        if isHovering { return Palette.hoverWash }
        return .clear
    }

    /// 博客里的标志性手法：悬浮时标题**变浅**（ink → inkSoft），而不是变亮。
    private var titleColor: Color {
        (isRead || isHovering) ? Palette.inkSoft : Palette.ink
    }

    // MARK: - 眉标：来源与时间

    private var eyebrow: some View {
        Text(eyebrowText)
            .font(Typography.eyebrow)
            .tracking(Metrics.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var eyebrowText: String {
        let source = story.sourceHost ?? "自述帖"
        let time = RelativeTime.text(for: story.postedAt)
        return "\(source) · \(time)"
    }

    // MARK: - 尾注：分数、评论数、作者

    @ViewBuilder
    private var metaLine: some View {
        let parts = metaParts
        if parts.isEmpty == false {
            Text(parts.joined(separator: " · "))
                .font(Typography.meta)
                .tracking(Metrics.metaTracking)
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
                .padding(.top, 10)
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let score = story.score {
            parts.append("\(score) 分")
        }
        if let commentCount = story.commentCount {
            parts.append("\(commentCount) 评论")
        }
        let author = story.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.isEmpty == false {
            parts.append(author)
        }
        return parts
    }

    // MARK: - AI 摘要

    @ViewBuilder
    private var summarySection: some View {
        if let summary {
            SummaryBlockView(summary: summary)
        } else if isGeneratingSummary {
            SummarySkeletonView()
        }
    }

    private var accessibilityLabel: String {
        var parts = [story.title, story.sourceHost ?? "自述帖"]
        parts.append(RelativeTime.text(for: story.postedAt))
        parts.append(contentsOf: metaParts)
        if isRead { parts.append("已读") }
        return parts.joined(separator: "，")
    }
}
