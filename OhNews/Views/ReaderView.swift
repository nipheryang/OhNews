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
                    readerNoticeBar
                    // 解读面板不在这里：它是正文文档里的一段，因此随正文一起滚，
                    // 而不是钉在阅读区顶部（见 InsightPanel）。
                    content(for: story)
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
        // 正文状态切换用短交叉淡化，不位移：阅读时内容位置跳动比“没有动画”更难受。
        .animation(
            reduceMotion ? nil : Motion.standard,
            value: state.readerState
        )
        .animation(reduceMotion ? nil : Motion.standard, value: state.transientNotice)
    }

    /// 阅读区自己的轻提示。
    ///
    /// 正文里发起的操作（高亮、取消高亮）结果提示在这里，与列表顶部那条同款：
    /// 用户的目光还在正文上，提示要在他的视线范围内。
    ///
    /// 它是流式的一块，出现时会把正文压下去一点。选这个而不是浮层，是因为
    /// 浮层要盖住顶部几行字，而这几行往往正是用户刚操作过的地方。
    @ViewBuilder
    private var readerNoticeBar: some View {
        if let notice = state.transientNotice, state.noticePlacement == .reader {
            HStack(spacing: 8) {
                Text(notice)
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
            ? state.pendingScroll?.highlight
            : nil
        return ArticleWebView(
            html: html,
            baseURL: baseURL,
            discussionHTML: state.displayDiscussionHTML,
            scrollTarget: target,
            insightHTML: InsightPanel.html(for: state.insightState),
            highlights: state.highlights(for: story),
            fontScale: state.readerFontScale,
            performBubbleAction: { action in
                Task { await state.performBubbleAction(action, for: story) }
            },
            selectionClearTicket: state.selectionClearTicket
        )
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
/// 一条高亮：段落序号 + 当时选中的原文。
///
/// 光有段落号只能整段上色，而要标的是选中那一截，所以连文字一起带上。
struct ReaderHighlight: Equatable, Sendable {
    let paragraphIndex: Int
    let text: String
}

enum ReaderScript {
    /// 把一段文字变成 JS 字符串字面量。
    ///
    /// 用 JSON 转义：引号、反斜杠、换行都由它处理，手写拼接容易漏。
    private static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2
        else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

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

    /// 气泡的构造函数。标记高亮与划选后弹气泡两处都要用，
    /// 所以拼成一段共用的脚本片段，各自放在自己的 IIFE 里。
    private static let bubbleFactory = """
      // 悬停在高亮上时浮出来的工具条。
      //
      // 和划选那条是同一个组件，只是按钮一上来就是按下态（这段文字本来
      // 就有高亮），点它是取消。位置按这一条高亮的矩形算：横向对着它居中，
      // 纵向坐在它上方 8px——两处都是量出来的，所以长句子、跨行的句子
      // 都不会跑偏。量之前必须先入文档，脱开的元素量出来全是 0。
      function attachHoverToolbar(host, text, index) {
        // 工具条必须挂在 .ohnews-bubble 这个零尺寸锚点里。
        // 样式表就是这么写的：锚点提供定位上下文，悬停显隐也靠
        // `mark:hover .ohnews-bubble .ohnews-toolbar` 这一条。
        // 直接挂到 mark 上，两条规则都不成立——工具条既不会隐藏，
        // 偏移的参照物也不对，最后飘在看不见的地方。
        var anchorEl = document.createElement('span');
        anchorEl.className = 'ohnews-bubble';

        var bar = document.createElement('div');
        bar.className = 'ohnews-toolbar';

        var button = document.createElement('span');
        button.className = 'ohnews-toolbar-button';
        button.setAttribute('data-ohnews-action', 'unhighlight');
        button.setAttribute('data-ohnews-text', text);
        button.setAttribute('data-ohnews-index', String(index));
        button.setAttribute('data-ohnews-active', '1');
        button.setAttribute('title', '取消高亮');
        button.innerHTML = \(quoted(markerIcon));
        bar.appendChild(button);
        anchorEl.appendChild(bar);
        host.appendChild(anchorEl);

        var hostBox = host.getBoundingClientRect();
        var barBox = bar.getBoundingClientRect();
        var anchor = anchorEl.getBoundingClientRect();

        // 横向：对着这一条高亮居中，再夹在正文左右边界里。
        var page = document.body.getBoundingClientRect();
        var margin = 8;
        var left = hostBox.left + hostBox.width / 2 - barBox.width / 2;
        left = Math.max(page.left + margin, Math.min(left, page.right - margin - barBox.width));

        // 纵向：下沿停在高亮上方 8px。
        // 注意 bottom 到的是"元素下沿"，所以这里给的是下沿的目标位置，
        // 不能再减一次工具条高度——减了它会整整高出 40px。
        var gap = 8;
        var barBottom = hostBox.top - gap;

        // 换算成相对锚点（.ohnews-bubble，它在高亮末尾、零尺寸）的偏移。
        bar.style.right = (anchor.right - (left + barBox.width)) + 'px';
        bar.style.bottom = (anchor.bottom - barBottom) + 'px';

        return bar;
      }
    """

    /// 在段落里定位选中的那段文字，只把它包起来，并在末尾挂上气泡。
    ///
    /// 先拆掉上一次的标记并合并文本节点——不还原就直接再标，
    /// 第二次会在被拆碎的节点里找不全原文。
    ///
    /// 找不到原文（文章重新抓取过、选中的是跨节点的片段）时整段上色：
    /// 宁可标大了，也比让它默默消失强。
    static func markHighlights(_ highlights: [ReaderHighlight]) -> String {
        let payload = highlights.map { ["index": $0.paragraphIndex, "text": $0.text] as [String: Any] }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"

        return """
        (function () {
          var wanted = \(json);

          \(bubbleFactory)

          function unwrapAll() {
            // 气泡要先摘掉。它挂在 mark 里面，而拆开 mark 只把子节点留在原地，
            // 于是气泡会变成段落后代里的一块垃圾，越积越多。
            var bubbles = document.querySelectorAll('.ohnews-bubble');
            for (var b = 0; b < bubbles.length; b++) {
              if (bubbles[b].parentNode) {
                bubbles[b].parentNode.removeChild(bubbles[b]);
              }
            }

            var old = document.querySelectorAll('mark.ohnews-highlight, .ohnews-highlight');
            for (var i = 0; i < old.length; i++) {
              var el = old[i];
              var parent = el.parentNode;
              if (!parent) { continue; }
              if (el.tagName === 'MARK') {
                while (el.firstChild) { parent.insertBefore(el.firstChild, el); }
                parent.removeChild(el);
              } else {
                el.classList.remove('ohnews-highlight');
                // 整段上色时原文存在块自己身上，也要清掉。
                el.removeAttribute('data-ohnews-text');
              }
              parent.normalize();
            }
          }

          // 把 [from, to) 这一段文字包进 mark，可能跨多个文本节点。
          // 返回包出来的那几个 mark，好把气泡挂到最后一个（也就是这条高亮的末尾）。
          function wrapRange(block, needle) {
            var texts = [];
            var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null);
            var node;
            while ((node = walker.nextNode())) { texts.push(node); }

            var starts = [];
            var full = '';
            for (var i = 0; i < texts.length; i++) {
              starts.push(full.length);
              full += texts[i].nodeValue;
            }

            var at = full.indexOf(needle);
            if (at < 0) {
              // 整段找不到时的退路：逐级缩短，找它还在的最长前缀。
              // 找不到就整段上色太重了——用户点了一句话，不该有整段被标黄。
              var shares = [0.75, 0.5, 0.25];
              for (var t = 0; t < shares.length; t++) {
                var cut = Math.max(8, Math.floor(needle.length * shares[t]));
                if (cut >= needle.length) { continue; }
                at = full.indexOf(needle.substring(0, cut));
                if (at >= 0) { needle = needle.substring(0, cut); break; }
              }
              at = full.indexOf(needle);
              if (at < 0) { return null; }
            }
            var end = at + needle.length;

            var made = [];
            // 从后往前切：splitText 会把后面的节点挪位，倒着处理才不会乱。
            for (var k = texts.length - 1; k >= 0; k--) {
              var from = starts[k];
              var to = from + texts[k].nodeValue.length;
              var lo = Math.max(at, from);
              var hi = Math.min(end, to);
              if (lo >= hi) { continue; }

              var piece = texts[k].splitText(lo - from);
              piece.splitText(hi - lo);

              var mark = document.createElement('mark');
              mark.className = 'ohnews-highlight';
              mark.setAttribute('data-ohnews-text', needle);
              piece.parentNode.insertBefore(mark, piece);
              mark.appendChild(piece);
              made.unshift(mark);
            }
            return made.length > 0 ? made : null;
          }

          unwrapAll();

          // 第一遍：只做标记，**不往段落里插任何东西**。
          //
          // 工具条里带着"取消高亮"这几个字。一边标记一边把它挂进段落，
          // 段落文字就不再连续——后一条与它重叠的高亮会因此搜不到自己的原文，
          // 退化成"整段上色"。这正是重复高亮把整段标黄的原因。
          // 所以标记与挂工具条分成两遍。
          var placed = [];
          for (var j = 0; j < wanted.length; j++) {
            var item = wanted[j];
            var block = document.getElementById('p-' + item.index);
            if (!block) { continue; }

            var marks = wrapRange(block, item.text);
            if (marks) {
              placed.push({ block: block, text: item.text, index: item.index });
            } else {
              block.classList.add('ohnews-highlight');
              block.setAttribute('data-ohnews-text', item.text);
              placed.push({ block: block, text: item.text, index: item.index });
            }
          }

          // 两条高亮互相重叠时，内层那个 mark 会嵌在外层里面：底色叠两层、
          // 两颗工具条挤在一起。把内层拆掉，只留外层——重叠的那一段仍然是
          // 高亮的，只是由外层代表它。
          var nested = document.querySelectorAll('mark.ohnews-highlight mark.ohnews-highlight');
          for (var n = 0; n < nested.length; n++) {
            var inner = nested[n];
            var host = inner.parentNode;
            if (!host) { continue; }
            while (inner.firstChild) { host.insertBefore(inner.firstChild, inner); }
            host.removeChild(inner);
            host.normalize();
          }

          // 第二遍：标记都落定了才挂工具条。按原文重新找一次宿主，
          // 因为上一步可能把某条高亮的 mark 拆掉了（那一条在正文里由外层代表）。
          for (var k = 0; k < placed.length; k++) {
            var want = placed[k];
            var targets = [];

            var found = want.block.querySelectorAll('mark.ohnews-highlight');
            for (var m = 0; m < found.length; m++) {
              if (found[m].getAttribute('data-ohnews-text') === want.text) { targets.push(found[m]); }
            }
            if (want.block.classList.contains('ohnews-highlight') &&
                want.block.getAttribute('data-ohnews-text') === want.text) {
              targets.push(want.block);
            }

            // 一段高亮可能被拆成几块：选中的文字跨过元素边界时（比如中间那个词
            // 被 <span> 或 <code> 包着，末尾还带一个 &nbsp;），每一块都是一个 mark。
            // 每块都挂一条工具条——只挂最后一块的话，鼠标放到前半句就只会亮、
            // 不会弹菜单。
            for (var t = 0; t < targets.length; t++) {
              attachHoverToolbar(targets[t], want.text, want.index);
            }
          }

          return document.querySelectorAll('mark.ohnews-highlight').length;
        })()
        """
    }

    /// 工具条上那颗「高亮」图标：一支斜置的马克笔，下面一道划痕。
    ///
    /// 用内联 SVG 而不是 SF Symbol——正文是网页，系统符号在这里用不了。
    /// 划痕用高亮色，与正文里标出来的颜色是同一个，一眼对得上。
    private static let markerIcon = """
    <svg viewBox="0 0 16 16" width="17" height="17" aria-hidden="true" focusable="false">
      <g transform="rotate(-45 8 8)">
        <rect x="5.9" y="2.3" width="4.2" height="6.9" rx="1.2" fill="currentColor"></rect>
        <path d="M6.6 9.4 H9.4 L8.7 12.4 H7.3 Z" fill="currentColor" opacity="0.45"></path>
      </g>
      <path class="ohnews-marker-swipe" d="M2.6 14.3 H13.4" stroke-width="1.7"
            stroke-linecap="round" fill="none"></path>
    </svg>
    """

    /// 划选结束后在选区上方浮出一条工具条。
    ///
    /// 选区自己不会上报"我选好了"，所以由应用侧在抬起鼠标时调这里。
    /// 工具条按**文档坐标**安放（不是视口坐标），这样它跟着正文一起滚。
    ///
    /// `known` 是这篇文章已有的高亮（`[{"index": n, "text": "…"}]`）：
    /// 选中的文字如果正是其中一条，按钮就显示按下态，再点是取消。
    /// 否则同一个按钮点下去会被存储层拒掉（重复），等于点了没反应。
    ///
    /// 返回 JSON `{"text": …, "index": …}`，选不中东西时返回 null。
    static func showSelectionToolbar(
        x: Double,
        y: Double,
        known: [[String: Any]],
        isClick: Bool
    ) -> String {
        let knownJSON = (try? JSONSerialization.data(withJSONObject: known))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"

        return """
        (function () {
          var known = \(knownJSON);

          // 只收划选那一条，不碰高亮里挂着的悬停工具条。
          function clearSelectionBar() {
            var old = document.querySelectorAll('.ohnews-toolbar-selection');
            for (var i = 0; i < old.length; i++) {
              if (old[i].parentNode) { old[i].parentNode.removeChild(old[i]); }
            }
          }

          // **点击**落在工具条或气泡上时不重建：那一下点的就是按钮或圆点。
          // 拖动不在此列——划选结束的那一点常常正好压在某条高亮的圆点上，
          // 那不是"点在气泡上"，用户是在选文字。
          if (\(isClick ? "true" : "false")) {
            var hit = document.elementFromPoint(\(x), \(y));
            if (hit && hit.closest && hit.closest('.ohnews-toolbar, .ohnews-bubble')) {
              return null;
            }
          }

          clearSelectionBar();

          var selection = window.getSelection();
          if (!selection || selection.rangeCount === 0) { return null; }

          var text = selection.toString().trim();
          if (text.length === 0) { return null; }

          var range = selection.getRangeAt(0);

          // 选区落在气泡或工具条自己身上时不弹。
          var anchor = range.startContainer;
          if (anchor && anchor.nodeType !== 1) { anchor = anchor.parentNode; }
          if (anchor && anchor.closest && anchor.closest('.ohnews-bubble, .ohnews-toolbar')) {
            return null;
          }

          // 选区落在哪一段。拿不到就给 -1。
          var index = -1;
          var node = range.startContainer;
          if (node && node.nodeType !== 1) { node = node.parentNode; }
          while (node && node !== document.body) {
            if (node.id && node.id.indexOf('p-') === 0) {
              var parsed = parseInt(node.id.substring(2), 10);
              if (!isNaN(parsed)) { index = parsed; }
              break;
            }
            node = node.parentNode;
          }

          var already = false;
          for (var k = 0; k < known.length; k++) {
            if (known[k].text === text && known[k].index === index) { already = true; break; }
          }

          var rects = range.getClientRects();
          if (rects.length === 0) { return null; }
          var first = rects[0];
          var last = rects[rects.length - 1];
          var bounds = range.getBoundingClientRect();

          var bar = document.createElement('div');
          // 带上专属类：清理时只认它。
          // 高亮里的那些悬停工具条也是 .ohnews-toolbar——按类名清会把它们一起删掉，
          // 而它们只有文章重新加载才会重建，于是"划过一次之后所有高亮都弹不出菜单"。
          bar.className = 'ohnews-toolbar ohnews-toolbar-selection';

          var button = document.createElement('span');
          button.className = 'ohnews-toolbar-button';
          button.setAttribute('data-ohnews-action', already ? 'unhighlight' : 'highlight');
          button.setAttribute('data-ohnews-text', text);
          button.setAttribute('data-ohnews-index', String(index));
          button.setAttribute('title', already ? '取消高亮' : '高亮');
          if (already) { button.setAttribute('data-ohnews-active', '1'); }
          button.innerHTML = \(quoted(markerIcon));
          bar.appendChild(button);

          // 先入文档再量，否则量出来全是 0，也就摆不对位置。
          document.body.appendChild(bar);
          var barBox = bar.getBoundingClientRect();

          // 横向：对着选区居中，再夹在正文的左右边界里，免得贴边被裁。
          var page = document.body.getBoundingClientRect();
          var margin = 8;
          var left = bounds.left + window.scrollX + (bounds.width - barBox.width) / 2;
          var minLeft = page.left + window.scrollX + margin;
          var maxLeft = page.right + window.scrollX - barBox.width - margin;
          if (maxLeft < minLeft) { maxLeft = minLeft; }
          left = Math.max(minLeft, Math.min(left, maxLeft));

          // 纵向：默认浮在选区上方；上面放不下就翻到选区下方。
          var gap = 8;
          var above = first.top - barBox.height - gap;
          var top = above >= margin
            ? above
            : last.bottom + gap;
          top += window.scrollY;

          bar.style.left = Math.round(left) + 'px';
          bar.style.top = Math.round(top) + 'px';

          return JSON.stringify({ text: text, index: index });
        })()
        """
    }

    /// 收走正文里的选区。标完之后那块蓝色选中还压在刚变黄的文字上，
    /// 看着像没生效。
    static let clearSelection = """
    (function () {
      var selection = window.getSelection();
      if (selection) { selection.removeAllRanges(); }
      return true;
    })()
    """

    /// 把解读面板填进文档里预留的空容器。
    ///
    /// 面板在文档流里，长高会把下面的正文一起往下推。读者正看的那一段不能因此
    /// 跳走：记下填之前容器的高度，填完之后按高度差把滚动位置补回来。
    /// 已经在最顶上（滚动量为 0）时不补——那时面板本来就该出现在正文之前。
    static func setInsightHTML(_ html: String) -> String {
        """
        (function () {
          var slot = document.getElementById('ohnews-insight');
          if (!slot) { return false; }

          var before = slot.getBoundingClientRect().height;
          slot.innerHTML = \(quoted(html));
          var after = slot.getBoundingClientRect().height;

          var delta = after - before;
          if (delta !== 0 && window.scrollY > 0) {
            window.scrollTo(0, window.scrollY + delta);
          }
          return Math.round(delta);
        })()
        """
    }

    /// 收走划选留下的那一条工具条。
    ///
    /// 只认 `.ohnews-toolbar-selection`：高亮里的悬停工具条同样带 `.ohnews-toolbar`，
    /// 按那个类名清会把它们全删掉，那之后悬停就不再弹菜单了。
    static let clearSelectionToolbar = """
    (function () {
      var old = document.querySelectorAll('.ohnews-toolbar-selection');
      for (var i = 0; i < old.length; i++) {
        if (old[i].parentNode) { old[i].parentNode.removeChild(old[i]); }
      }
      return old.length;
    })()
    """

    /// 这一点上有没有可以点的东西。
    ///
    /// 页面脚本关着，气泡和工具条都点不动，只能由应用侧读文档判断点了哪里。
    /// 认的是 `data-ohnews-action` 这个标记：气泡里的字条和工具条上的按钮
    /// 都带着它，所以两边共用这一条路径，加功能时不必再改这里。
    /// 返回 JSON `{"action": …, "text": …, "index": …}`，没命中时返回 null。
    static func hitTestBubbleItem(x: Double, y: Double) -> String {
        """
        (function () {
          var el = document.elementFromPoint(\(x), \(y));
          if (!el || !el.closest) { return null; }

          var item = el.closest('[data-ohnews-action]');
          if (!item) { return null; }

          var index = parseInt(item.getAttribute('data-ohnews-index'), 10);
          return JSON.stringify({
            action: item.getAttribute('data-ohnews-action') || '',
            text: item.getAttribute('data-ohnews-text') || '',
            index: isNaN(index) ? -1 : index
          });
        })()
        """
    }

    /// 把某一段滚到视野中央，并让**被点的那一条**高亮闪一下。
    ///
    /// 只闪文字对得上的那一个标记：同一段里可能有几条不相干的高亮，
    /// 让它们一起闪等于在说"你点的是这些"。
    ///
    /// 以前这里给整段描一圈轮廓当落点提示，但它读起来像"选中了这一整段"——
    /// 用户只是从高亮列表跳过来，并没有选任何东西。
    static func scrollToParagraph(_ index: Int, text: String) -> String {
        let needle = quoted(text)

        return """
        (function () {
          var block = document.getElementById('p-\(index)');
          if (!block) { return false; }
          block.scrollIntoView({ block: 'center', behavior: 'auto' });

          var needle = \(needle);
          var target = null;

          var marks = block.querySelectorAll('mark.ohnews-highlight');
          for (var i = 0; i < marks.length; i++) {
            if (marks[i].getAttribute('data-ohnews-text') === needle) {
              target = marks[i];
              break;
            }
          }
          if (!target &&
              block.classList.contains('ohnews-highlight') &&
              block.getAttribute('data-ohnews-text') === needle) {
            target = block;
          }
          if (!target) { return true; }

          target.classList.remove('ohnews-highlight-flash');
          // 读一次布局，强制重排：否则同一个元素连着闪两次不会重放动画。
          void target.offsetWidth;
          target.classList.add('ohnews-highlight-flash');
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
    /// 需要滚动到的段落。用后由 `AppState` 清掉，避免下次重新渲染又跳。
    var scrollTarget: ReaderHighlight?
    /// 正文顶部那块 AI 解读面板的 HTML。空字符串表示这块不占位置。
    var insightHTML: String = ""
    /// 要标黄的高亮（段落号 + 选中的原文）。
    var highlights: [ReaderHighlight] = []
    /// 正文字号倍数。
    var fontScale: Double = 1.0
    /// 气泡菜单里点了某一项。高亮与取消高亮都从这里出去。
    var performBubbleAction: (ReaderAction) -> Void = { _ in }
    /// 票号变了就请在正文里收一下选区和划选气泡。
    var selectionClearTicket: Int = 0

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
        context.coordinator.installInteraction(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.performBubbleAction = performBubbleAction
        context.coordinator.highlights = highlights
        context.coordinator.insightHTML = insightHTML
        context.coordinator.applyInsight(insightHTML, in: webView)
        context.coordinator.clearSelectionIfTicked(selectionClearTicket, in: webView)

        let document = ReaderDocumentBuilder.build(
            html: html,
            style: ReaderStyle.css,
            baseURL: baseURL,
            discussionHTML: discussionHTML,
            fontScale: fontScale
        )
        guard context.coordinator.loadedDocument != document else {
            // 文档没变。高亮是后加的标记，不需要重新加载整篇就能更新。
            context.coordinator.applyHighlights(highlights, in: webView)
            context.coordinator.scrollIfNeeded(in: webView, target: scrollTarget)
            return
        }
        context.coordinator.loadedDocument = document
        // 新文档加载后，旧编号已失效，要让下一次跳转重新执行。
        context.coordinator.appliedScrollTarget = nil
        // 标记随文档一起没了，清掉记录让 didFinish 重新打一遍。
        context.coordinator.appliedHighlights = []
        // 新文档里那个容器是空的，要让下一次把面板重新填进去。
        context.coordinator.invalidateInsight()
        context.coordinator.pendingScrollTarget = scrollTarget
        webView.loadHTMLString(document, baseURL: baseURL)
    }

    /// 视图销毁时卸掉事件监听，否则每换一篇文章都会留下一个。
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.uninstallInteraction()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedDocument: String?
        /// 文档还没加载完时记下要跳的位置。
        var pendingScrollTarget: ReaderHighlight?
        /// 已经跳过的位置，用来避免重复触发。
        var appliedScrollTarget: ReaderHighlight?
        /// 当前要高亮的文段。文档重载后由 `didFinish` 重新打一遍。
        var highlights: [ReaderHighlight] = []
        /// 已经打上的高亮，用来避免重复跑脚本。
        var appliedHighlights: [ReaderHighlight] = []
        /// 气泡菜单被点中时执行什么。
        var performBubbleAction: (ReaderAction) -> Void = { _ in }
        /// 已经处理到哪一张票。
        private var handledSelectionClearTicket = 0
        /// 已经填进文档的解读面板。没变就不必再写一次（写一次会动滚动位置）。
        private var appliedInsightHTML: String?
        /// 当前该填进文档的面板 HTML。文档加载完成时要靠它重填。
        var insightHTML: String = ""

        private let interaction = ReaderInteractionController()

        func installInteraction(in webView: WKWebView) {
            interaction.install(
                in: webView,
                highlights: { [weak self] in self?.highlights ?? [] },
                perform: { [weak self] action in self?.performBubbleAction(action) }
            )
        }

        func uninstallInteraction() {
            interaction.uninstall()
        }

        /// 文档换了，之前填进去的面板跟着没了，记下这件事。
        func invalidateInsight() {
            appliedInsightHTML = nil
        }

        /// 把解读面板填进文档里预留的空容器。
        ///
        /// 面板在文档流里，撑高会把下面的正文往下推——所以脚本会按高度差
        /// 把滚动位置补回来，读者正看的那一段不会跳走。
        ///
        /// - Parameter force: 新文档里那个容器是空的，必须在 `didFinish` 里重填一次
        ///   （那里绕开去重）。平时的调用要去重，否则状态每变一次就把面板重写一遍。
        func applyInsight(_ html: String, in webView: WKWebView, force: Bool = false) {
            guard force || html != appliedInsightHTML else { return }
            appliedInsightHTML = html
            webView.evaluateJavaScript(ReaderScript.setInsightHTML(html)) { _, _ in }
        }

        /// 票号前进过就收一次选区和工具条。
        func clearSelectionIfTicked(_ ticket: Int, in webView: WKWebView) {
            guard ticket != handledSelectionClearTicket else { return }
            handledSelectionClearTicket = ticket
            interaction.clearSelectionToolbar(in: webView)
        }

        /// 文档加载完成：先给段落编号，标黄，再做挂起的跳转。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 面板要在这里填回去。
            //
            // `updateNSView` 那次调用跑在 `loadHTMLString` 之前，推给的是上一份文档；
            // 新文档里的容器是空的。少了这一句，读者要等到解读生成完、状态再变一次
            // 才看得见面板——表现就是内容"闪"出来，而不是一开始就有一块正在生成的盒子。
            // 放在最前面：面板会把正文往下推，先定下文档高度再处理跳转。
            applyInsight(insightHTML, in: webView, force: true)

            webView.evaluateJavaScript(ReaderScript.tagParagraphs) { _, _ in
                // 编号出来了才找得到段落，标记必须排在后面。
                self.applyHighlights(self.highlights, in: webView, force: true)
                guard let target = self.pendingScrollTarget else { return }
                self.pendingScrollTarget = nil
                self.scrollIfNeeded(in: webView, target: target)
            }
        }

        /// 给高亮打标记。重复调用无副作用，脚本自己会先拆掉旧的。
        func applyHighlights(
            _ marks: [ReaderHighlight],
            in webView: WKWebView,
            force: Bool = false
        ) {
            let ordered = marks.sorted { $0.paragraphIndex < $1.paragraphIndex }
            highlights = ordered
            guard force || ordered != appliedHighlights else { return }
            appliedHighlights = ordered
            webView.evaluateJavaScript(ReaderScript.markHighlights(ordered)) { _, _ in }
        }

        /// 跳到最后一次请求的段落。
        ///
        /// 只有脚本确认找到了那一段，才记下"跳过了"：正文还在加载时这一段并不存在，
        /// 那时就记账的话，等正文真的到了也不会再跳——用户点了高亮却停在文章开头。
        ///
        /// 目标带上原文，是因为闪动只该落在被点的那一条上：同一段里可能有几条
        /// 互不相干的高亮。
        func scrollIfNeeded(in webView: WKWebView, target: ReaderHighlight?) {
            guard let target, target != appliedScrollTarget else { return }
            let script = ReaderScript.scrollToParagraph(target.paragraphIndex, text: target.text)
            webView.evaluateJavaScript(script) { result, _ in
                guard (result as? Bool) == true else { return }
                self.appliedScrollTarget = target
            }
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
