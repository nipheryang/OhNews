import Foundation

public enum HNParseError: Error, Equatable {
    case malformedJSON
}

/// HN 接口响应解析器。
///
/// 纯函数、不触网，所有分支都用固定 fixture 做回归测试。
public enum HNJSONParser {
    // MARK: - 接口结构

    /// Firebase `item/<id>.json` 的结构。字段全部可选：HN 上已删除/被标记的条目会缺字段。
    private struct ItemDTO: Decodable {
        let id: Int?
        let type: String?
        let by: String?
        let title: String?
        let url: String?
        let score: Int?
        let time: Int?
        let descendants: Int?
        let text: String?
        let deleted: Bool?
        let dead: Bool?
    }

    /// Algolia `items/<id>` 的结构（递归）。
    private struct AlgoliaItemDTO: Decodable {
        let id: Int?
        let title: String?
        let author: String?
        let points: Int?
        let created_at_i: Int?
        let text: String?
        let children: [AlgoliaItemDTO]?
    }

    // MARK: - 解析

    /// 榜单 ID 列表。
    public static func parseStoryIDs(from data: Data) throws -> [Int] {
        do {
            return try JSONDecoder().decode([Int].self, from: data)
        } catch {
            throw HNParseError.malformedJSON
        }
    }

    /// 单条 item。
    ///
    /// 已删除、被标记或缺少标题的条目返回 `nil`——这是正常情况而非错误，
    /// 只有 JSON 结构本身不可解析时才抛错。
    public static func parseStory(from data: Data) throws -> Story? {
        let dto: ItemDTO
        do {
            dto = try JSONDecoder().decode(ItemDTO.self, from: data)
        } catch {
            throw HNParseError.malformedJSON
        }

        guard let id = dto.id, let title = dto.title, title.isEmpty == false else { return nil }
        if dto.deleted == true || dto.dead == true { return nil }

        return Story(
            id: SourceIdentifier.itemID(
                sourceID: HackerNewsSource.sourceID,
                rawID: String(id)
            ),
            sourceID: HackerNewsSource.sourceID,
            title: title,
            url: dto.url.flatMap { URL(string: $0) },
            score: dto.score ?? 0,
            author: dto.by ?? "",
            postedAt: Date(timeIntervalSince1970: TimeInterval(dto.time ?? 0)),
            commentCount: dto.descendants ?? 0,
            type: ItemType(lenient: dto.type),
            text: dto.text
        )
    }

    /// 一个 story 的完整评论树。缺少 id 时返回 `nil`。
    public static func parseStoryComments(from data: Data) throws -> StoryComments? {
        let dto: AlgoliaItemDTO
        do {
            dto = try JSONDecoder().decode(AlgoliaItemDTO.self, from: data)
        } catch {
            throw HNParseError.malformedJSON
        }

        guard let id = dto.id else { return nil }

        return StoryComments(
            storyID: SourceIdentifier.itemID(
                sourceID: HackerNewsSource.sourceID,
                rawID: String(id)
            ),
            title: dto.title,
            author: dto.author,
            points: dto.points,
            topLevel: mapComments(dto.children ?? [])
        )
    }

    private static func mapComments(_ dtos: [AlgoliaItemDTO]) -> [CommentNode] {
        dtos.map { dto in
            CommentNode(
                id: dto.id ?? 0,
                author: dto.author,
                text: dto.text,
                points: dto.points,
                createdAt: dto.created_at_i.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                children: mapComments(dto.children ?? [])
            )
        }
    }
}
