import Foundation
import FoundationXML

enum SearchService {
    static func providers(for kind: MediaKind) -> [String] {
        kind == .anime ? ["AniLiberty", "Nyaa", "Tokyo Toshokan"] : ["MangaDex", "Tokyo Toshokan"]
    }

    static func search(_ query: String, kind: MediaKind, provider: String) async -> SearchBatch {
        do {
            let hits: [SearchHit]
            switch provider {
            case "AniLiberty": hits = try await aniLiberty(query)
            case "Nyaa": hits = try await rss(
                "https://nyaa.si/",
                parameters: ["page": "rss", "q": query, "c": "1_0"],
                provider: provider, kind: kind
            )
            case "Tokyo Toshokan": hits = try await rss(
                "https://www.tokyotosho.info/rss.php",
                parameters: ["terms": query], provider: provider, kind: kind
            )
            case "MangaDex": hits = try await mangaDex(query)
            default: throw SearchError.invalidSource
            }
            return SearchBatch(provider: provider, hits: hits, warning: nil)
        } catch {
            return SearchBatch(provider: provider, hits: [], warning: "\(provider): \(error.localizedDescription)")
        }
    }

    private static func url(_ base: String, _ parameters: [String: String]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw SearchError.invalidURL }
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw SearchError.invalidURL }
        return url
    }

    private static func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MochiDrop/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SearchError.server
        }
        return data
    }

    private static func rss(
        _ base: String, parameters: [String: String], provider: String, kind: MediaKind
    ) async throws -> [SearchHit] {
        let xml = try await data(url(base, parameters))
        let parser = RSSCollector()
        let reader = XMLParser(data: xml)
        reader.delegate = parser
        guard reader.parse() else { throw reader.parserError ?? SearchError.server }
        return parser.items.compactMap { item in
            let category = item.category.lowercased()
            if kind == .anime && !category.isEmpty
                && !["anime", "batch", "raws", "non-english"].contains(category) { return nil }
            if kind == .manga && !category.isEmpty && category != "manga" { return nil }
            let link = item.enclosure.isEmpty ? item.link : item.enclosure
            guard !item.title.isEmpty,
                  link.hasPrefix("https://") || link.hasPrefix("http://") || link.hasPrefix("magnet:?")
            else { return nil }
            return SearchHit(
                id: "\(provider):\(item.guid.isEmpty ? link : item.guid)",
                title: item.title, provider: provider, kind: kind,
                method: .torrent, url: link,
                details: item.description.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                size: item.length, seeders: item.seeders
            )
        }.prefix(25).map { $0 }
    }

    private static func aniLiberty(_ query: String) async throws -> [SearchHit] {
        let releases = try await data(url("https://anilibria.top/api/v1/app/search/releases", ["query": query]))
        guard let rows = try JSONSerialization.jsonObject(with: releases) as? [[String: Any]] else {
            throw SearchError.server
        }
        var hits: [SearchHit] = []
        for release in rows.prefix(5) {
            guard let id = release["id"] as? Int else { continue }
            let source = URL(string: "https://anilibria.top/api/v1/anime/torrents/release/\(id)")!
            guard let torrentData = try? await data(source),
                  let torrents = try? JSONSerialization.jsonObject(with: torrentData) as? [[String: Any]]
            else { continue }
            for torrent in torrents.prefix(6) {
                guard let magnet = torrent["magnet"] as? String, magnet.hasPrefix("magnet:?") else { continue }
                let release = torrent["release"] as? [String: Any]
                let names = release?["name"] as? [String: Any]
                let releaseName = names?["main"] as? String
                let qualityValue = (torrent["quality"] as? [String: Any])?["value"] as? String
                let quality = qualityValue ?? ""
                let rawTorrentID = torrent["id"] as? Int
                let torrentID = rawTorrentID ?? 0
                let label = torrent["label"] as? String
                let rawDescription = torrent["description"] as? String
                let description = rawDescription ?? ""
                hits.append(SearchHit(
                    id: "AniLiberty:\(torrentID)",
                    title: label ?? releaseName ?? "Аниме",
                    provider: "AniLiberty", kind: .anime, method: .torrent, url: magnet,
                    details: "\(quality) \(description)",
                    size: (torrent["size"] as? NSNumber)?.int64Value,
                    seeders: torrent["seeders"] as? Int
                ))
            }
        }
        return hits
    }

    private static func mangaDex(_ query: String) async throws -> [SearchHit] {
        let response = try await data(url("https://api.mangadex.org/manga", ["title": query, "limit": "5"]))
        let value = try JSONSerialization.jsonObject(with: response)
        guard let root = value as? [String: Any] else { throw SearchError.server }
        let manga = root["data"] as? [[String: Any]] ?? []
        var hits: [SearchHit] = []
        for entry in manga.prefix(5) {
            guard let id = entry["id"] as? String,
                  let attributes = entry["attributes"] as? [String: Any],
                  let titles = attributes["title"] as? [String: String]
            else { continue }
            let title = titles["en"] ?? titles["ja-ro"] ?? titles.values.first ?? "Манга"
            let feedURL = try url("https://api.mangadex.org/manga/\(id)/feed",
                                  ["limit": "5", "order[publishAt]": "desc"])
            guard let feedData = try? await data(feedURL),
                  let feed = try? JSONSerialization.jsonObject(with: feedData) as? [String: Any],
                  let chapters = feed["data"] as? [[String: Any]] else { continue }
            for chapter in chapters {
                guard let chapterID = chapter["id"] as? String,
                      let meta = chapter["attributes"] as? [String: Any],
                      meta["externalUrl"] == nil || meta["externalUrl"] is NSNull
                else { continue }
                let chapterNumber = meta["chapter"] as? String
                let number = chapterNumber ?? "?"
                let translatedLanguage = meta["translatedLanguage"] as? String
                let language = translatedLanguage ?? ""
                let rawChapterTitle = meta["title"] as? String
                let chapterTitle = rawChapterTitle ?? ""
                hits.append(SearchHit(
                    id: "MangaDex:\(chapterID)", title: "\(title) · Глава \(number)",
                    provider: "MangaDex", kind: .manga, method: .page,
                    url: "https://mangadex.org/chapter/\(chapterID)",
                    details: "\(language.uppercased()) \(chapterTitle)",
                    size: nil, seeders: nil
                ))
            }
        }
        return hits
    }
}

private enum SearchError: LocalizedError {
    case invalidURL, invalidSource, server
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Неверный адрес источника"
        case .invalidSource: "Неизвестный источник"
        case .server: "Источник вернул неожиданный ответ"
        }
    }
}

private struct RSSItem {
    var title = ""
    var category = ""
    var link = ""
    var guid = ""
    var description = ""
    var enclosure = ""
    var length: Int64?
    var seeders: Int?
}

private final class RSSCollector: NSObject, XMLParserDelegate {
    var items: [RSSItem] = []
    private var current: RSSItem?
    private var element = ""
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "item" { current = RSSItem() }
        element = name
        text = ""
        if name == "enclosure" {
            current?.enclosure = attributeDict["url"] ?? ""
            current?.length = attributeDict["length"].flatMap(Int64.init)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": current?.title = value
        case "category": current?.category = value
        case "link": current?.link = value
        case "guid": current?.guid = value
        case "description": current?.description = value
        case "seeders": current?.seeders = Int(value)
        case "item":
            if let current { items.append(current) }
            current = nil
        default: break
        }
        element = ""
        text = ""
    }
}
