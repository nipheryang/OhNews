// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 列表为空时的三种状态：首次加载中、取不到数据、确实没有内容。
struct EmptyStateView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        if isLoading {
            ProgressView("正在获取 HN 榜单…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("暂时取不到数据", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试", action: onRetry)
            }
        } else {
            ContentUnavailableView("暂无内容", systemImage: "tray")
        }
    }
}
