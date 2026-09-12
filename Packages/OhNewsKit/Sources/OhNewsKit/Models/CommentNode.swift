// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

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
    public let storyID: String
    public let title: String?
    public let author: String?
    public let points: Int?
    /// 顶层评论。子评论挂在各节点的 `children` 上。
    public let topLevel: [CommentNode]

    public init(
        storyID: String,
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

    /// 按 HN 网页的排名顺序重排顶层评论。
    ///
    /// Algolia 的 `children` 按时间（id 递增）排列，HN 网页则按自己的排名排序。
    /// 未出现在 `rankedIDs` 里的评论保持原有相对顺序，排在后面。
    public func orderingTopLevel(by rankedIDs: [Int]) -> StoryComments {
        guard rankedIDs.isEmpty == false, topLevel.isEmpty == false else { return self }

        var remaining = topLevel
        var ordered: [CommentNode] = []
        for id in rankedIDs {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else { continue }
            ordered.append(remaining.remove(at: index))
        }
        ordered.append(contentsOf: remaining)

        return StoryComments(
            storyID: storyID,
            title: title,
            author: author,
            points: points,
            topLevel: ordered
        )
    }
}
