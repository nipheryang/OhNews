// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public enum PromptVersion {
    /// 改动 `PromptBuilder` 的输出格式或字段含义时递增，已缓存的摘要会自动失效。
    ///
    /// v2：system 段按来源种类生成，正文不再限定于自述帖，措辞去掉 HN 专有说法。
    public static let current = "v2"
}
