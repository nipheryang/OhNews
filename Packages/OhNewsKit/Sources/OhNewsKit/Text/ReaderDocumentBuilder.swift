import Foundation

/// 把正文 HTML 组装成一个完整的阅读文档。
///
/// 阅读视图用 `loadHTMLString` 呈现，所以这里要补上编码声明、`<base>`（让相对路径的图片
/// 能加载）以及排版样式。
public enum ReaderDocumentBuilder {
    public static func build(article: Article, style: String) -> String {
        build(html: article.html, style: style, baseURL: article.sourceURL)
    }

    public static func build(html: String, style: String, baseURL: URL? = nil) -> String {
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        """

        if let baseURL {
            head += "\n<base href=\"\(escapeAttribute(baseURL.absoluteString))\">"
        }

        head += "\n<style>\n\(style)\n</style>"

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        \(head)
        </head>
        <body>
        <article>
        \(html)
        </article>
        </body>
        </html>
        """
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
