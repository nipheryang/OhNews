import Foundation
import Testing

@testable import OhNewsKit

@Suite("SelectionPersistence")
struct SelectionPersistenceTests {
    /// 每个用例用独立的 suite，避免污染真实偏好与彼此干扰。
    private func makeDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "OhNewsKitTests.Selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    @Test("没有存过任何值时返回 nil")
    func returnsNilWhenNothingStored() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        #expect(persistence.load() == nil)
    }

    @Test("保存后能读回同一个频道")
    func roundTripsChannel() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save("hn:best")

        #expect(persistence.load() == "hn:best")
    }

    @Test("能保存带源前缀的订阅频道")
    func roundTripsFeedChannel() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save("rss:9a1f2b3c")

        #expect(persistence.load() == "rss:9a1f2b3c")
    }

    @Test("保存 nil 会清除已存的值")
    func clearsStoredValueWhenSavingNil() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save("hn:show")
        persistence.save(nil)

        #expect(persistence.load() == nil)
    }

    @Test("空字符串视为没有选择")
    func treatsEmptyStringAsNoSelection() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save("")

        #expect(persistence.load() == nil)
    }
}
