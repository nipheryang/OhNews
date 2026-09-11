import HeyNewsKit
import SwiftUI

/// 应用根视图。M0 阶段只做骨架占位，M2 会替换为三栏 `NavigationSplitView`。
struct RootView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("HeyNews")
                .font(.system(size: 34, weight: .semibold))
            Text("Hacker News 阅读器 · v\(HeyNewsKit.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    RootView()
}
