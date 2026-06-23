import SwiftUI

@main
struct SwiftUninstallApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultPosition(.center)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新载入应用") { Task { await state.reloadApplications() } }
                    .keyboardShortcut("r")
            }
        }
    }
}
