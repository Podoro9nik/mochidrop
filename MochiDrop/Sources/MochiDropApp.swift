import SwiftUI

@main
struct MochiDropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 650)
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
