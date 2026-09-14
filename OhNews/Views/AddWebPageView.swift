// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 把一个网页收进收藏夹。
///
/// 与添加订阅的校验方式不同：那里看地址能不能解析成 feed，这里看能不能抽出正文。
/// 一个正常网页不是订阅源，一个订阅源也不是文章，两者失败的原因要分开说，
/// 否则用户会把「这里应该填文章网址」误解成「网址填错了」。
struct AddWebPageView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle
        case working
        case failure(String)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("收藏一篇文章")
                .font(.headline)

            TextField("https://example.com/article", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submit() } }

            statusLine

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("收藏") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedAddress.isEmpty || status == .working)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            Text("粘贴文章网址。正文会被抓取并存在本地，之后打开不联网，也能用翻译与 AI 解读。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在抓取正文…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() async {
        status = .working
        switch await state.addSavedPage(urlText: trimmedAddress) {
        case .success:
            dismiss()
        case .failure(let error):
            status = .failure(error.message)
        }
    }
}
