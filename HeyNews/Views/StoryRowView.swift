import HeyNewsKit
import SwiftUI

struct StoryRowView: View {
    let story: Story
    let isRead: Bool
    let isSelected: Bool

    var body: some View {
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
                Label("\(story.score)", systemImage: "arrow.up")
                Label("\(story.commentCount)", systemImage: "bubble.right")
                Text(story.author)
                Text(story.postedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .opacity(isSelected ? 1 : 0.98)
    }
}
