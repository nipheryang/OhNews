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
    @State private var readerFontScale = ReaderPreferences.defaultScale
    @State private var trashRetention = TrashRetention.fallback
    @State private var isConfirmingClearCache = false
    @State private var isConfirmingClearArchives = false
    @State private var isConfirmingEmptyTrash = false
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
            case .success: "checkmark.circle.fill"
            case .failure: "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .failure: .red
            }
        }
    }

    @State private var page: SettingsPage?

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                // 推入：新页面从右侧进来，一级往左让出去；返回时反向。
                pageView(for: page)
                    .transition(.move(edge: .trailing))
            } else {
                rootList
                    .transition(.move(edge: .leading))
            }
        }
        // 动画由动作一侧显式驱动（`withAnimation`），不靠 `.animation(value:)`。
        // 上一版用后者时，新页面会停在偏移位置上（一半在窗口外）——过渡没有被真正
        // 驱动起来，只是停在了它的起始状态。
        // 两级用同一个底色：此前一级是 List、二级是 Form，浅色下两级颜色不同，
        // 点进去会有一瞬间的跳脱感。
        .background(Palette.paper)
        .navigationTitle(page?.title ?? "设置")
        .frame(width: 540)
        .frame(minHeight: 560)
        .preferredColorScheme(preferredScheme)
        .task {
            load()
        }
        .alert("清空回收站？", isPresented: $isConfirmingEmptyTrash) {
            Button("清空", role: .destructive) { Task { await state.emptyTrash() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("回收站里的条目会连同离线存档一起删除，之后无法找回。")
        }
        .alert("删除全部离线存档？", isPresented: $isConfirmingClearArchives) {
            Button("删除", role: .destructive) { Task { await state.clearArchives() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("星标、稍后读与收藏夹会保留，但它们的正文、译文与讨论区副本会被清空，下次打开需要重新获取（译文可能已失效）。")
        }
        .alert("删除缓存？", isPresented: $isConfirmingClearCache) {
            Button("删除", role: .destructive) { Task { await state.clearCache() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已缓存的内容、已读记录与 AI 摘要会被清空，下次打开会重新抓取。订阅配置会保留。")
        }
    }

    private var presetHint: String {
        config.preset.hint
    }
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
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    /// 一级：四个分组的入口。做成卡片 + 右侧箭头，与列表里那套外观同一套语言
    /// （圆角、极淡的底、一圈描边），箭头则明示"可以点进去"。
    private var rootList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(SettingsPage.allCases) { item in
                    Button {
                        withAnimation(Motion.pane) { page = item }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(Typography.ui)
                                    .foregroundStyle(Palette.ink)
                                Text(item.summary)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .articleCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    /// 二级：返回按钮 + 这一页的设置项。
    private func pageView(for page: SettingsPage) -> some View {
        VStack(spacing: 0) {
            backButton

            Form {
                switch page {
                case .ai: aiSections
                case .reading: readingSections
                case .data: dataSections
                case .about: aboutSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
        }
    }

    /// 返回按钮：放在**页面内容里、左对齐**，而且做成一枚有底的按钮——
    /// 原来那个是 `NavigationStack` 给的原生箭头，又小又没底、还在顶部中间。
    private var backButton: some View {
        HStack {
            Button {
                withAnimation(Motion.pane) { page = nil }
            } label: {
                Label("返回", systemImage: "chevron.left")
                    .font(Typography.uiSmall)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.ink.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Palette.line, lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 四个分组的内容

    @ViewBuilder
    private var aiSections: some View {
            Section {
                Toggle("启用 AI 摘要", isOn: $config.isEnabled)
            } header: {
                Text("AI").font(.system(size: 13, weight: .semibold))
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
                    // 成功：一个绿勾就够了，不解释。
                    // 失败：红叉后面跟一句简短原因——只说"失败了"用户不知道下一步该改什么。
                    // 更长的细节（例如连接成功时模型返回的摘要）留在悬停提示里。
                    HStack(spacing: 6) {
                        Image(systemName: status.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(status.color)

                        if case .failure = status {
                            Text(status.text)
                                .font(.caption)
                                .foregroundStyle(status.color)
                                .lineLimit(2)
                        }
                    }
                    .help(status.text)
                    .accessibilityLabel(status.text)
                }
            } footer: {
                Text("「测试连接」会用一条固定的极短内容真实调用一次接口，用来验证地址、密钥、模型名与输出格式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("模型") {
                TextField("摘要模型", text: $config.summaryModel)
                Text("用于列表摘要，建议用便宜快速的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("深度分析模型", text: $config.analysisModel)
                Text("用于正文解读等更重的任务。留空则与摘要模型相同。")
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

    }

    @ViewBuilder
    private var readingSections: some View {
            Section("阅读") {
                // 在设置里看不到正文，所以配一行预览。字号只影响正文，
                // 列表的密度是版式的一部分，不跟着变。
                Text("这一段的字号就是正文的字号。")
                    .font(.system(size: state.readerFontScale * 17))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("正文字号")
                    Slider(
                        value: $readerFontScale,
                        in: ReaderPreferences.minimumScale...ReaderPreferences.maximumScale
                    )
                    Text("\(Int((readerFontScale * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .onChange(of: readerFontScale) { _, newValue in
                    state.setReaderFontScale(newValue)
                }

                Text("只影响正文，列表不变。拖动时会重新渲染正文，当前滚动位置会回到开头。")
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

    }

    @ViewBuilder
    private var dataSections: some View {
            Section("离线存档") {
                LabeledContent("占用") {
                    Text(state.archiveSizeText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("删除全部存档", role: .destructive) {
                    isConfirmingClearArchives = true
                }
                .disabled(state.archiveSizeBytes == 0)

                Text("星标、稍后读与收藏夹的内容会连正文、译文、讨论区一起存到本地，以后打开不再联网。删除后条目仍在，但下次打开需要重新获取。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            Section("回收站") {
                Picker("自动清空", selection: $trashRetention) {
                    ForEach(TrashRetention.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .onChange(of: trashRetention) { _, newValue in
                    var preferences = TrashPreferences()
                    preferences.retention = newValue
                    Task { await state.applyTrashRetentionChange() }
                }

                LabeledContent("在站") {
                    Text("\(state.trashItems.count) 篇")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("立即清空", role: .destructive) {
                    isConfirmingEmptyTrash = true
                }
                .disabled(state.trashItems.isEmpty)

                Text("删除收藏夹的单篇、取消星标或从稍后读移除时，文章先进回收站，可以放回原处。到期后连同离线存档一起清掉。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

    }

    @ViewBuilder
    private var aboutSections: some View {
            Section("关于") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OhNews")
                        .font(.headline)
                    Text("新闻阅读器 · 版本 \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MIT 开源 · © 2026 Nipher")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("检查更新") {
                    Task { await state.checkForUpdatesNow() }
                }

                if let message = state.updateCheckMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("启动时会自动检查一次，有新版本会在列表顶部提示。当前安装包未经代码签名，更新需要手动下载安装。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("查看开源许可（MIT）") {
                    openBundledDocument(named: "LICENSE", withExtension: nil)
                }

                Button("查看第三方组件声明") {
                    openBundledDocument(named: "THIRD_PARTY_NOTICES", withExtension: "md")
                }
            }

    }

    private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
        case ai, reading, data, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ai: "AI"
            case .reading: "阅读与外观"
            case .data: "本地数据"
            case .about: "关于"
            }
        }

        /// 一级列表里那行小字：iOS 设置的做法，先把当前状态说清楚，再决定进不进去。
        var summary: String {
            switch self {
            case .ai: "供应商、密钥、模型，以及摘要与正文解读"
            case .reading: "正文字号、列表条数、主题"
            case .data: "离线存档、缓存、回收站"
            case .about: "版本、更新、开源许可"
            }
        }
    }
    private func load() {
        guard isLoaded == false else { return }
        config = state.config
        listLimit = ListPreferences().listLimit
        summaryScope = SummaryPreferences().scope
        insightEnabled = InsightPreferences().isEnabled
        appearance = state.appearance
        readerFontScale = state.readerFontScale
        trashRetention = TrashPreferences().retention
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
