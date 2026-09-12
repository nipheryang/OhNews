// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import OhNewsKit
import SwiftUI
import WebKit

/// 阅读器的排版样式，来自应用包内的 reader.css。
enum ReaderStyle {
    static let css: String = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "css"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "body { font: 16px/1.7 -apple-system, system-ui; padding: 24px 32px; }"
        }
        return text
    }()
}

/// 详情区：把 `AppState.readerState` 映射成具体的呈现方式。
struct StoryDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 讨论区最多渲染多少条由 `AppState` 统一控制，视图不再自己定阈值。

    /// 降级场景的提示，转成与讨论区同一份文档里的 HTML。

    var body: some View {
        Group {
            if let story = state.selectedStory {
                VStack(spacing: 0) {
                    header(for: story)
                    hairline
                    content(for: story)
                }
            } else {
                emptyState
            }
        }
        .background(Palette.paper)
        // 正文状态切换用短交叉淡化，不位移：阅读时内容位置跳动比“没有动画”更难受。
        .animation(
            reduceMotion ? nil : Motion.standard,
            value: state.readerState
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: Metrics.hairline)
    }

    /// 空状态：衬线标题 + 等宽提示，与整套排版语言一致。
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("选择一条新闻")
                .font(Typography.emptyStateTitle)
                .foregroundStyle(Palette.ink)

            Text(emptyHint)
                .font(Typography.meta)
                .tracking(Metrics.metaTracking)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 空状态不只是“什么都没选”，得告诉用户当前在哪个频道、下一步做什么。
    private var emptyHint: String {
        guard let name = state.selectedChannel?.name else {
            return "在中间列表选中条目，正文会显示在这里。"
        }
        return "当前频道「\(name)」· 选中条目后正文显示在这里"
    }

    // MARK: - 头部

    /// 头部按博客的文章页编排：等宽眉标在上，衬线大标题在下。
    private func header(for story: Story) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(headerEyebrow(for: story))
                    .font(Typography.readerMeta)
                    .tracking(Metrics.metaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                // 操作只留图标：阅读区的主路径是「读」，按钮越多越吵。
                // 但图标要够大、间距要够松，否则几个按钮挤成一团反而更难用。
                HStack(spacing: 4) {
                    if let url = story.url {
                        ReaderActionButton(title: "在浏览器中打开") {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }

                    ReaderActionButton(title: "重新抓取正文") {
                        Task { await state.reloadArticle(for: story) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(state.readerState == .loading)

                    // 只在真有可翻内容（或正在翻）时出现：降级场景下没什么可翻。
                    if state.canTranslate || isTranslating {
                        ReaderActionButton(title: translationButtonHelp) {
                            Task { await state.toggleTranslation() }
                        } label: {
                            TranslationGlyph(
                                symbol: translationButtonIcon,
                                progress: translationProgress
                            )
                        }
                        // 未配置 AI 时置灰；但翻译中仍可点，用于取消。
                        .disabled(state.canTranslate == false && isTranslating == false)
                    }
                }
            }

            Text(state.displayTitle ?? headerTitle(for: story))
                .font(Typography.readerTitle)
                .foregroundStyle(Palette.ink)
                .lineSpacing(Typography.readerTitleLineSpacing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        // 先限定正文宽度再加内边距，才能和 `reader.css` 的
        // `max-width: 720px` + `padding: 0 40px`（content-box）对上升，
        // 否则头部会比正文窄 40pt，两栏看起来错位。
        .frame(maxWidth: Metrics.readerMaxWidth, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func headerTitle(for story: Story) -> String {
        if case .article(let article) = state.readerState, let title = article.title {
            return title
        }
        return story.title
    }

    /// 眉标：来源 · 分数 · 评论 · 作者，全部压成一行等宽小字。
    private func headerEyebrow(for story: Story) -> String {
        var parts: [String] = []
        parts.append(story.sourceHost ?? "自述帖")
        if let score = story.score {
            parts.append("\(score) 分")
        }
        if let commentCount = story.commentCount {
            parts.append("\(commentCount) 评论")
        }
        parts.append(story.author)
        return parts.joined(separator: " · ")
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(for story: Story) -> some View {
        // 显示译文时用译文；讨论区也跟着切（两者一起翻的）。
        if case .showingTranslation = state.translationState, let html = state.displayArticleHTML {
            ArticleWebView(
                html: html,
                baseURL: nil,
                discussionHTML: state.displayDiscussionHTML
            )
        } else {
            originalContent(for: story)
        }
    }

    // MARK: - 翻译按钮

    private var isTranslating: Bool {
        if case .translating = state.translationState { return true }
        return false
    }

    /// 0…1 的翻译进度；未在翻译时为 nil。
    ///
    /// 段落数还没拿到的准备阶段返回 0，而不是 nil——这一小段时间也要有可见
    /// 的反馈，否则点下去像没点上。
    private var translationProgress: Double? {
        guard case .translating(let done, let total) = state.translationState else {
            return nil
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    private var translationButtonIcon: String {
        switch state.translationState {
        case .showingOriginal: "translate"
        case .translating: "translate"
        case .showingTranslation: "arrow.uturn.backward"
        case .failed: "arrow.clockwise"
        }
    }

    private var translationButtonHelp: String {
        if state.canTranslate == false && isTranslating == false {
            return "需要先在设置里启用 AI 才能翻译"
        }
        return switch state.translationState {
        case .showingOriginal: "把全文翻译成中文"
        case .translating: "点击取消翻译"
        case .showingTranslation: "切回原文"
        case .failed: "重新翻译"
        }
    }

    @ViewBuilder
    private func originalContent(for story: Story) -> some View {
        switch state.readerState {
        case .idle:
            VStack(spacing: 10) {
                Text("还没有打开正文")
                    .font(Typography.emptyStateTitle)
                    .foregroundStyle(Palette.ink)
                Text("在中间列表点选一条内容即可阅读")
                    .font(Typography.meta)
                    .tracking(Metrics.metaTracking)
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .article(let article):
            ArticleWebView(
                html: article.html,
                baseURL: article.sourceURL ?? story.url,
                discussionHTML: state.displayDiscussionHTML
            )

        case .selfPost(let html):
            ArticleWebView(
                html: HTMLSanitizer.sanitize(html),
                baseURL: nil,
                discussionHTML: state.displayDiscussionHTML
            )

        case .degraded(let level):
            // 正文取不到时，讨论区往往正是用户想看的内容，所以降级也走同一渲染通道，
            // 把提示与讨论放进同一份文档。
            ArticleWebView(
                html: noticeHTML(for: level, story: story),
                baseURL: nil,
                discussionHTML: state.displayDiscussionHTML
            )

        case .failed(let message):
            ContentUnavailableView {
                Label("正文获取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let url = story.url {
                    Button("在浏览器中打开") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    /// 降级场景的提示，转成与讨论区同一份文档里的 HTML。
    private func noticeHTML(for level: ReadingLevel, story: Story) -> String {
        let heading = escapeHTML(title(for: level))
        let body = paragraphs(description(for: level, story: story))
        return "<div class=\"reader-notice\"><h2>\(heading)</h2>\(body)</div>"
    }

    private func paragraphs(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined()
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func title(for level: ReadingLevel) -> String {
        switch level {
        case .article: "已获取正文"
        case .titleAndComments: "没有取到正文"
        case .titleOnly: "这条没有可读正文"
        }
    }

    private func description(for level: ReadingLevel, story: Story) -> String {
        switch level {
        case .article:
            "正文已经显示在下方。"
        case .titleAndComments:
            if let count = story.commentCount, count > 0 {
                """
                这个站点没有返回可解析的正文，常见原因是付费墙或反爬限制。
                这条内容还有 \(count) 条评论，评论阅读界面会在后续版本提供。
                """
            } else {
                """
                这个站点没有返回可解析的正文，常见原因是付费墙或反爬限制。
                """
            }
        case .titleOnly:
            """
            既没有可解析的正文，也没有评论可以看。
            可以直接用上面的「浏览器打开」按钮查看原始链接。
            """
        }
    }
}

/// 阅读器头部的操作按钮。
///
/// 图标本身要够大好点，同时保持克制：悬停时只给一层极淡的底色，
/// 不做外发光或位移，否则会和「安静阅读」的基调冲突。
private struct ReaderActionButton<Content: View>: View {
    let title: String
    let action: () -> Void
    let content: Content

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) {
        self.title = title
        self.action = action
        self.content = label()
    }

    var body: some View {
        Button(action: action) {
            content
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radiusSmall + 3, style: .continuous)
                        .fill(isHovering && isEnabled ? Palette.hoverWash : Color.clear)
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: Metrics.radiusSmall + 3, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Palette.inkSoft : Palette.inkFaint)
        .onHover { hovering in
            withAnimation(Motion.standard) { isHovering = hovering }
        }
        .help(title)
    }
}

/// 翻译按钮的图标。
///
/// 翻译中在图标外围画一圈进度：既看得出在动，也看得出剩多少。
/// 段落数还没拿到时没有真实进度可报，就画一圈旋转的弧（不确定进度），
/// 让点击立刻有反馈。
private struct TranslationGlyph: View {
    let symbol: String
    /// 0…1；`nil` 表示不在翻译中；0 表示已在翻译但尚无进度。
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    /// 圆环直径与线宽。图标与圆环共用同一直径并各自居中，两者才会同心。
    private let diameter: CGFloat = 28
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .frame(width: diameter, height: diameter)

            if let progress {
                if progress > 0 {
                    arc(to: progress)
                        .animation(Motion.standard, value: progress)
                } else {
                    // 准备阶段：一段短弧匀速旋转。
                    arc(to: 0.28)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .animation(
                            reduceMotion
                                ? nil
                                : .linear(duration: 0.9).repeatForever(autoreverses: false),
                            value: isSpinning
                        )
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { isSpinning = (progress == 0) }
        .onChange(of: progress) { _, newValue in
            // 只有准备阶段（0）才旋转；拿到真实进度后切回确定进度。
            isSpinning = (newValue == 0)
        }
    }

    /// 从 12 点方向顺时针画一段弧。
    private func arc(to fraction: Double) -> some View {
        Circle()
            .trim(from: 0, to: max(0.05, fraction))
            .stroke(
                Palette.inkSoft,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
    }
}

/// 阅读视图。
///
/// 关闭 JavaScript 并用 `loadHTMLString` 呈现已清理的正文；链接点击交给系统浏览器，
/// 避免阅读器被导航到别的页面。
struct ArticleWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    /// 讨论区段落，为 nil 时不渲染。
    var discussionHTML: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let document = ReaderDocumentBuilder.build(
            html: html,
            style: ReaderStyle.css,
            baseURL: baseURL,
            discussionHTML: discussionHTML
        )
        guard context.coordinator.loadedDocument != document else { return }
        context.coordinator.loadedDocument = document
        webView.loadHTMLString(document, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedDocument: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}

