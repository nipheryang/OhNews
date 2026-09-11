import OhNewsKit
import SwiftUI

struct StoryRowView: View {
    let story: Story
    let isRead: Bool
    let isSelected: Bool
    let summary: StorySummary?
    let isGeneratingSummary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if let summary {
                SummaryCardView(summary: summary)
            } else if isGeneratingSummary {
                SummarySkeletonView()
            }
        }
        .padding(.vertical, 5)
    }
}
