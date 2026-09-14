// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

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
    @State private var isAddingPage = false
    @State private var renamingSource: NewsSource?
    @State private var renameText = ""
    @State private var deletingSource: NewsSource?

    var body: some View {
        @Bindable var state = state

        List(selection: $state.selectedChannelID) {
            // 一级功能入口，不放进可折叠的分组里。
            ForEach(LibraryEntry.allCases) { entry in
                sidebarRow(
                    title: entry.title,
                    count: count(for: entry),
                    isSelected: state.selectedChannelID == entry.rawValue,
                    action: entry.addActionTitle == nil ? nil : { isAddingPage = true },
                    help: entry.addActionTitle
                )
                .tag(entry.rawValue)
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.paper)
            }

            // 订阅源是一级分组，下辖各个源（二级），源自己的频道列在源之内。
            sidebarGroupHeader(
                "订阅源",
                action: { isAddingSource = true },
                help: "添加 RSS / Atom 订阅"
            )

            ForEach(state.channelGroups) { group in
                sidebarSubHeader(group.source.name)

                ForEach(group.channels) { channel in
                    sidebarRow(
                        title: channel.name,
                        count: nil,
                        isSelected: state.selectedChannelID == channel.id
                    )
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
                    .listRowInsets(indentedRowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Palette.paper)
                }
            }
        }

        // 整列根视图的高度必须相对窗口而定。
        //
        // 不加这句，List 会按**全部条目的高度**索取空间，NavigationSplitView 把它
        // 当成列高，三列一起被撑高、上下溢出窗口——表现就是侧栏前几行被标题栏盖住，
        // 而且它不是滚动视图，滑不回来。与 2026-09-13 修过的中栏那一例同源，
        // 侧栏当时漏了。（此处的 List 就是整列的根视图；中栏那种"List 外面还套着
        // VStack"的情形不能这么加，会形成约束循环。）
        .containerRelativeFrame(.vertical)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationSplitViewColumnWidth(min: 188, ideal: 208, max: 260)
        .sheet(isPresented: $isAddingSource) {
            AddSourceView()
        }
        .sheet(isPresented: $isAddingPage) {
            AddWebPageView()
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

    /// 分组标题。
    ///
    /// 做成普通行而不是 `Section` header：`.sidebar` 样式下系统会把 header 当成
    /// 选中单元的一部分，选中组内频道时会画上一道系统色描边。不设 `tag`，
    /// 所以它自己也永远不会被选中。
    private func sidebarGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.eyebrow)
            .tracking(Metrics.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 15)
            .padding(.bottom, 3)
            .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.paper)
    }

    /// 一级分组标题。右侧可以带一个添加按钮。
    ///
    /// 做成普通行而不是 `Section` header：`.sidebar` 样式下系统会把 header 当成
    /// 选中单元的一部分，选中组内频道时会画上一道系统色描边。不设 `tag`，
    /// 所以它自己也永远不会被选中。
    private func sidebarGroupHeader(
        _ title: String,
        action: (() -> Void)? = nil,
        help: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Typography.eyebrow)
                .tracking(Metrics.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .help(help ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 15)
        .padding(.bottom, 3)
        .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Palette.paper)
    }

    /// 二级标题：订阅源自己的名字。它下面缩进的就是这个源的频道。
    private func sidebarSubHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.uiSmall)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 10))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.paper)
    }

    /// 侧栏的一行。
    ///
    /// 选中态自己画：系统在 `.sidebar` 样式下不但颜色很重（深色近白、浅色近黑），
    /// 还会把选中行**连同它所属分组的标题**一起染色。行背景铺满纸底色先把系统的
    /// 那层遮掉，再用一条墨色薄雾表示选中。
    private func sidebarRow(
        title: String,
        count: Int?,
        isSelected: Bool,
        action: (() -> Void)? = nil,
        help: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Typography.ui)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let count {
                Text("\(count)")
                    .font(Typography.uiSmall)
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
            }

            // 添加入口贴在行右侧。只有收藏夹有，常驻就好。
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .help(help ?? "")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
                .fill(isSelected ? Palette.sidebarSelection : Color.clear)
        }
        .contentShape(Rectangle())
    }

    /// 行内边距。横向留出一点，让选中块的圆角不贴住侧栏边缘。
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)
    }

    /// 频道行的内边距：比一级入口再缩进一档，体现它属于上面那个源。
    private var indentedRowInsets: EdgeInsets {
        EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 8)
    }

    /// 入口后面的条数。为空时也显示 0，而不是留白。
    private func count(for entry: LibraryEntry) -> Int {
        switch entry {
        case .collection: state.collectionItems.count
        case .highlight: state.passageItems.count
        case .savedPages: state.savedPages.count
        case .readLater: state.readLaterItems.count
        case .trash: state.trashItems.count
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
