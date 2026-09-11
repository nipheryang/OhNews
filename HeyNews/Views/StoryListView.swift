import HeyNewsKit
import SwiftUI

struct StoryListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            banner

            if state.stories.isEmpty {
                EmptyStateView(
                    isLoading: state.isLoading,
                    errorMessage: state.lastErrorMessage,
                    onRetry: { Task { await state.refresh() } }
                )
            } else {
                listContent
            }
        }
        .navigationTitle(state.activeList.displayName)
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var banner: some View {
        switch state.aiStatus {
        case .notConfigured:
            if state.config.isEnabled {
                AIUnavailableBanner(
                    title: "AI 摘要未启用",
                    message: "填入 API Key 后，会为列表前 \(AppState.summaryPrefetchLimit) 条自动生成中文摘要；不配置也能正常阅读。"
                )
            }
        case .failed(let message):
            AIUnavailableBanner(title: "AI 请求失败", message: message)
        case .ready:
            EmptyView()
        }
    }

    private var listContent: some View {
        List {
            if let message = state.lastErrorMessage {
                // 有缓存但刷新失败：不遮挡内容，只在顶部提示。
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(state.stories) { story in
                StoryRowView(
                    story: story,
                    isRead: state.isRead(story),
                    isSelected: state.selectedStoryID == story.id,
                    summary: state.summaries[story.id],
                    isGeneratingSummary: state.isGeneratingSummary(for: story)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await state.select(story) }
                }
            }
        }
        .listStyle(.inset)
        .refreshable { await state.refresh() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if state.isLoading {
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .controlSize(.small)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await state.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(state.isLoading)
            .help("重新获取榜单")
        }

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .help("配置 AI 摘要")
        }
    }
}
