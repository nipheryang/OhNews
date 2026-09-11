import AppKit
import OhNewsKit
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
        .navigationTitle(state.selectedChannel?.name ?? "OhNews")
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var banner: some View {
        switch state.aiStatus {
        case .notConfigured:
            if state.config.isEnabled {
                AIUnavailableBanner(
                    title: "AI 摘要未启用",
                    message: "填入 API Key 后即可生成中文摘要；不配置也能正常阅读。"
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
                .onTapGesture {
                    Task { await state.select(story) }
                }
                .contextMenu {
                    rowMenu(for: story)
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .refreshable { await state.refresh() }
        // 新条目插入时用弹性动画把已有行往下推，而不是生硬地重排。
        // 只在顺序变化时触发，所以普通刷新（已有条目原地更新）不会有动画。
        .animation(.bouncy(duration: 0.45), value: state.stories.map(\.id))
    }

    /// 行的右键菜单。
    ///
    /// 列表只自动生成前若干条摘要，剩下的由用户在这里按需生成；
    /// 已有摘要时提供重新生成，避免过期或不满意的结果无从替换。
    @ViewBuilder
    private func rowMenu(for story: Story) -> some View {
        if state.config.isEnabled == false {
            Button("生成 AI 摘要") {}
                .disabled(true)
            Text("需要先在设置里启用 AI")
        } else if state.summaries[story.id] != nil {
            Button("重新生成 AI 摘要") {
                Task { await state.generateSummaryNow(for: story, force: true) }
            }
            .disabled(state.isGeneratingSummary(for: story))
        } else {
            Button("生成 AI 摘要") {
                Task { await state.generateSummaryNow(for: story) }
            }
            .disabled(state.isGeneratingSummary(for: story))
        }

        Divider()

        Button("在浏览器中打开") {
            if let url = story.url {
                NSWorkspace.shared.open(url)
            }
        }
        .disabled(story.url == nil)
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
