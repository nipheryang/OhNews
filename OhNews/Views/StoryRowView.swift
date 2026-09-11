import OhNewsKit
import SwiftUI

/// 列表里的一条内容。
///
/// 标题、元信息与 AI 摘要属于同一篇文章，所以整块共用一个背景与圆角：
/// 鼠标悬停时整块出现底色，用户一眼能看出「点这里的任何位置都是打开这篇文章」。
struct StoryRowView: View {
    let story: Story
    let isRead: Bool
    let isSelected: Bool
    let summary: StorySummary?
    let isGeneratingSummary: Bool

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            summarySection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(fillColor))
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    /// 三态底色：选中优先于悬停。
    private var fillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovering {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.headline)
                .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(2)

            HStack(spacing: 10) {
                if let host = story.sourceHost {
                    Label(host, systemImage: "link")
                } else {
                    Label("自述帖", systemImage: "text.bubble")
                }
                if let score = story.score {
                    Label("\(score)", systemImage: "arrow.up")
                }
                if let commentCount = story.commentCount {
                    Label("\(commentCount)", systemImage: "bubble.right")
                }
                Text(story.author)
                Text(story.postedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary {
            SummaryCardView(summary: summary)
        } else if isGeneratingSummary {
            SummarySkeletonView()
        }
    }
}
