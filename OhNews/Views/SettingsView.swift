// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import OhNewsKit
import SwiftUI

/// AI 设置。
///
/// 所有改动先落在本地 `config` / `apiKey` 上，点「保存」才写入 UserDefaults 与钥匙串，
/// 避免边输入边写钥匙串。
struct SettingsView: View {
    @Environment(AppState.self) private var state

    @State private var config = AIProviderConfig.default
    @State private var apiKey = ""
    @State private var keyState: AIKeyState = .missing
    @State private var listLimit = ListPreferences.defaultLimit
    @State private var summaryScope = SummaryGenerationScope.fallback
    @State private var insightEnabled = true
    @State private var appearance = AppAppearance.system
    @State private var isConfirmingClearCache = false
    @State private var isConfirmingClearArchives = false
    @State private var status: StatusMessage?
    @State private var isTesting = false
    @State private var isLoaded = false

    private enum StatusMessage {
        case info(String)
        case success(String)
        case failure(String)

        var text: String {
            switch self {
            case .info(let text), .success(let text), .failure(let text): text
            }
        }

        var icon: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .failure: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .failure: .orange
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 摘要", isOn: $config.isEnabled)
            } footer: {
                Text("关闭后应用退回纯阅读器，不会发起任何 AI 请求。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("供应商") {
                Picker("预设", selection: $config.preset) {
                    ForEach(AIProviderPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: config.preset) { _, newValue in
                    config.applyPreset(newValue)
                    status = nil
                    loadStoredKey()
                }

                Text(presetHint)

                TextField("接口地址", text: $config.baseURL)

                if config.isInsecureTransport {
                    Label(
                        "该地址使用明文 http。除本机与局域网服务外，建议改用 https。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if config.preset.requiresAPIKey {
                    SecureField("API Key", text: $apiKey)
                    keyHint
                } else {
                    Label("本地服务不需要 API Key。", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("模型") {
                TextField("摘要模型", text: $config.summaryModel)
                Text("用于列表摘要，建议用便宜快速的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("深度分析模型", text: $config.analysisModel)
                Text("V0 尚未使用，后续做详情级解读时启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("摘要生成") {
                Picker("生成范围", selection: $summaryScope) {
                    ForEach(SummaryGenerationScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .onChange(of: summaryScope) { _, newValue in
                    var preferences = SummaryPreferences()
                    preferences.scope = newValue
                    Task { await state.applySummaryScopeChange() }
                }

                Text(summaryScopeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("正文解读") {
                Toggle("打开正文时自动生成", isOn: $insightEnabled)
                    .onChange(of: insightEnabled) { _, newValue in
                        var preferences = InsightPreferences()
                        preferences.isEnabled = newValue
                        Task { await state.applyInsightEnabledChange() }
                    }

                Text("在正文顶部生成一份解读：正文讲了什么，以及评论区的核心观点与趋势。\n它需要连同正文一起送给模型，因此每打开一篇会调一次 AI（按内容缓存，同一篇不会重复调）。关掉后不再自动生成，但正文里仍可手动重新生成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: appearance) { _, newValue in
                    state.setAppearance(newValue)
                }

                Text("主窗口工具栏上也有一个按钮，可以一键在深色与浅色之间切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("列表") {
                Picker("每次显示条数", selection: $listLimit) {
                    ForEach(ListPreferences.allowedLimits, id: \.self) { limit in
                        Text("\(limit) 条").tag(limit)
                    }
                }
                .onChange(of: listLimit) { _, newValue in
                    var preferences = ListPreferences()
                    preferences.listLimit = newValue
                    Task { await state.applyListLimitChange() }
                }

                Text("同时决定一次抓取多少条、列表最多保留多少条。新内容从顶部插入，超出后从底部移除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("缓存") {
                HStack {
                    Text("当前占用")
                    Spacer()
                    Text(state.cacheSizeText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("删除缓存", role: .destructive) {
                    isConfirmingClearCache = true
                }
                .disabled(state.cacheSizeBytes == 0)

                Text("包括已缓存的内容、已读记录与 AI 摘要。订阅配置与各项设置不会被删除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("收藏存档") {
                LabeledContent("占用") {
                    Text(state.archiveSizeText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("删除全部存档", role: .destructive) {
                    isConfirmingClearArchives = true
                }
                .disabled(state.archiveSizeBytes == 0)

                Text("收藏与稍后读的内容会连正文、译文、讨论区一起存到本地，以后打开不再联网。删除后收藏还在，但下次打开需要重新获取。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("关于") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OhNews")
                        .font(.headline)
                    Text("Hacker News 阅读器 · 版本 \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MIT 开源 · © 2026 Nipher")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("查看开源许可（MIT）") {
                    openBundledDocument(named: "LICENSE", withExtension: nil)
                }

                Button("查看第三方组件声明") {
                    openBundledDocument(named: "THIRD_PARTY_NOTICES", withExtension: "md")
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("测试连接") {
                        Task { await runConnectionTest() }
                    }
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    Button("保存") {
                        Task { await save() }
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if let status {
                    Label(status.text, systemImage: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("「测试连接」会用一条固定的极短内容真实调用一次接口，用来验证地址、密钥、模型名与输出格式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 520)
        .preferredColorScheme(preferredScheme)
        .task {
            load()
            await state.refreshCacheSize()
            await state.refreshArchiveSize()
        }
        .confirmationDialog(
            "删除全部存档？",
            isPresented: $isConfirmingClearArchives
        ) {
            Button("删除", role: .destructive) {
                Task { await state.clearArchives() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("收藏与稍后读会保留，但它们的正文、译文与讨论区副本会被清空，下次打开需要重新获取（译文可能已失效）。")
        }
        .confirmationDialog(
            "删除全部缓存？",
            isPresented: $isConfirmingClearCache
        ) {
            Button("删除", role: .destructive) {
                Task { await state.clearCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已缓存的内容、已读记录与 AI 摘要会被清空，下次打开会重新抓取。订阅配置会保留。")
        }
    }

    private var summaryScopeHint: String {
        switch summaryScope {
        case .leadingItems:
            "自动为列表最前面 \(SummaryPreferences.automaticLimit) 条生成摘要；其余条目可在列表里右键按需生成。"
        case .allItems:
            "自动为列表中所有条目生成摘要。列表条数越多，AI 调用成本越高。"
        case .manual:
            "不自动生成。在列表里右键任意条目，选择「生成 AI 摘要」。"
        }
    }

    private var presetHint: String {
        config.preset.hint
    }

    /// 密钥状态说明。
    ///
    /// 关键是区分「没存过」与「存了但读不到」：后者常见于重新构建后应用签名变化、
    /// 钥匙串授权失效。以前两种都显示「还没有保存密钥」，用户会以为自己的密钥丢了。
    @ViewBuilder
    private var keyHint: some View {
        switch keyState {
        case .present:
            Text("已保存在系统钥匙串；留空并保存会删除已存的密钥。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .missing:
            Text("密钥只写入系统钥匙串，不会进入配置文件或日志。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unreadable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 版本号来自 app bundle，避免与工程里的 `MARKETING_VERSION` 漂移。
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    private func load() {
        guard isLoaded == false else { return }
        config = state.config
        listLimit = ListPreferences().listLimit
        summaryScope = SummaryPreferences().scope
        insightEnabled = InsightPreferences().isEnabled
        appearance = state.appearance
        loadStoredKey()
        isLoaded = true
    }

    /// 让设置窗口跟主窗口保持同一种外观，`nil` 表示跟随系统。
    private var preferredScheme: ColorScheme? {
        switch state.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func loadStoredKey() {
        switch KeychainStore().readOutcome(account: config.preset.keychainAccount) {
        case .found(let value):
            apiKey = value
            keyState = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .missing
                : .present
        case .missing:
            apiKey = ""
            keyState = .missing
        case .denied:
            apiKey = ""
            keyState = .unreadable(
                "钥匙串拒绝读取已保存的密钥。重新构建后的应用签名变化会让授权失效，重新保存一次即可恢复。"
            )
        case .failed(let status):
            apiKey = ""
            keyState = .unreadable("读取钥匙串失败（错误码 \(status)）。")
        }
    }

    private func save() async {
        let keychain = KeychainStore()
        do {
            if config.preset.requiresAPIKey {
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    try keychain.delete(account: config.preset.keychainAccount)
                    keyState = .missing
                } else {
                    try keychain.save(trimmed, account: config.preset.keychainAccount)
                    keyState = .present
                }
            }
        } catch {
            status = .failure("写入钥匙串失败：\((error as NSError).localizedDescription)")
            return
        }

        await state.saveConfig(config)
        status = .success("已保存。")
    }

    /// 许可类文件随应用包分发：MIT 要求把版权声明与许可文本随程序一并交付。
    private func openBundledDocument(named name: String, withExtension ext: String?) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            status = .failure("找不到随应用附带的文档。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runConnectionTest() async {
        isTesting = true
        defer { isTesting = false }

        let result = await state.testAIConnection(config: config, apiKey: apiKey)
        switch result {
        case .success(let summary):
            status = .success("连接成功。模型返回的摘要：\(summary)")
        case .failure(let error):
            status = .failure(error.displayMessage)
        }
    }
}
