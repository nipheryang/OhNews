import OhNewsKit
import SwiftUI

/// 列表里的一条内容。
///
/// 一条新闻是一张卡片：来源、标题、元信息与 AI 摘要共用同一个表面与圆角。
/// 内部按重要性分四层，每层只干一件事，靠字号和颜色拉开层级，而不是靠边框或嵌套底色。
struct StoryRowView: View {
    let story: Story
    let isRead: Bool
    let isSelected: Bool
    let summary: StorySummary?
    let isGeneratingSummary: Bool

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceLine

            Text(story.title)
                .font(Typography.listTitle)
                .foregroundStyle(isRead ? Palette.textSecondary : Palette.textPrimary)
                .lineSpacing(Typography.listTitleLineSpacing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            metaLine

            summarySection
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(fillColor))
        .contentShape(shape)
        .onHover { hovering in
            // 只改背景，不改尺寸，所以不会产生「整行被推了一下」的错觉。
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 三态底色：选中优先于悬浮，常态就是卡片底色。
    private var fillColor: Color {
        if isSelected { return Palette.cardSelected }
        if isHovering { return Palette.cardHover }
        return Palette.cardSurface
    }

    // MARK: - 第一层：来源与时间

    private var sourceLine: some View {
        HStack(spacing: 6) {
            SourceBadge(host: story.sourceHost)

            Text(story.sourceHost ?? "自述帖")
                .font(Typography.metadata)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(story.postedAt, format: .relative(presentation: .named))
                .font(Typography.metadata)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - 第三层：分数、评论数、作者

    /// 低优先级信息，统一降为三级文字，并用 `·` 连接而不是一组图标。
    @ViewBuilder
    private var metaLine: some View {
        let parts = metaParts
        if parts.isEmpty == false {
            Text(parts.joined(separator: " · "))
                .font(Typography.metadata)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .padding(.top, 4)
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let score = story.score {
            parts.append("\(score) 分")
        }
        if let commentCount = story.commentCount {
            parts.append("\(commentCount) 条评论")
        }
        let author = story.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.isEmpty == false {
            parts.append(author)
        }
        return parts
    }

    // MARK: - 第四层：AI 摘要

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
        parts.append(story.postedAt.formatted(.relative(presentation: .named)))
        parts.append(contentsOf: metaParts)
        if isRead { parts.append("已读") }
        return parts.joined(separator: "，")
    }
}
