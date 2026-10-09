import SwiftUI

@main
struct BotPlusPDFEditorLegacyApp: App {
    var body: some Scene {
        WindowGroup("BotPlus PDF Editor") {
            WorkspaceView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .saveItem) {
                Button("Open PDF…") { NotificationCenter.default.post(name: .botPlusOpenDocument, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let botPlusOpenDocument = Notification.Name("BotPlusPDFEditor.openDocument")
}
