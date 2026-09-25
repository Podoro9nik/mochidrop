import AppKit
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.982, green: 0.968, blue: 0.988)
    static let sidebar = Color(red: 0.951, green: 0.918, blue: 0.975)
    static let ink = Color(red: 0.25, green: 0.19, blue: 0.31)
    static let muted = Color(red: 0.54, green: 0.49, blue: 0.57)
    static let pink = Color(red: 0.93, green: 0.42, blue: 0.64)
    static let lilac = Color(red: 0.54, green: 0.37, blue: 0.75)
    static let border = Color(red: 0.91, green: 0.87, blue: 0.93)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 226)
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                Group {
                    switch model.page {
                    case .search: SearchScreen()
                    case .downloads: DownloadsScreen()
                    case .settings: SettingsScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background)
        }
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: $model.showingNewDownload) {
            NewDownloadSheet()
                .environmentObject(model)
        }
        .alert("MochiDrop", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )) {
            Button("ОК") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.shutdown()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.pink)
                    .frame(width: 37, height: 37)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MochiDrop")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("твоя уютная коллекция")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.top, 29)
            .padding(.horizontal, 19)

            VStack(spacing: 6) {
                ForEach(AppModel.Page.allCases) { page in
                    Button {
                        model.page = page
                    } label: {
                        Label(page.title, systemImage: page.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .foregroundStyle(model.page == page ? Palette.lilac : Palette.muted)
                            .background(
                                model.page == page ? .white.opacity(0.9) : .clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.page == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 13)

            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.pink)
                Text("Истории всегда рядом")
                    .font(.system(size: 12, weight: .semibold))
                Text("Аниме и манга в одном милом месте.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
            .padding(14)
        }
        .background(Palette.sidebar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.page.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(model.page == .search ? "Найди любимую историю" :
                        model.page == .downloads ? "Всё, что ты сохранил" : "Сделай приложение своим")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                model.showingNewDownload = true
            } label: {
                Label("Новая загрузка", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 17)
                    .frame(height: 36)
                    .foregroundStyle(.white)
                    .background(Palette.pink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 21)
        .background(.white.opacity(0.65))
    }
}

private struct SearchScreen: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Что будем смотреть или читать? ✦")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("Один поиск покажет доступные раздачи и главы.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 31))
                            .foregroundStyle(Palette.pink.opacity(0.78))
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Palette.lilac)
                        TextField("Название аниме или манги", text: $model.query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .onSubmit { model.search() }
                        if !model.query.isEmpty {
                            Button {
                                model.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Palette.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Очистить поиск")
                        }
                    }
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 13))

                    HStack {
                        Picker("Тип", selection: $model.kind) {
                            ForEach(MediaKind.allCases) { kind in
                                Label(kind.title, systemImage: kind.symbol).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        Spacer()
                        Text(SearchService.providers(for: model.kind).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .mochiCard()

                HStack {
                    Text("Результаты")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if !model.results.isEmpty {
                        Text("\(model.results.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.lilac)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Palette.sidebar, in: Capsule())
                    }
                    Spacer()
                    if model.searching { ProgressView().controlSize(.small) }
                }

                if model.results.isEmpty && !model.searching {
                    VStack(spacing: 11) {
                        Image(systemName: model.query.isEmpty ? "sparkle.magnifyingglass" : "tray")
                            .font(.system(size: 34))
                            .foregroundStyle(Palette.pink)
                        Text(model.query.isEmpty ? "Введи название — и начнём поиск" : "Пока ничего не найдено")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Источники могут временно быть недоступны или требовать другое написание.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 55)
                    .mochiCard()
                }
                ForEach(model.results) { hit in
                    SearchRow(hit: hit)
                }
                ForEach(model.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.query) { _, _ in scheduleSearch() }
        .onChange(of: model.kind) { _, _ in model.search() }
        .onDisappear { debounce?.cancel() }
    }

    private func scheduleSearch() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            model.search()
        }
    }
}

private struct SearchRow: View {
    @EnvironmentObject private var model: AppModel
    let hit: SearchHit

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: hit.kind.symbol)
                .font(.system(size: 19))
                .foregroundStyle(Palette.lilac)
                .frame(width: 47, height: 47)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(hit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(hit.provider)
                        .foregroundStyle(Palette.lilac)
                    if let seeders = hit.seeders { Text("↑ \(seeders)") }
                    if let size = hit.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if !hit.details.isEmpty { Text(hit.details).lineLimit(1) }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button {
                model.add(hit)
            } label: {
                Label("Скачать", systemImage: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 33)
                    .background(Palette.lilac, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .mochiCard(padding: 14)
    }
}

private struct DownloadsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("\(model.items.count) в коллекции")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Text("Одновременно до двух загрузок")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                if model.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.heart.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Palette.pink)
                        Text("Тут появятся твои истории")
                            .font(.system(size: 15, weight: .semibold))
                        Button("Перейти к поиску") { model.page = .search }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                    .mochiCard()
                }
                ForEach(model.items) { item in
                    DownloadRow(item: item)
                }
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var model: AppModel
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(Palette.pink)
                .font(.system(size: 19))
                .frame(width: 46, height: 46)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack {
                    Text(item.status.title)
                    if item.method == .torrent { Text("· Торрент") }
                    if let fraction = item.fraction, item.status == .downloading {
                        Text("· \(Int(fraction * 100))%")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                if item.status == .downloading {
                    ProgressView(value: item.fraction ?? 0)
                        .tint(Palette.pink)
                }
                if let error = item.error, item.status == .failed {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if item.status == .downloading || item.status == .queued {
                Button {
                    model.pause(item.id)
                } label: { Image(systemName: "pause.fill") }
                    .help("Пауза")
            } else if item.status != .completed {
                Button {
                    model.start(item.id)
                } label: { Image(systemName: "play.fill") }
                    .help("Продолжить")
            }
            Button {
                model.openFolder(item)
            } label: { Image(systemName: "folder") }
                .help("Открыть папку")
            Button {
                model.remove(item.id)
            } label: { Image(systemName: "trash") }
                .help("Убрать из списка")
        }
        .buttonStyle(.plain)
        .mochiCard(padding: 15)
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Папка загрузок", systemImage: "folder.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(model.folder.path)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                    Button("Выбрать папку") { model.chooseFolder() }
                }
                .mochiCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Источники", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Поиск: AniLiberty, Nyaa, Tokyo Toshokan и MangaDex. Для страниц используются встроенные yt-dlp и gallery-dl, для торрентов — встроенный движок.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text("Некоторые источники могут требовать учётную запись. Приложение не обходит DRM.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .mochiCard()
                VStack(alignment: .leading, spacing: 9) {
                    Label("Быстрые клавиши", systemImage: "keyboard")
                        .font(.system(size: 16, weight: .bold))
                    Text("⌘F — поиск · ⌘N — новая загрузка · ⌘, — настройки")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                .mochiCard()
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct NewDownloadSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: MediaKind = .anime
    @State private var method: DownloadMethod = .page
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Новая загрузка ✦")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
            }
            Picker("Что загружаем?", selection: $kind) {
                ForEach(MediaKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
            Picker("Способ", selection: $method) {
                Text("Страница сайта").tag(DownloadMethod.page)
                Text("Торрент").tag(DownloadMethod.torrent)
                Text("Прямая ссылка").tag(DownloadMethod.direct)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("Название").font(.system(size: 12, weight: .semibold))
                TextField("Название", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading) {
                Text(method == .torrent ? "Magnet, URL .torrent или локальный .torrent"
                     : method == .direct && kind == .manga ? "Адреса изображений, по одному в строке"
                     : "Адрес страницы или файла")
                    .font(.system(size: 12, weight: .semibold))
                if method == .direct && kind == .manga {
                    TextEditor(text: $address)
                        .frame(height: 92)
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
                } else {
                    TextField("https://…", text: $address)
                        .textFieldStyle(.roundedBorder)
                }
                if method == .torrent {
                    Button("Выбрать файл .torrent") {
                        if let selected = model.chooseTorrent() { address = selected }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Начать загрузку") {
                    let urls = method == .direct && kind == .manga
                        ? address.components(separatedBy: .newlines) : [address]
                    model.add(title: title, kind: kind, method: method, urls: urls)
                    if model.alert == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.pink)
            }
        }
        .padding(26)
        .frame(width: 550)
        .background(Palette.background)
    }
}

private struct MochiCard: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(Palette.border.opacity(0.55)))
    }
}

private extension View {
    func mochiCard(padding: CGFloat = 21) -> some View {
        modifier(MochiCard(padding: padding))
    }
}
