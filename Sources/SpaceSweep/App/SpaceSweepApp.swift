import AppKit
import SpaceSweepCore
import SwiftUI

@main
struct SpaceSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("SpaceSweep", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 790)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.route = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Scan") {
            Button("Scan Mac") { model.startScan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning || model.isCleaning)
            Button("Cancel Scan") { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isScanning)
            Divider()
            Button("Review & Clean Selected…") { model.beginCleanup() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.report == nil || model.selection.isEmpty || model.isCleaning)
            Button("Restore Safe Selection") { model.resetSelectionToSafeDefaults() }
                .disabled(model.report == nil)
        }
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) { model.route = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }
        }
    }
}
