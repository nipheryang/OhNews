import Foundation
import Testing

@testable import HeyNewsKit

@Suite("SelectionPersistence")
struct SelectionPersistenceTests {
    /// 每个用例用独立的 suite，避免污染真实偏好与彼此干扰。
    private func makeDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "HeyNewsKitTests.Selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    @Test("没有存过任何值时返回 nil")
    func returnsNilWhenNothingStored() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        #expect(persistence.load() == nil)
    }

    @Test("保存后能读回同一个榜单")
    func roundTripsSelection() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save(.best)

        #expect(persistence.load() == .best)
    }

    @Test("存的是未知值时返回 nil，而不是崩溃")
    func returnsNilForUnknownValue() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)
        defaults.set("legacy-list", forKey: "ui.selectedList")

        #expect(persistence.load() == nil)
    }

    @Test("保存 nil 会清除已存的值")
    func clearsStoredValueWhenSavingNil() throws {
        let (defaults, _) = try makeDefaults()
        let persistence = SelectionPersistence(defaults: defaults)

        persistence.save(.show)
        persistence.save(nil)

        #expect(persistence.load() == nil)
    }
}
