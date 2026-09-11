import OhNewsKit
import SwiftUI

/// 三栏结构：左侧信息源与频道，中间列表，右侧阅读器。
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            StoryListView()
        } detail: {
            StoryDetailView()
        }
        // 先载入源与上次选中的频道；频道确定后由下面这个 task 负责加载内容。
        .task { await state.prepare() }
        .task(id: state.selectedChannelID) {
            guard let channelID = state.selectedChannelID else { return }
            await state.loadChannel(channelID)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .frame(width: 1240, height: 780)
}
