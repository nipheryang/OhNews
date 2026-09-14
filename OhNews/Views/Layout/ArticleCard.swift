// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import SwiftUI

/// 列表条目的卡片外观：**近乎透明的底 + 一圈圆角轮廓线**。
///
/// 抽成一个修饰器，是因为它要覆盖所有清单——文章列表、高亮、收藏夹、稍后读、回收站。
/// 各写一遍的话，下次调样式就得改五处，很快就互相对不上了。
///
/// 两条设计约定：
/// 1. **底色几乎不存在**，把形状交给那一圈轮廓线去表达。少即是多：
///    一旦底色有了存在感，条目就会读成"一块块色块"，与这套单色语言冲突。
/// 2. **留白比内容大一圈**。卡片如果正好裹住文字，会显得局促、像被框住的表格；
///    所以内边距给得比正文行距更宽松，轮廓线落在文字外面一段距离上。
struct ArticleCard: ViewModifier {
    var isSelected = false
    var isHovering = false

    @Environment(\.colorScheme) private var colorScheme

    /// 留白：卡片比内容大一圈。
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 16
    /// 圆角。与正文栏左缘的 18pt 同族，但不至于把短标题的卡片做成胶囊。
    static let cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background {
                shape.fill(fill)
                    .overlay {
                        shape.strokeBorder(line, lineWidth: 1)
                    }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    /// 底色：平时几乎看不见，选中/悬浮时才稍微有一点，用来交代状态。
    private var fill: Color {
        if isSelected { return Palette.selectedWash }
        if isHovering { return Palette.hoverWash }
        // 3% 的墨色：能感觉到底下有一层，但读不出颜色。
        return Palette.ink.opacity(colorScheme == .dark ? 0.05 : 0.03)
    }

    /// 轮廓线——卡片的主要表达。选中时加重，让当前条目跳出来。
    private var line: Color {
        isSelected ? Palette.ink.opacity(0.42) : Palette.line
    }
}

extension View {
    /// 见 `ArticleCard`。所有清单的条目都用它，样式只有一个来源。
    func articleCard(isSelected: Bool = false, isHovering: Bool = false) -> some View {
        modifier(ArticleCard(isSelected: isSelected, isHovering: isHovering))
    }
}
