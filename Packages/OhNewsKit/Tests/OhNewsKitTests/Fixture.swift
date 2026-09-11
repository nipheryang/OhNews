import Foundation

/// 测试用的真实接口样本。全部来自线上响应，未做人工改写（除非注释说明）。
enum Fixture {
    enum FixtureError: Error {
        case missingBundleResource(String)
    }

    /// 读取 fixture。默认 `.json`，feed 样本用 ``extension: "xml"``。
    static func data(_ name: String, `extension` fileExtension: String = "json") throws -> Data {
        guard let base = Bundle.module.resourceURL else {
            throw FixtureError.missingBundleResource(name)
        }
        let url = base.appendingPathComponent("Fixtures/\(name).\(fileExtension)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missingBundleResource(name)
        }
        return try Data(contentsOf: url)
    }
}
