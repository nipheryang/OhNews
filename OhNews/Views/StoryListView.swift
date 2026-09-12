// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

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

            if let notice = state.transientNotice {
                noticeBar(notice)
            }

            if let update = state.availableUpdate {
                updateBar(update)
            }

            if let entry = state.activeLibraryEntry {
                libraryContent(for: entry)
            } else if state.stories.isEmpty {
                EmptyStateView(
                    isLoading: state.isLoading,
                    errorMessage: state.lastErrorMessage,
                    onRetry: { Task { await state.refresh() } }
                )
            } else {
                listContent
            }
        }
        // 整列的高度取自容器（窗口），而不是由 `List` 的内容高度决定：
        // `List` 会按全部内容高度索取空间，这个需求传给 `NavigationSplitView`
        // 后会把整列撑成列表全长，窗口装不下就溢出——侧栏因此空白，正文上方
        // 也看不到。放在根视图上（而不是列表上）可以避免与提示条叠加出循环。
        .containerRelativeFrame(.vertical)
        .animation(reduceMotion ? nil : Motion.standard, value: state.transientNotice)
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
    }

    /// 有新版本时的提示条。可关闭；关掉后同一版本不再出现。
    private func updateBar(_ info: ReleaseInfo) -> some View {
        HStack(spacing: 12) {
            Text("有新版本 \(info.tagName)")
                .font(Typography.uiSmall)
                .foregroundStyle(Palette.ink)

            Spacer(minLength: 8)

            Button("查看") { state.openUpdatePage() }
                .buttonStyle(.plain)
                .font(Typography.uiSmall)
                .foregroundStyle(Palette.ink)

            Button {
                state.dismissUpdate()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .buttonStyle(.plain)
            .help("不再提示这个版本")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: Metrics.hairline)
        }
    }

    /// 轻提示条：一条发丝线分隔的等宽小字，不抢占内容区。
    private func noticeBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Typography.uiSmall)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: Metrics.hairline)
        }
        .transition(.opacity)
    }

    private var navigationTitle: String {
        if let entry = state.activeLibraryEntry { return entry.title }
        return state.selectedChannel?.name ?? "OhNews"
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
            guard let newValue else { return }
            Task { await state.selectByID(newValue) }
        }
        .refreshable { await state.refresh() }
        // 新条目插入时把已有行往下推。用博客同一条缓动曲线，短而非弹跳：
        // 阅读场景里明显的运动会让人丢失阅读位置。
        .animation(
            reduceMotion ? nil : Motion.insert,
            value: state.stories.map(\.id)
        )
    }

    /// 中栏的收藏／稍后读列表。
    ///
    /// 行视图与频道列表共用：同一套排版、同一种已读与摘要行为，切过来不需要重新学。
    ///
    /// 收藏分「文章」与「段落」两段——两个级别的收藏共用收藏这一个入口；
    /// 稍后读只收整篇，段落收在里面没有意义。
    @ViewBuilder
    private func libraryContent(for entry: LibraryEntry) -> some View {
        let articles = state.activeLibraryItems
        let passages = entry == .collection ? state.passageItems : []

        if articles.isEmpty && passages.isEmpty {
            VStack(spacing: 10) {
                Text(entry.title)
                    .font(Typography.emptyStateTitle)
                    .foregroundStyle(Palette.ink)

                Text(entry.emptyHint)
                    .font(Typography.meta)
                    .tracking(Metrics.metaTracking)
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selection) {
                if articles.isEmpty == false {
                    if entry == .collection {
                        Section {
                            articleRows(articles)
                        } header: {
                            sectionHeader("文章")
                        }
                    } else {
                        Section {
                            articleRows(articles)
                        }
                    }
                }

                if passages.isEmpty == false {
                    Section {
                        passageRows(passages)
                    } header: {
                        sectionHeader("段落")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .onChange(of: state.selectedStoryID) { _, newValue in
                guard let newValue else { return }
                Task { await state.selectByID(newValue) }
            }
        }
    }

    @ViewBuilder
    private func articleRows(_ articles: [SavedArticle]) -> some View {
        ForEach(articles) { article in
            StoryRowView(
                story: article.story,
                isRead: state.isRead(article.story),
                isSelected: state.selectedStoryID == article.id,
                // 清单里的摘要是收藏时冻下来的，优先用它：列表不必等打开内容
                // 就能显示中文标题与摘要。
                summary: article.summary ?? state.summaries[article.id],
                isGeneratingSummary: state.isGeneratingSummary(for: article.story),
                displayTitle: article.translatedTitle
            )
            .tag(article.id)
            .contextMenu {
                rowMenu(for: article.story)
            }
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: Metrics.gutter,
                bottom: 0,
                trailing: Metrics.gutter
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.paper)
        }
    }

    @ViewBuilder
    private func passageRows(_ passages: [SavedPassage]) -> some View {
        ForEach(passages) { passage in
            SavedPassageRowView(
                passage: passage,
                isSelected: state.selectedStoryID == passage.id
            )
            .tag(passage.id)
            .contextMenu {
                Button("删除这条收藏", role: .destructive) {
                    Task { await state.removePassage(id: passage.id) }
                }
            }
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: Metrics.gutter,
                bottom: 0,
                trailing: Metrics.gutter
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.paper)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.eyebrow)
            .tracking(Metrics.eyebrowTracking)
            .foregroundStyle(Palette.inkFaint)
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

        Button(state.isCollected(story) ? "取消收藏" : "收藏") {
            Task { await state.toggleCollection(story) }
        }

        Button(state.isInReadLater(story) ? "从稍后读移除" : "稍后读") {
            Task { await state.toggleReadLater(story) }
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
                state.selectedChannelID = LibraryEntry.collection.rawValue
            } label: {
                Label("收藏", systemImage: LibraryEntry.collection.systemImage)
            }
            .help("查看收藏")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.selectedChannelID = LibraryEntry.readLater.rawValue
            } label: {
                Label("稍后读", systemImage: LibraryEntry.readLater.systemImage)
            }
            .help("查看稍后读")
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
