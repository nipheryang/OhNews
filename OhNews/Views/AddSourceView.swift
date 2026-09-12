// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 添加 RSS / Atom 订阅。
///
/// 保存前会真实抓取一次：地址填错或对方不是订阅源时当场给出原因，
/// 而不是先存下来、之后在列表里一直报错。
struct AddSourceView: View {
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
            Text("添加订阅")
                .font(.headline)

            TextField("https://example.com/feed", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submit() } }

            statusLine

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { Task { await submit() } }
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
            Text("填入订阅地址后会自动抓取一次，确认能解析才会保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在抓取并解析…")
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
        guard trimmedAddress.isEmpty == false else { return }
        status = .working

        switch await state.addSource(feedURLText: trimmedAddress) {
        case .success:
            dismiss()
        case .failure(let error):
            status = .failure(error.message)
        }
    }
}
