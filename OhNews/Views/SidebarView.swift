import OhNewsKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        List(selection: $state.selectedList) {
            Section("榜单") {
                ForEach(StoryList.allCases) { list in
                    Label(list.displayName, systemImage: list.systemImage)
                        .tag(list)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 240)
    }
}
