import Foundation

/// OhNews 的纯逻辑层：模型、解析、prompt 组装与降级决策。
///
/// 这里不放任何 SwiftUI / AppKit / WebKit 代码，因此可以用 `swift test` 快速验证。
public enum OhNewsKit {
    /// 包版本，与 app 的 MARKETING_VERSION 保持一致。
    public static let version = "0.1.0"
}
