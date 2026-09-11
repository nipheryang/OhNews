import Foundation

/// HN 评论节点，对应 Algolia items 接口返回的 children 结构。
public struct CommentNode: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let author: String?
    /// 评论正文（HTML）。
    public let text: String?
    public let points: Int?
    public let createdAt: Date?
    public let children: [CommentNode]

    public init(
        id: Int,
        author: String?,
        text: String?,
        points: Int?,
        createdAt: Date?,
        children: [CommentNode]
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.points = points
        self.createdAt = createdAt
        self.children = children
    }

    /// 含自身在内的节点总数。
    public static func count(in nodes: [CommentNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count(in: $1.children) }
    }

    /// 扁平化后的所有后代（深度优先）。
    public var flattened: [CommentNode] {
        children.reduce(into: children) { result, node in
            result.append(contentsOf: node.flattened)
        }
    }
}

/// 一个 story 的评论树。
public struct StoryComments: Codable, Hashable, Sendable {
    public let storyID: Int
    public let title: String?
    public let author: String?
    public let points: Int?
    /// 顶层评论。子评论挂在各节点的 `children` 上。
    public let topLevel: [CommentNode]

    public init(
        storyID: Int,
        title: String?,
        author: String?,
        points: Int?,
        topLevel: [CommentNode]
    ) {
        self.storyID = storyID
        self.title = title
        self.author = author
        self.points = points
        self.topLevel = topLevel
    }

    /// 递归统计的评论总数（含子评论）。
    public var totalCount: Int { CommentNode.count(in: topLevel) }
}
