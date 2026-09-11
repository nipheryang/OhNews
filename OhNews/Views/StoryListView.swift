import AppKit
import OhNewsKit
import SwiftUI

struct StoryListView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// 交给 `List` 的选择绑定。
    ///
    /// 选中完全交给原生选择机制，不再在行上加 `onTapGesture`——实测那样会
    /// 把点击吃掉，`List` 拿不到焦点，方向键就完全失效。
    /// 选中变化后由 `onChange` 统一走 `state.select(_:)`，鼠标与键盘行为一致。
    private var selection: Binding<String?> {
        Binding(
            get: { state.selectedStoryID },
            set: { state.selectedStoryID = $0 }
        )
    }

    private var listContent: some View {
        List(selection: selection) {
            if let message = state.lastErrorMessage {
                // 有缓存但刷新失败：不遮挡内容，只在顶部提示。
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(state.stories) { story in
                StoryRowView(
                    story: story,
                    isRead: state.isRead(story),
                    isSelected: state.selectedStoryID == story.id,
                    summary: state.summaries[story.id],
                    isGeneratingSummary: state.isGeneratingSummary(for: story)
                )
                .tag(story.id)
                .contextMenu {
                    rowMenu(for: story)
                }
                .listRowInsets(EdgeInsets(
                    top: Metrics.cardSpacing / 2,
                    leading: Metrics.listHorizontalInset,
                    bottom: Metrics.cardSpacing / 2,
                    trailing: Metrics.listHorizontalInset
                ))
                .listRowSeparator(.hidden)
                // 用不透明的行背景遮住 `List` 自带的选中高亮：它是一块通栏直角方块，
                // 会盖过卡片的圆角与左右留白，和卡片语言直接冲突。
                // 选中态由卡片自己的强调色底色表达，键盘导航仍然走原生选择。
                .listRowBackground(Palette.listSurface)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Palette.listSurface)
        .onChange(of: state.selectedStoryID) { _, newValue in
            guard let newValue,
                  let story = state.stories.first(where: { $0.id == newValue })
            else { return }
            Task { await state.select(story) }
        }
        .refreshable { await state.refresh() }
        // 新条目插入时把已有行往下推。用短时平滑弹簧而不是弹跳：阅读场景里
        // 明显的运动会让用户丢失阅读位置，这里只需要“被轻轻让开”的感觉。
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.26),
            value: state.stories.map(\.id)
        )
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
                    // 只在真正刷新期间转，结束就停，不做循环装饰。
                    .symbolEffect(.rotate, isActive: state.isLoading)
                    .symbolEffectsRemoved(reduceMotion)
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
