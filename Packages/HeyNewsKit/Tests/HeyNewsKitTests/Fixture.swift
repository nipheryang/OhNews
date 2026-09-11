import Foundation

/// 测试用的真实接口样本。全部来自线上响应，未做人工改写（除非注释说明）。
enum Fixture {
    enum FixtureError: Error {
        case missingBundleResource(String)
    }

    static func data(_ name: String) throws -> Data {
        guard let base = Bundle.module.resourceURL else {
            throw FixtureError.missingBundleResource(name)
        }
        let url = base.appendingPathComponent("Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missingBundleResource(name)
        }
        return try Data(contentsOf: url)
    }
}
