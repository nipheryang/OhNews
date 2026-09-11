import Foundation

/// 侧栏榜单选择的持久化。
///
/// 只存一个 `rawValue`，用于重启后回到上次浏览的榜单。
/// `defaults` 可注入，便于在测试里用独立的 suite 验证往返行为。
public struct SelectionPersistence {
    private static let key = "ui.selectedList"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读取上次选中的榜单。没有存过、或存的是未知值（例如榜单被移除）时返回 `nil`。
    public func load() -> StoryList? {
        guard let raw = defaults.string(forKey: Self.key) else { return nil }
        return StoryList(rawValue: raw)
    }

    public func save(_ list: StoryList?) {
        guard let list else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(list.rawValue, forKey: Self.key)
    }
}
