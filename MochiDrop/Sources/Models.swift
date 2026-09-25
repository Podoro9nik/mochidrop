import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case anime, manga
    var id: String { rawValue }
    var title: String { self == .anime ? "Аниме" : "Манга" }
    var symbol: String { self == .anime ? "play.rectangle.fill" : "books.vertical.fill" }
}

enum DownloadMethod: String, Codable {
    case torrent, page, direct
}

enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed
    var title: String {
        switch self {
        case .queued: "В очереди"
        case .downloading: "Загружается"
        case .paused: "Пауза"
        case .completed: "Готово"
        case .failed: "Ошибка"
        }
    }
}

struct SearchHit: Identifiable {
    let id: String
    let title: String
    let provider: String
    let kind: MediaKind
    let method: DownloadMethod
    let url: String
    let details: String
    let size: Int64?
    let seeders: Int?
}

struct DownloadItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var kind: MediaKind
    var method: DownloadMethod
    var urls: [String]
    var folder: String
    var status: DownloadStatus
    var downloaded: Int64
    var total: Int64?
    var error: String?
    var createdAt: Date

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(downloaded) / Double(total))
    }
}

struct SearchBatch {
    let provider: String
    let hits: [SearchHit]
    let warning: String?
}
