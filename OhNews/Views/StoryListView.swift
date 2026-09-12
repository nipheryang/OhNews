import AppKit
import OhNewsKit
import SwiftUI

struct StoryListView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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

    /// 顶部提示。两种性质分开处理：
    ///
    /// - 配置类问题（缺密钥、配置不完整、密钥读不到）持续存在，给出原因并可跳设置
    /// - 请求失败是一次性的，带关闭按钮，否则一条内容的偶发失败会永久挂在顶部
    @ViewBuilder
    private var banner: some View {
        if let failure = state.aiFailureMessage {
            AIUnavailableBanner(
                title: "AI 请求失败",
                message: failure,
                onDismiss: { state.dismissAIFailure() }
            )
        } else if let explanation = state.aiConfiguration.explanation {
            AIUnavailableBanner(
                title: bannerTitle,
                message: explanation,
                onDismiss: nil
            )
        }
    }

    private var bannerTitle: String {
        switch state.aiConfiguration {
        case .keyUnreadable:
            "无法读取 API Key"
        case .keyMissing:
            "尚未设置 API Key"
        default:
            "AI 摘要未启用"
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
                    .font(Typography.uiSmall)
                    .foregroundStyle(Palette.inkSoft)
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
                    top: 0,
                    leading: Metrics.gutter,
                    bottom: 0,
                    trailing: Metrics.gutter
                ))
                .listRowSeparator(.hidden)
                // 用不透明的纸底色作行背景：既遮住 `List` 自带的选中高亮
                // （一块通栏直角方块，与这套发丝线语言格格不入），
                // 也让条目之间只靠自己的 1px 线条分隔，不产生卡片感。
                .listRowBackground(Palette.paper)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .onChange(of: state.selectedStoryID) { _, newValue in
            guard let newValue,
                  let story = state.stories.first(where: { $0.id == newValue })
            else { return }
            Task { await state.select(story) }
        }
        .refreshable { await state.refresh() }
        // 新条目插入时把已有行往下推。用博客同一条缓动曲线，短而非弹跳：
        // 阅读场景里明显的运动会让人丢失阅读位置。
        .animation(
            reduceMotion ? nil : Motion.insert,
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
            Button {
                state.setAppearance(isCurrentlyDark ? .light : .dark)
            } label: {
                Label(appearanceActionLabel, systemImage: isCurrentlyDark ? "sun.max" : "moon")
            }
            .help(appearanceActionLabel)
        }

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .help("配置 AI 摘要")
        }
    }

    /// 当前实际是不是深色。用户显式选过就按用户的选择，不再依赖环境值；
    /// 只有在「跟随系统」时才读环境外观。
    private var isCurrentlyDark: Bool {
        switch state.appearance {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    private var appearanceActionLabel: String {
        isCurrentlyDark ? "切换到浅色外观" : "切换到深色外观"
    }
}
