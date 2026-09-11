import Foundation

public enum PromptVersion {
    /// 改动 `PromptBuilder` 的输出格式或字段含义时递增，已缓存的摘要会自动失效。
    public static let current = "v1"
}
