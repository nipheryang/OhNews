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
                    // 解读是浮层（overlay），不是流式的一块：正文在它后面滑过，
                    // 文字经过下边缘时被玻璃遮住。正文自身的顶部留白由 `topInset`
                    // 交给文档，这样开头不会被面板永远挡住。
                    content(for: story)
                        .overlay(alignment: .top) {
                            insight(for: story)
                        }
                }
            } else {
                emptyState
            }
        }
        .background(Palette.paper)
        // 与中栏同一个道理：`WKWebView` 会按正文内容高度索取空间，长文章（几千点的
        // 内容）会把这个需求传给 `NavigationSplitView`，三列便都按那个高度布局，
        // 窗口装不下就溢出——侧栏被挤到可视区之上而空白，正文上方也被裁掉。
        // 正文自己会在 WebView 内部滚动，外层高度取容器即可。
        .containerRelativeFrame(.vertical)
        // 正文状态切换用短交叉淡化，不位移：阅读时内容位置跳动比“没有动画”更难受。
        .animation(
            reduceMotion ? nil : Motion.standard,
            value: state.readerState
        )
    }

    /// 正文之上的 AI 解读。没有可显示的解读时不占任何位置。
    @ViewBuilder
    private func insight(for story: Story) -> some View {
        if state.insightState != .unavailable {
            InsightCardView(state: state.insightState) {
                Task { await state.regenerateInsight() }
            }
            .animation(reduceMotion ? nil : Motion.standard, value: state.insightState)
        }
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
                    // 星标与稍后读用填充态表示已保存，与工具栏的同名入口一致。
                    ReaderActionButton(title: isCollected ? "取消星标" : "星标") {
                        Task { await state.toggleCollection(story) }
                    } label: {
                        Image(systemName: isCollected ? "star.fill" : "star")
                    }

                    ReaderActionButton(title: isInReadLater ? "从稍后读移除" : "加入稍后读") {
                        Task { await state.toggleReadLater(story) }
                    } label: {
                        Image(systemName: isInReadLater ? "clock.badge.checkmark.fill" : "clock")
                    }

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

    private var isCollected: Bool {
        guard let story = state.selectedStory else { return false }
        return state.isCollected(story)
    }

    private var isInReadLater: Bool {
        guard let story = state.selectedStory else { return false }
        return state.isInReadLater(story)
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
            readerWebView(html: html, baseURL: nil, story: story)
        } else {
            originalContent(for: story)
        }
    }

    /// 正文渲染的唯一入口。
    ///
    /// 四种正文形态（正常、自述帖、降级、译文）共用它，高亮与跳转才
    /// 不会只在一部分场景里能用。
    private func readerWebView(html: String, baseURL: URL?, story: Story) -> some View {
        // 跳转目标只在它确实属于当前这篇时才生效。
        let target = state.pendingScroll?.itemID == story.id
            ? state.pendingScroll?.paragraphIndex
            : nil
        // 顶部浮层占掉多少，正文就让出多少。解读不可用时不留白。
        let inset = state.insightState == .unavailable ? 0 : InsightCardView.height

        return ArticleWebView(
            html: html,
            baseURL: baseURL,
            discussionHTML: state.displayDiscussionHTML,
            scrollTarget: target,
            topInset: inset,
            highlightedParagraphs: state.highlightedParagraphs(for: story),
            contextMenuItems: { readerContextMenu(for: story) }
        )
    }

    /// 正文右键菜单的内容。
    ///
    /// 这里就是以后加功能的地方：往数组里添一项，菜单里就多一条，
    /// 不需要动事件处理那一层。数组为空时正文里右键不会弹任何菜单。
    private func readerContextMenu(for story: Story) -> [ReaderContextMenuItem] {
        [
            ReaderContextMenuItem(title: "高亮选中内容") { selection in
                Task {
                    await state.savePassage(
                        text: selection.text,
                        paragraphIndex: selection.paragraphIndex ?? -1,
                        for: story
                    )
                }
            }
        ]
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
            readerWebView(
                html: article.html,
                baseURL: article.sourceURL ?? story.url,
                story: story
            )

        case .selfPost(let html):
            readerWebView(
                html: HTMLSanitizer.sanitize(html),
                baseURL: nil,
                story: story
            )

        case .degraded(let level):
            // 正文取不到时，讨论区往往正是用户想看的内容，所以降级也走同一渲染通道，
            // 把提示与讨论放进同一份文档。
            readerWebView(
                html: noticeHTML(for: level, story: story),
                baseURL: nil,
                story: story
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

/// 阅读视图里要执行的脚本。
///
/// 阅读视图关闭了页面脚本，但应用侧 `evaluateJavaScript` 不受这个开关限制：
/// 用它注入段落编号、读取选区。选区读取需要连同所在段落的编号一起拿到，
/// 所以两段脚本都写成自执行函数并返回一个值。
enum ReaderScript {
    /// 给正文的块级元素按 DOM 顺序挂上 `p-<序号>`。
    ///
    /// 每次加载后重新编号，序号只保证在一次渲染内稳定（与跳转目标一致）。
    static let tagParagraphs = """
    (function () {
      var blocks = document.querySelectorAll(
        'article p, article h2, article h3, article h4, article h5, article h6,' +
        'article blockquote, article pre, article li'
      );
      for (var i = 0; i < blocks.length; i++) {
        blocks[i].id = 'p-' + i;
      }
      return blocks.length;
    })()
    """

    /// 读选区，并给出它所在的段落编号。段落编号拿不到时为 -1。
    /// 返回 JSON 字符串，因为在两个系统之间只能传基础类型。
    static let readSelection = """
    (function () {
      var selection = window.getSelection();
      var text = selection ? selection.toString() : '';
      var index = -1;
      if (selection && selection.rangeCount > 0 && text.trim().length > 0) {
        var node = selection.getRangeAt(0).startContainer;
        if (node && node.nodeType !== 1) { node = node.parentNode; }
        while (node && node !== document.body) {
          if (node.id && node.id.indexOf('p-') === 0) {
            index = parseInt(node.id.substring(2), 10);
            break;
          }
          node = node.parentNode;
        }
      }
      return JSON.stringify({ text: text, index: index });
    })()
    """

    /// 给高亮的段落打上标记类，其余段落先清掉。
    ///
    /// 只加 class 不动节点结构：段落号 `p-<序号>` 是按 DOM 顺序生成的，
    /// 包裹一层元素会让序号错位，之前的跳转就指到别处了。
    static func markHighlights(_ indexes: [Int]) -> String {
        let list = indexes.map(String.init).joined(separator: ",")
        return """
        (function () {
          var marked = document.querySelectorAll('.ohnews-highlight');
          for (var i = 0; i < marked.length; i++) {
            marked[i].classList.remove('ohnews-highlight');
          }
          var wanted = [\(list)];
          var count = 0;
          for (var j = 0; j < wanted.length; j++) {
            var block = document.getElementById('p-' + wanted[j]);
            if (block) {
              block.classList.add('ohnews-highlight');
              count++;
            }
          }
          return count;
        })()
        """
    }

    /// 把某一段滚到视野中央，并用一条临时轮廓标出来。
    /// 轮廓自己会消失，不需要另一段脚本来清。
    static func scrollToParagraph(_ index: Int) -> String {
        """
        (function () {
          var block = document.getElementById('p-\(index)');
          if (!block) { return false; }
          block.scrollIntoView({ block: 'center', behavior: 'auto' });
          var previous = block.style.outline;
          var previousOffset = block.style.outlineOffset;
          block.style.outline = '2px solid rgba(127, 127, 127, 0.55)';
          block.style.outlineOffset = '6px';
          window.setTimeout(function () {
            block.style.outline = previous;
            block.style.outlineOffset = previousOffset;
          }, 1600);
          return true;
        })()
        """
    }
}

/// 阅读视图。
///
/// 关闭 JavaScript 并用 `loadHTMLString` 呈现已清理的正文；链接点击交给系统浏览器，
/// 避免阅读器被导航到别的页面。
///
/// 正文的右键菜单由 `ReaderContextMenuController` 接管，不再出现 WebKit 的系统菜单；
/// 要往菜单里加功能，传一个非空的 `contextMenuItems` 即可。
struct ArticleWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    /// 讨论区段落，为 nil 时不渲染。
    var discussionHTML: String?
    /// 需要滚动到的段落编号。用后由 `AppState` 清掉，避免下次重新渲染又跳。
    var scrollTarget: Int?
    /// 正文顶部预留的高度，让正文从顶部浮层下边缘开始。
    var topInset: CGFloat = 0
    /// 需要标黄的段落编号（高亮）。
    var highlightedParagraphs: [Int] = []
    /// 正文右键菜单里的项。返回空数组时，正文里右键什么也不发生。
    var contextMenuItems: () -> [ReaderContextMenuItem] = { [] }

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
        // 在事件分发前接管右键，WebKit 的系统菜单就不会再出来。
        context.coordinator.installContextMenu(in: webView, items: contextMenuItems)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateContextMenu(items: contextMenuItems)

        let document = ReaderDocumentBuilder.build(
            html: html,
            style: ReaderStyle.css,
            baseURL: baseURL,
            discussionHTML: discussionHTML,
            topInset: topInset
        )
        guard context.coordinator.loadedDocument != document else {
            // 文档没变。高亮是后加的标记，不需要重新加载整篇就能更新。
            context.coordinator.applyHighlights(highlightedParagraphs, in: webView)
            context.coordinator.scrollIfNeeded(in: webView, target: scrollTarget)
            return
        }
        context.coordinator.loadedDocument = document
        // 新文档加载后，旧编号已失效，要让下一次跳转重新执行。
        context.coordinator.appliedScrollTarget = nil
        // 标记随文档一起没了，清掉记录让 didFinish 重新打一遍。
        context.coordinator.appliedHighlights = []
        context.coordinator.highlightedParagraphs = highlightedParagraphs
        context.coordinator.pendingScrollTarget = scrollTarget
        webView.loadHTMLString(document, baseURL: baseURL)
    }

    /// 视图销毁时卸掉事件监听，否则每换一篇文章都会留下一个。
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.uninstallContextMenu()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedDocument: String?
        /// 文档还没加载完时记下要跳的位置。
        var pendingScrollTarget: Int?
        /// 已经跳过的位置，用来避免重复触发。
        var appliedScrollTarget: Int?
        /// 当前要标黄的段落。文档重载后由 `didFinish` 重新打一遍。
        var highlightedParagraphs: [Int] = []
        /// 已经打上的高亮，用来避免重复跑脚本。
        var appliedHighlights: [Int] = []

        private let contextMenu = ReaderContextMenuController()

        func installContextMenu(
            in webView: WKWebView,
            items: @escaping () -> [ReaderContextMenuItem]
        ) {
            contextMenu.install(in: webView, items: items)
        }

        func updateContextMenu(items: @escaping () -> [ReaderContextMenuItem]) {
            contextMenu.update(items: items)
        }

        func uninstallContextMenu() {
            contextMenu.uninstall()
        }

        /// 文档加载完成：先给段落编号，标黄，再做挂起的跳转。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(ReaderScript.tagParagraphs) { _, _ in
                // 编号出来了才找得到段落，标记必须排在后面。
                self.applyHighlights(self.highlightedParagraphs, in: webView, force: true)
                guard let target = self.pendingScrollTarget else { return }
                self.pendingScrollTarget = nil
                self.scrollIfNeeded(in: webView, target: target)
            }
        }

        /// 给高亮段落打标记。重复调用无副作用，脚本自己会先清旧的。
        func applyHighlights(
            _ indexes: [Int],
            in webView: WKWebView,
            force: Bool = false
        ) {
            let sorted = indexes.sorted()
            highlightedParagraphs = sorted
            guard force || sorted != appliedHighlights else { return }
            appliedHighlights = sorted
            webView.evaluateJavaScript(ReaderScript.markHighlights(sorted)) { _, _ in }
        }

        func scrollIfNeeded(in webView: WKWebView, target: Int?) {
            guard let target, target != appliedScrollTarget else { return }
            appliedScrollTarget = target
            webView.evaluateJavaScript(ReaderScript.scrollToParagraph(target)) { _, _ in }
        }

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


