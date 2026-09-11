import HeyNewsKit
import SwiftUI

/// 列表为空时的三种状态：首次加载中、取不到数据、确实没有内容。
struct EmptyStateView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        if isLoading {
            ProgressView("正在获取 HN 榜单…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("暂时取不到数据", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试", action: onRetry)
            }
        } else {
            ContentUnavailableView("暂无内容", systemImage: "tray")
        }
    }
}

/// 详情区占位。M4 会替换成内嵌阅读器。
struct StoryDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let story = state.selectedStory {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label(story.title, systemImage: "doc.text")
                } description: {
                    Text(description(for: story))
                } actions: {
                    if let url = story.url {
                        Link("在浏览器中打开", destination: url)
                    }
                }
            }
            .navigationTitle(story.sourceHost ?? "Hacker News")
        } else {
            ContentUnavailableView(
                "选择一条新闻",
                systemImage: "newspaper",
                description: Text("左侧切换榜单，中间选择条目。")
            )
        }
    }

    private func description(for story: Story) -> String {
        var lines = [
            "\(story.score) 分 · \(story.commentCount) 条评论 · \(story.author)",
            "阅读器将在 M4 接入，AI 摘要将在 M3 显示在列表行内。",
        ]
        if story.isSelfPost {
            lines.append("这是 HN 自述帖，没有外链。")
        }
        return lines.joined(separator: "\n")
    }
}
