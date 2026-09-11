import HeyNewsKit
import SwiftUI

/// 三栏结构：左侧榜单，中间列表，右侧阅读器。
///
/// 阅读器在 M4 接入；M3 会在列表行里补上 AI 摘要。
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
        .task(id: state.selectedList) {
            guard let list = state.selectedList else { return }
            await state.loadList(list)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .frame(width: 1240, height: 780)
}
