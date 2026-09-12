// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 用户添加的信息源配置。
///
/// 与内容缓存分开落盘（`sources.json`）：清理缓存不应该把用户订阅的源一起丢掉。
/// 这里只存配置（源 ID、类型、显示名、feed 地址），不存条目内容。
///
/// 内置的 Hacker News 由代码提供（`HackerNewsSource`），不进这个文件，
/// 因此用户不会误删它，重新安装也不会多出一条重复记录。
public actor SourcesPersistence {
    private static let fileName = "sources.json"

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var sources: [NewsSource]

    /// - Parameter directory: 数据目录。传 nil 时与内容缓存放在同一目录。
    public init(directory: URL? = nil) {
        let base = directory ?? CacheStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let url = base.appendingPathComponent(Self.fileName)
        self.fileURL = url

        if let data = try? Data(contentsOf: url),
           let loaded = try? decoder.decode([NewsSource].self, from: data) {
            self.sources = loaded
        } else {
            self.sources = []
        }
    }

    /// 用户添加的全部源，顺序与添加顺序一致。
    public func all() -> [NewsSource] {
        sources
    }

    public func source(id: String) -> NewsSource? {
        sources.first { $0.id == id }
    }

    /// 追加一个源。ID 已存在时覆盖（用于更新 feed 标题）。
    public func upsert(_ source: NewsSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        save()
    }

    public func remove(id: String) {
        let before = sources.count
        sources.removeAll { $0.id == id }
        guard sources.count != before else { return }
        save()
    }

    public func replaceAll(_ newSources: [NewsSource]) {
        sources = newSources
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(sources) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
