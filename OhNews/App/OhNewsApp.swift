import SwiftUI

@main
struct OhNewsApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
