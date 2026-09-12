// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// HN 官方榜单。
///
/// 原始值直接用于 Firebase 端点名（`topstories` / `beststories` / …）。
/// 展示名不放这里：文案属于界面层，由 app 负责映射。
public enum StoryList: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case top
    case best
    case new
    case ask
    case show

    public var id: String { rawValue }

    /// 例如 `topstories`。
    public var endpointName: String { "\(rawValue)stories" }
}
