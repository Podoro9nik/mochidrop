import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case search, downloads, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .search: "Поиск"
            case .downloads: "Загрузки"
            case .settings: "Настройки"
            }
        }
        var symbol: String {
            switch self {
            case .search: "magnifyingglass"
            case .downloads: "arrow.down.to.line.compact"
            case .settings: "gearshape"
            }
        }
    }

    @Published var page: Page = .search
    @Published var kind: MediaKind = .anime
    @Published var query = ""
    @Published private(set) var results: [SearchHit] = []
    @Published private(set) var warnings: [String] = []
    @Published private(set) var searching = false
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var folder: URL
    @Published var showingNewDownload = false
    @Published var alert: String?

    private var searchJob: Task<Void, Never>?
    private var searchSequence = 0
    private var processes: [UUID: Process] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var lastOutput: [UUID: String] = [:]
    private var generations: [UUID: Int] = [:]

    init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        folder = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "downloadFolder")
            ?? downloads.appendingPathComponent("MochiDrop").path, isDirectory: true)
        if let data = try? Data(contentsOf: Self.storageURL()),
           let saved = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = saved.map {
                var item = $0
                if item.status == .downloading || item.status == .queued { item.status = .paused }
                return item
            }
        }
    }

    func search() {
        searchJob?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchSequence += 1
        let sequence = searchSequence
        results = []
        warnings = []
        guard text.count >= 2 else { searching = false; return }
        searching = true
        let selectedKind = kind
        searchJob = Task {
            await withTaskGroup(of: SearchBatch.self) { group in
                for provider in SearchService.providers(for: selectedKind) {
                    group.addTask {
                        await SearchService.search(text, kind: selectedKind, provider: provider)
                    }
                }
                for await batch in group {
                    guard !Task.isCancelled, sequence == searchSequence else { continue }
                    results += batch.hits
                    results.sort { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
                    if let warning = batch.warning { warnings.append(warning) }
                }
            }
            if sequence == searchSequence { searching = false }
        }
    }

    func add(_ hit: SearchHit) {
        add(title: hit.title, kind: hit.kind, method: hit.method, urls: [hit.url])
    }

    func add(title: String, kind: MediaKind, method: DownloadMethod, urls: [String]) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURLs = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanTitle.isEmpty, !cleanURLs.isEmpty else {
            alert = "Введите название и адрес загрузки."
            return
        }
        guard cleanURLs.allSatisfy({ address in
            address.hasPrefix("https://") || address.hasPrefix("http://")
                || (method == .torrent && (address.hasPrefix("magnet:?") || FileManager.default.fileExists(atPath: address)))
        }) else {
            alert = "Укажите HTTP(S), magnet или локальный файл .torrent."
            return
        }
        let item = DownloadItem(id: UUID(), title: cleanTitle, kind: kind, method: method,
                                urls: cleanURLs, folder: folder.path, status: .queued,
                                downloaded: 0, total: nil, error: nil, createdAt: .now)
        items.insert(item, at: 0)
        persist()
        startQueued()
        page = .downloads
    }

    func start(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status != .downloading else { return }
        items[index].status = .queued
        items[index].error = nil
        persist()
        startQueued()
    }

    func pause(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .downloading || items[index].status == .queued else { return }
        items[index].status = .paused
        generations[id, default: 0] += 1
        if let process = processes.removeValue(forKey: id), process.isRunning { process.terminate() }
        jobs.removeValue(forKey: id)?.cancel()
        persist()
        startQueued()
    }

    func remove(_ id: UUID) {
        pause(id)
        items.removeAll { $0.id == id }
        persist()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            UserDefaults.standard.set(url.path, forKey: "downloadFolder")
        }
    }

    func chooseTorrent() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent")!]
        panel.canChooseDirectories = false
        panel.prompt = "Выбрать"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    func openFolder(_ item: DownloadItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.folder, isDirectory: true))
    }

    func shutdown() {
        for process in processes.values where process.isRunning { process.terminate() }
        for job in jobs.values { job.cancel() }
        processes.removeAll()
        jobs.removeAll()
        for index in items.indices where items[index].status == .downloading || items[index].status == .queued {
            items[index].status = .paused
        }
        persist()
    }

    private func startQueued() {
        var active = items.filter { $0.status == .downloading }.count
        for index in items.indices.reversed() where active < 2 {
            guard items[index].status == .queued else { continue }
            let id = items[index].id
            generations[id, default: 0] += 1
            let generation = generations[id]!
            items[index].status = .downloading
            active += 1
            if items[index].kind == .manga && items[index].method == .direct {
                jobs[id] = Task { await downloadImages(id, generation: generation) }
            } else {
                startProcess(id, generation: generation)
            }
        }
        persist()
    }

    private func startProcess(_ id: UUID, generation: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let destination = URL(fileURLWithPath: item.folder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let process = Process()
            let tools = Bundle.main.resourceURL!.appendingPathComponent("tools", isDirectory: true)
            switch item.method {
            case .torrent:
                process.executableURL = tools.appendingPathComponent("mochidrop-torrent")
                let subfolder = destination.appendingPathComponent(safeName(item.title), isDirectory: true)
                process.arguments = [item.urls[0], subfolder.path]
            case .page:
                if item.kind == .anime {
                    process.executableURL = tools.appendingPathComponent("yt-dlp")
                    process.arguments = ["--no-config", "--no-playlist", "--newline", "--no-warnings",
                                         "--continue", "--progress-template",
                                         "download:PROGRESS:%(progress._percent_str)s",
                                         "-f", "best[ext=mp4]/best",
                                         "-o", destination.appendingPathComponent("\(safeName(item.title)).%(ext)s").path,
                                         item.urls[0]]
                } else {
                    process.executableURL = tools.appendingPathComponent("gallery-dl")
                    process.arguments = ["--config-ignore", "--no-input", "--no-colors",
                                         "--cbz", "-D", destination.path, item.urls[0]]
                }
            case .direct:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                let name = URL(string: item.urls[0])?.lastPathComponent ?? "video.mp4"
                let filename = safeName(name.isEmpty ? "video.mp4" : name)
                process.arguments = ["--location", "--fail", "--continue-at", "-",
                                     "--output", destination.appendingPathComponent(filename).path,
                                     "--", item.urls[0]]
            }
            process.currentDirectoryURL = destination
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                guard !bytes.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let text = String(decoding: bytes, as: UTF8.self)
                Task { @MainActor [weak self] in self?.readOutput(text, id: id, generation: generation) }
            }
            process.terminationHandler = { [weak self] finished in
                output.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [weak self] in
                    self?.finish(id, generation: generation, exitCode: finished.terminationStatus)
                }
            }
            processes[id] = process
            try process.run()
        } catch {
            processes[id] = nil
            fail(id, generation: generation, error.localizedDescription)
        }
    }

    private func readOutput(_ text: String, id: UUID, generation: Int) {
        guard generations[id] == generation else { return }
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .downloading else { return }
        lastOutput[id] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in text.components(separatedBy: .newlines) {
            if let range = line.range(of: "PROGRESS ") {
                let values = line[range.upperBound...].split(separator: " ")
                if values.count >= 2, let current = Int64(values[0]), let total = Int64(values[1]) {
                    items[index].downloaded = current
                    items[index].total = total
                }
            } else if let range = line.range(of: "PROGRESS:") {
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "%", with: "")
                if let percent = Double(value) {
                    items[index].downloaded = Int64(max(0, min(100, percent)))
                    items[index].total = 100
                }
            }
        }
    }

    private func finish(_ id: UUID, generation: Int, exitCode: Int32) {
        guard generations[id] == generation else { return }
        processes[id] = nil
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .downloading else {
            startQueued()
            return
        }
        if exitCode == 0 {
            items[index].status = .completed
            if items[index].total == nil { items[index].total = 1; items[index].downloaded = 1 }
        } else {
            items[index].status = .failed
            items[index].error = lastOutput[id].flatMap { $0.isEmpty ? nil : $0 } ?? "Загрузчик завершился с кодом \(exitCode)."
        }
        lastOutput[id] = nil
        persist()
        startQueued()
    }

    private func fail(_ id: UUID, generation: Int, _ message: String) {
        guard generations[id] == generation else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].status == .paused { return }
        items[index].status = .failed
        items[index].error = message
        jobs[id] = nil
        persist()
        startQueued()
    }

    private func downloadImages(_ id: UUID, generation: Int) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let directory = URL(fileURLWithPath: item.folder, isDirectory: true)
            .appendingPathComponent(safeName(item.title), isDirectory: true)
        let pages = directory.appendingPathComponent("pages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
            let urls = item.urls
            for (index, address) in urls.enumerated() {
                guard generations[id] == generation else { return }
                try Task.checkCancellation()
                guard let url = URL(string: address), url.scheme == "https" else {
                    throw DownloadError.invalidURL
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let status = response as? HTTPURLResponse, (200...299).contains(status.statusCode)
                else { throw DownloadError.server }
                let ext = ["jpg", "jpeg", "png", "webp", "gif"].contains(url.pathExtension.lowercased())
                    ? url.pathExtension.lowercased() : "jpg"
                let output = pages.appendingPathComponent(String(format: "%04d.%@", index + 1, ext))
                try data.write(to: output, options: .atomic)
                if generations[id] == generation,
                   let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].downloaded = Int64(index + 1)
                    items[current].total = Int64(urls.count)
                }
            }
            guard generations[id] == generation else { return }
            try Task.checkCancellation()
            let archive = directory.appendingPathComponent("\(safeName(item.title)).cbz")
            let files = try FileManager.default.contentsOfDirectory(at: pages, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-q", "-j", archive.path] + files.map(\.path)
            processes[id] = zip
            let code: Int32 = try await withCheckedThrowingContinuation { continuation in
                zip.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try zip.run() } catch { continuation.resume(throwing: error) }
            }
            guard generations[id] == generation else { return }
            processes[id] = nil
            try Task.checkCancellation()
            guard code == 0 else { throw DownloadError.archive }
            try? FileManager.default.removeItem(at: pages)
            if let current = items.firstIndex(where: { $0.id == id }), items[current].status == .downloading {
                items[current].status = .completed
            }
            jobs[id] = nil
            persist()
            startQueued()
        } catch is CancellationError {
            if generations[id] == generation { jobs[id] = nil }
        } catch {
            fail(id, generation: generation, error.localizedDescription)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let location = Self.storageURL()
        try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: location, options: .atomic)
    }

    private static func storageURL() -> URL {
        let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return parent.appendingPathComponent("MochiDrop/downloads.json")
    }

    private func safeName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        let name = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(name.prefix(100)).isEmpty ? "Загрузка" : String(name.prefix(100))
    }
}

private enum DownloadError: LocalizedError {
    case invalidURL, server, archive
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Для изображений нужна ссылка HTTPS."
        case .server: "Не удалось получить изображение."
        case .archive: "Не удалось создать CBZ."
        }
    }
}
