import AppKit
import HeyNewsKit
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

    var body: some View {
        if let story = state.selectedStory {
            VStack(spacing: 0) {
                header(for: story)
                Divider()
                content(for: story)
            }
        } else {
            ContentUnavailableView(
                "选择一条新闻",
                systemImage: "newspaper",
                description: Text("左侧切换榜单，中间选择条目。")
            )
        }
    }

    // MARK: - 头部

    private func header(for story: Story) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle(for: story))
                    .font(.headline)
                    .lineLimit(2)
                Text(headerSubtitle(for: story))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let url = story.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("浏览器打开", systemImage: "safari")
                }
                .controlSize(.small)
            }

            Button {
                Task { await state.reloadArticle(for: story) }
            } label: {
                Label("重新抓取", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(state.readerState == .loading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func headerTitle(for story: Story) -> String {
        if case .article(let article) = state.readerState, let title = article.title {
            return title
        }
        return story.title
    }

    private func headerSubtitle(for story: Story) -> String {
        var parts: [String] = []
        if let host = story.sourceHost {
            parts.append(host)
        } else {
            parts.append("HN 自述帖")
        }
        parts.append("\(story.score) 分")
        parts.append("\(story.commentCount) 条评论")
        parts.append(story.author)
        return parts.joined(separator: " · ")
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(for story: Story) -> some View {
        switch state.readerState {
        case .idle:
            ContentUnavailableView(
                "还没有打开正文",
                systemImage: "doc.text",
                description: Text("在中间列表点选一条内容即可阅读。")
            )

        case .loading:
            ProgressView("正在抓取正文…")
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
            """
            这个站点没有返回可解析的正文，常见原因是付费墙或反爬限制。
            这条内容还有 \(story.commentCount) 条 HN 评论，评论阅读界面会在 V1 提供。
            """
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
