import Foundation

/// 一份 feed 的解析结果。
public struct ParsedFeed: Hashable, Sendable {
    /// feed 自身标题，用于给订阅源命名。缺失时为 nil。
    public let title: String?
    public let items: [ParsedFeedItem]

    public init(title: String?, items: [ParsedFeedItem]) {
        self.title = title
        self.items = items
    }
}

/// feed 里的一条内容。
public struct ParsedFeedItem: Hashable, Sendable {
    /// 稳定标识：优先用 feed 提供的 GUID / Atom id，缺失时回落到链接。
    public let identifier: String
    public let title: String
    public let link: URL?
    public let author: String?
    public let publishedAt: Date?
    /// 正文。可能是 HTML 片段，也可能是纯文本，取决于 feed 本身的写法。
    public let content: String?

    public init(
        identifier: String,
        title: String,
        link: URL?,
        author: String?,
        publishedAt: Date?,
        content: String?
    ) {
        self.identifier = identifier
        self.title = title
        self.link = link
        self.author = author
        self.publishedAt = publishedAt
        self.content = content
    }
}

public enum FeedParseError: Error, Equatable {
    /// XML 本身不合法。
    case malformedXML
    /// XML 合法，但不是 RSS / Atom。
    case unsupportedFormat
}

/// RSS 2.0 与 Atom 1.0 的解析。
///
/// 用 `XMLParser` 做流式解析，不引入第三方依赖：feed 的字段集合有限，
/// 自研可以精确控制「缺失字段怎么办」这类分支，也好写单测。
public enum FeedParser {
    public static func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // 保留命名空间前缀，便于识别 `content:encoded` 这类带前缀的元素。
        parser.shouldProcessNamespaces = false
        // 不解析外部实体：feed 是不可信输入。
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw FeedParseError.malformedXML
        }
        guard delegate.recognizedFormat else {
            throw FeedParseError.unsupportedFormat
        }
        return delegate.makeFeed()
    }
}

// MARK: - 解析代理

private final class FeedDelegate: NSObject, XMLParserDelegate {
    private struct BuildItem {
        var title: String?
        var link: URL?
        var author: String?
        var publishedAt: Date?
        var identifier: String?
        /// 正文候选，按字段名收集后再按优先级挑选。
        var contents: [(field: String, text: String)] = []

        /// 正文优先级：结构化的内容优于摘要，摘要优于描述。
        private static let contentPriority = ["encoded", "content", "description", "summary"]

        var content: String? {
            for field in Self.contentPriority {
                if let match = contents.last(where: { $0.field == field && $0.text.isEmpty == false }) {
                    return match.text
                }
            }
            return contents.last { $0.text.isEmpty == false }?.text
        }
    }

    /// 会被捕获文本的元素（已统一为小写本地名）。
    private static let capturedFields: Set<String> = [
        "title", "link", "description", "summary", "content", "encoded",
        "pubdate", "published", "updated", "date",
        "author", "creator", "guid", "id"
    ]

    private(set) var recognizedFormat = false

    private var isAtom = false
    private var feedTitle: String?
    private var feedLink: URL?
    private var current: BuildItem?
    private var items: [BuildItem] = []

    /// 正在捕获的字段名；为 nil 表示当前文本不属于任何关心的字段。
    private var capturing: String?
    /// 捕获目标内部的嵌套深度。用于把 `<description><p>x</p></description>` 里的
    /// 文本一并收进来，而不是被嵌套标签打断。
    private var nestedDepth = 0
    private var buffer = ""

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = localName(elementName)

        switch name {
        case "rss", "rdf":
            recognizedFormat = true
        case "feed":
            isAtom = true
            recognizedFormat = true
        case "item", "entry":
            current = BuildItem()
        case "link":
            // Atom 的链接写在 href 属性上，但只有 rel 为 alternate 的才是文章地址
            // （feed 自己还会提供 rel="self" 的订阅地址）；RSS 的链接是元素文本。
            if isAtom, let href = attributes["href"] {
                let rel = attributes["rel"] ?? "alternate"
                if rel == "alternate" { assignLink(href) }
            }
        default:
            break
        }

        guard FeedDelegate.capturedFields.contains(name) else {
            if capturing != nil { nestedDepth += 1 }
            return
        }

        capturing = name
        nestedDepth = 0
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturing != nil else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard capturing != nil else { return }
        buffer += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = localName(elementName)

        if let capturing {
            if name == capturing, nestedDepth == 0 {
                handleCaptured(field: capturing, text: normalizedText(buffer))
                self.capturing = nil
                buffer = ""
            } else if nestedDepth > 0 {
                nestedDepth -= 1
            }
            return
        }

        switch name {
        case "item", "entry":
            if let current { items.append(current) }
            current = nil
        default:
            break
        }
    }

    // MARK: 内部

    private func handleCaptured(field: String, text: String) {
        switch field {
        case "title":
            if current != nil {
                current?.title = text
            } else if feedTitle == nil {
                feedTitle = text
            }
        case "link":
            assignLink(text)
        case "description", "summary", "content", "encoded":
            if text.isEmpty == false {
                current?.contents.append((field: field, text: text))
            }
        case "pubdate", "published", "updated", "date":
            if current?.publishedAt == nil, let date = FeedDateParser.parse(text) {
                current?.publishedAt = date
            }
        case "author", "creator":
            if let current, current.author == nil, text.isEmpty == false {
                self.current?.author = text
            }
        case "guid", "id":
            if let current, current.identifier == nil, text.isEmpty == false {
                self.current?.identifier = text
            }
        default:
            break
        }
    }

    private func assignLink(_ raw: String) {
        guard let url = absoluteURL(raw) else { return }
        if current != nil {
            current?.link = url
        } else if feedLink == nil {
            feedLink = url
        }
    }

    /// 相对链接按 feed 自身地址补全；`URL(string:relativeTo:)` 对已带 scheme 的地址是幂等的。
    private func absoluteURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        if let url = URL(string: text), url.scheme != nil { return url }
        guard let base = feedLink else { return nil }
        return URL(string: text, relativeTo: base)?.absoluteURL
    }

    private func normalizedText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉命名空间前缀：`content:encoded` → `encoded`。
    private func localName(_ element: String) -> String {
        guard let colon = element.lastIndex(of: ":") else { return element.lowercased() }
        return String(element[element.index(after: colon)...]).lowercased()
    }

    func makeFeed() -> ParsedFeed {
        let parsed = items.compactMap { builder -> ParsedFeedItem? in
            // GUID 与链接都缺的条目无法生成稳定标识，只能跳过。
            let identifier = builder.identifier ?? builder.link?.absoluteString
            guard let identifier, identifier.isEmpty == false else { return nil }

            let title = builder.title ?? ""
            return ParsedFeedItem(
                identifier: identifier,
                // 标题缺失时用标识兜底，避免列表出现空行。
                title: title.isEmpty ? identifier : title,
                link: builder.link,
                author: builder.author,
                publishedAt: builder.publishedAt,
                content: builder.content
            )
        }
        return ParsedFeed(title: feedTitle, items: parsed)
    }
}
