import AppKit
import SwiftUI

@main
struct MochiDropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 650)
                .onAppear { GUISmokeProbe.reportVisibleWindow() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая загрузка") { model.showingNewDownload = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("MochiDrop") {
                Button("Поиск") { model.page = .search }
                    .keyboardShortcut("f")
                Button("Настройки") { model.page = .settings }
                    .keyboardShortcut(",")
            }
        }
    }
}

@MainActor
private enum GUISmokeProbe {
    static func reportVisibleWindow() {
        guard let path = ProcessInfo.processInfo.environment["MOCHIDROP_GUI_SMOKE_MARKER"] else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task {
            for _ in 0..<40 {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.contentView != nil && $0.frame.width >= 900
                }) {
                    let report = "visible window: \(Int(window.frame.width))x\(Int(window.frame.height)); pid: \(ProcessInfo.processInfo.processIdentifier)\n"
                    try? report.write(toFile: path, atomically: true, encoding: .utf8)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
