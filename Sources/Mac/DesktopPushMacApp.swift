import SwiftUI
import UserNotifications

@main
struct DesktopPushMacApp: App {
    @StateObject private var model = SenderModel()

    var body: some Scene {
        WindowGroup {
            MacRootView(model: model)
                .task { await model.start() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Send Current Push") { Task { await model.sendNow() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canSend)
            }
        }
    }
}
