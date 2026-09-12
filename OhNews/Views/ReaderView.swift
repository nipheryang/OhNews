// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

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

                // 操作只留图标：阅读区的主路径是“读”，按钮越多越吵。
                HStack(spacing: 2) {
                    if let url = story.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("在浏览器中打开", systemImage: "safari")
                        }
                        .help("在浏览器中打开")
                    }

                    Button {
                        Task { await state.reloadArticle(for: story) }
                    } label: {
                        Label("重新抓取", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.readerState == .loading)
                    .help("重新抓取正文")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.inkFaint)
            }

            Text(headerTitle(for: story))
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
            ArticleWebView(html: article.html, baseURL: article.sourceURL ?? story.url)

        case .selfPost(let html):
            ArticleWebView(html: HTMLSanitizer.sanitize(html), baseURL: nil)

        case .degraded(let level):
            degradedView(story: story, level: level)

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

    @ViewBuilder
    private func degradedView(story: Story, level: ReadingLevel) -> some View {
        ContentUnavailableView {
            Label(title(for: level), systemImage: "doc.questionmark")
        } description: {
            Text(description(for: level, story: story))
        } actions: {
            HStack {
                if let url = story.url {
                    Button("在浏览器中打开") { NSWorkspace.shared.open(url) }
                }
                Button("重新抓取") { Task { await state.reloadArticle(for: story) } }
            }
        }
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

/// 阅读视图。
///
/// 关闭 JavaScript 并用 `loadHTMLString` 呈现已清理的正文；链接点击交给系统浏览器，
/// 避免阅读器被导航到别的页面。
struct ArticleWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

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
        let document = ReaderDocumentBuilder.build(html: html, style: ReaderStyle.css, baseURL: baseURL)
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
