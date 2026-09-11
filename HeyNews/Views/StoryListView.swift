import HeyNewsKit
import SwiftUI

struct StoryListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
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
                    isSelected: state.selectedStoryID == story.id
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
    }
}
