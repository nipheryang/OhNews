// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import OhNewsKit
import SwiftUI

/// 侧栏：按信息源分组展示频道，并提供订阅管理入口。
///
/// 形态对齐博客的页头导航：**纯文字、无图标**，分组标题用等宽大写小字
/// （博客里的 `.eyebrow`）。底色就是纸白，与内容区不做明度区分——
/// 两者的边界交给一条发丝线交代。
struct SidebarView: View {
    @Environment(AppState.self) private var state

    @State private var isAddingSource = false
    @State private var renamingSource: NewsSource?
    @State private var renameText = ""
    @State private var deletingSource: NewsSource?

    var body: some View {
        @Bindable var state = state

        List(selection: $state.selectedChannelID) {
            ForEach(state.channelGroups) { group in
                Section {
                    ForEach(group.channels) { channel in
                        Text(channel.name)
                            .font(Typography.ui)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .tag(channel.id)
                            .contextMenu {
                                if group.source.kind == .rss {
                                    Button("重命名…") {
                                        renameText = group.source.name
                                        renamingSource = group.source
                                    }
                                    Button("删除订阅", role: .destructive) {
                                        deletingSource = group.source
                                    }
                                }
                            }
                    }
                } header: {
                    Text(group.source.name)
                        .font(Typography.eyebrow)
                        .tracking(Metrics.eyebrowTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationSplitViewColumnWidth(min: 188, ideal: 208, max: 260)
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingSource = true
                } label: {
                    Label("添加订阅源", systemImage: "plus")
                }
                .help("添加 RSS / Atom 订阅")
            }
        }
        .sheet(isPresented: $isAddingSource) {
            AddSourceView()
        }
        .alert("重命名订阅", isPresented: renamingBinding) {
            TextField("名称", text: $renameText)
            Button("保存") {
                guard let source = renamingSource else { return }
                let name = renameText
                Task { await state.renameSource(id: source.id, name: name) }
                renamingSource = nil
            }
            Button("取消", role: .cancel) { renamingSource = nil }
        } message: {
            Text("只改显示名称，不影响订阅地址。")
        }
        .confirmationDialog(
            "删除这个订阅？",
            isPresented: deletingBinding,
            presenting: deletingSource
        ) { source in
            Button("删除", role: .destructive) {
                Task { await state.removeSource(id: source.id) }
                deletingSource = nil
            }
            Button("取消", role: .cancel) { deletingSource = nil }
        } message: { source in
            Text("「\(source.name)」将不再刷新。已缓存的内容不会被删除。")
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingSource != nil },
            set: { if $0 == false { renamingSource = nil } }
        )
    }

    private var deletingBinding: Binding<Bool> {
        Binding(
            get: { deletingSource != nil },
            set: { if $0 == false { deletingSource = nil } }
        )
    }
}
