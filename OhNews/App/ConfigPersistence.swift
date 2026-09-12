// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import OhNewsKit

/// AI 配置的持久化。只存非敏感字段；API Key 在 Keychain 里。
enum ConfigPersistence {
    private static let key = "ai.provider.config"

    static func load() -> AIProviderConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(AIProviderConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    static func save(_ config: AIProviderConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
