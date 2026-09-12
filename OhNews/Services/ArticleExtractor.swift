// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit
import WebKit

/// 正文抽取：离屏 WebView 加载页面，再注入 Mozilla Readability.js。
///
/// 这是浏览器阅读模式的同源方案，比自研正文识别规则准确得多，也不用为每个站点打补丁。
/// 代价是需要一个离屏 WebView，因此整个类固定在主线程上。
@MainActor
final class ArticleExtractor: NSObject, WKNavigationDelegate {
    private enum ExtractionError: Error {
        case timeout
        case scriptMissing
    }

    private let webView: WKWebView
    private let readabilityScript: String
    private let loadTimeout: Duration
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(loadTimeout: Duration = .seconds(8)) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // 用一个用完即弃的数据存储，避免第三方站点在应用里留下 Cookie。
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: .zero, configuration: configuration)
        readabilityScript = Self.loadReadabilityScript() ?? ""
        self.loadTimeout = loadTimeout

        super.init()

        webView.navigationDelegate = self
    }

    /// 抽取失败一律返回 nil，由 `ExtractionFallback` 决定降级方式。
    func extract(from url: URL) async -> Article? {
        guard readabilityScript.isEmpty == false else { return nil }

        do {
            let data = try await loadAndExtract(from: url)
            guard let data else { return nil }
            guard let article = try ReadabilityResultParser.parse(from: data, sourceURL: url) else {
                return nil
            }
            // 在数据边界上清理：阅读视图虽然关了 JS，也不该把脚本带进应用。
            let cleaned = Article(
                title: article.title,
                byline: article.byline,
                siteName: article.siteName,
                html: HTMLSanitizer.sanitize(article.html),
                textLength: article.textLength,
                sourceURL: article.sourceURL
            )
            // 应用外壳页面会被 Readability 「成功」抽出一大坨框架标记，这里挡掉。
            return ExtractionQuality.isReadable(cleaned) ? cleaned : nil
        } catch {
            return nil
        }
    }

    private func loadAndExtract(from url: URL) async throws -> Data? {
        try await load(url)
        let jsonString = try await webView.evaluateJavaScript(
            readabilityScript + "\n" + Self.extractionScript
        )

        guard let text = jsonString as? String, text.isEmpty == false else { return nil }
        return Data(text.utf8)
    }

    private func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 20))

            // 超时兜底：某些页面永远不会触发 didFinish，不能让阅读器一直转圈。
            let timeout = loadTimeout
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finishLoad(with: .failure(ExtractionError.timeout))
            }
        }
    }

    private func finishLoad(with result: Result<Void, Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        continuation.resume(with: result)
    }

    private static func loadReadabilityScript() -> String? {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 注入脚本。Readability 是顶层函数声明，所以加载后可直接作为全局函数使用。
    private static let extractionScript = """
    (function () {
      try {
        if (typeof Readability !== "function") { return ""; }
        var article = new Readability(document.cloneNode(true)).parse();
        if (!article || !article.content) { return ""; }
        return JSON.stringify({
          title: article.title || "",
          byline: article.byline || "",
          siteName: article.siteName || "",
          content: article.content || "",
          textContent: article.textContent || "",
          length: article.length || 0
        });
      } catch (error) {
        return "";
      }
    })();
    """

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            finishLoad(with: .success(()))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            finishLoad(with: .failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            finishLoad(with: .failure(error))
        }
    }
}
