import Foundation
import Testing
@testable import OhNewsKit

/// 用例里的数字来自 2026-09-12 对真实站点的实测（见 `ExtractionQuality` 的注释）。
struct ExtractionQualityTests {
    private func article(htmlLength: Int, textLength: Int) -> Article {
        Article(
            title: "t",
            byline: nil,
            siteName: nil,
            html: String(repeating: "a", count: htmlLength),
            textLength: textLength,
            sourceURL: nil
        )
    }

    @Test func acceptsTypicalArticle() {
        // 实测：derflounder.wordpress.com 正文 12522 / 文字 7953
        #expect(ExtractionQuality.isReadable(article(htmlLength: 12522, textLength: 7953)))
        // 实测：tinybird.co 正文 23020 / 文字 20667
        #expect(ExtractionQuality.isReadable(article(htmlLength: 23020, textLength: 20667)))
    }

    @Test func rejectsApplicationShell() {
        // 实测：github.com 仓库页正文 115747 / 文字 1919（比例 0.017）
        #expect(ExtractionQuality.isReadable(article(htmlLength: 115747, textLength: 1919)) == false)
    }

    @Test func skipsRatioCheckForSmallPages() {
        // 实测：example.com 正文 231 / 文字 111，页面本身很短，不应被误判
        #expect(ExtractionQuality.isReadable(article(htmlLength: 231, textLength: 111)))
    }

    @Test func rejectsMarkupWithoutText() {
        #expect(ExtractionQuality.isReadable(article(htmlLength: 50_000, textLength: 0)) == false)
    }

    @Test func boundaryAtInspectionSize() {
        // 刚好达到观察规模且比例为 0.5 → 通过
        #expect(ExtractionQuality.isReadable(article(htmlLength: 2000, textLength: 1000)))
        // 未达观察规模 → 直接通过
        #expect(ExtractionQuality.isReadable(article(htmlLength: 1999, textLength: 1)))
    }
}
