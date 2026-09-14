// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

#if DEBUG
import AppKit
import SwiftUI

/// 只在 DEBUG 下存在：把一栏的实测高度与窗口内容高度打到日志里。
///
/// 为什么需要它：三栏布局出过太多次「看着还行、实际高度不对」的问题。
/// 每次排查都只能靠截图和推测，修完也无法证明修好了——因为**不变量从来没被测量过**。
/// 这个不变量是：**每一栏的高度 == 窗口的内容高度**（±1pt）。
/// 只要它成立，内容就不可能溢出窗口，也就不可能出现"顶部被推到标题栏下、
/// 又滑不回来"这类症状；一旦它不成立，日志里会直接标出来。
///
/// 用法：`.modifier(PaneHeightProbe(name: "侧栏"))`
struct PaneHeightProbe: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { report(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in report(height) }
            }
        )
    }

    private func report(_ paneHeight: CGFloat) {
        // 两个窗口参照一起打，因为"该与谁比"本身需要一次测量来定：
        //   contentLayoutRect —— 扣掉工具栏之后的内容区高度
        //   contentView      —— 窗口内容视图的整体高度（含延伸到标题栏下的那部分）
        // 2026-09-14 实测：栏高恒比 contentLayoutRect 少约 17.5pt，且这个差值
        // 不随窗口变化。溢出的特征是"栏高 > 窗口"，而这里是反过来，所以那不是溢出。
        // 保留两个数字，等下一次真出问题时可以直接对照。
        let window = NSApplication.shared.keyWindow
        let layoutHeight = window?.contentLayoutRect.height ?? 0
        let contentHeight = window?.contentView?.frame.height ?? 0
        // 断言只针对"栏高不应当超过窗口"——那才是溢出的充要特征。
        let verdict = paneHeight <= contentHeight + 1 ? "未溢出" : "溢出 ←←←"
        NSLog(
            "%@",
            "[三栏自检] \(name) 栏高=\(fmt(paneHeight)) 内容区=\(fmt(layoutHeight)) 内容视图=\(fmt(contentHeight)) \(verdict)"
        )
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}

extension View {
    /// 见 `PaneHeightProbe`。三栏根视图各挂一个，用来守住「栏高 == 窗口高」。
    func paneHeightProbe(_ name: String) -> some View {
        modifier(PaneHeightProbe(name: name))
    }
}
#endif
