import Foundation
import AVFoundation

struct Library: Decodable, Identifiable {
    let id: String
    let title: String
    let type: String
}
struct Account: Decodable { let libraries: [Library] }
struct Login: Decodable { let ticket: String? }
struct Page: Decodable { let total: Int; let items: [Title] }
struct Title: Decodable, Identifiable {
    let id: String
    let title: String
    let type: String
    let summary: String?
    let year: Int?
    let thumb: String?
    let episode: Int?
    let season: Int?
    let duration: Int?
    let genres: [String]?
    let show_id: String?
    let position: Int?
    let in_watchlist: Bool?
    let show: String?
    let art: String?
    let watched: Bool?
    var label: String {
        if let episode { return "E\(episode)  ·  \(title)" }
        return title
    }
}
struct Stream: Decodable {
    let stream: String
    let url: String
    let duration: Int
    let offset: Int
}
struct ServerError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
struct Empty: Decodable {}
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct Server {
    static let sample = Server(sampleURL: URL(fileURLWithPath: "/"))
    private init(sampleURL: URL) { base = sampleURL }
    var isSample: Bool { base.isFileURL }
    let base: URL
    static let session = URLSession(configuration: .default, delegate: NoRedirects(), delegateQueue: nil)
    init(_ address: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http","https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ServerError("Enter your server address, including http:// or https://.")
        }
        base = url
    }
    static func path(_ route: String, _ query: [URLQueryItem]) -> String {
        var parts = URLComponents()
        parts.queryItems = query
        return route + "?" + (parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
    }
    func endpoint(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path),
              url.host == base.host, url.scheme == base.scheme, url.port == base.port else {
            throw ServerError("The server returned an invalid address.")
        }
        return url
    }
    func request<T: Decodable>(_ path: String, _ body: [String: Any]? = nil) async throws -> T {
        if isSample { return try SampleLibrary.response(path: path, body: body) }
        var req = URLRequest(url: try endpoint(path))
        req.setValue("1", forHTTPHeaderField: "X-Seance")
        req.setValue("en", forHTTPHeaderField: "X-Lang")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await Self.session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let details = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ServerError(details?["error"] as? String ?? "The server could not complete this request.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func asset(_ path: String) throws -> AVURLAsset {
        if isSample {
            guard let clip = Bundle.main.url(forResource: path, withExtension: "mp4") else { throw ServerError("Sample film unavailable.") }; return AVURLAsset(url: clip)
        }
        let url = try endpoint(path)
        return AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: HTTPCookieStorage.shared.cookies(for: url) ?? []])
    }
}

struct HomeFeed: Decodable {
    struct Row: Decodable {
        let library: Library
        let items: [Title]
    }
    let hero: Title?
    let hero_mode: String?
    let `continue`: [Title]
    let suggestions: [Title]?
    let rows: [Row]
}

struct SearchResults: Decodable {
    let movies: [Title]
    let shows: [Title]
    let episodes: [Title]
}


/// Preserve the server's ordering for equally strong genre matches.
func viewerPicks(feed: HomeFeed, favorites: [Title]) -> [Title] {
    let saved = Set(favorites.map(\.id))
    let genres = Set(favorites.flatMap { $0.genres ?? [] }.map { $0.lowercased() })
    var seen = Set<String>()
    let candidates = ((feed.suggestions ?? []) + feed.rows.flatMap(\.items)).filter {
        !saved.contains($0.id) && seen.insert($0.id).inserted && $0.watched != true
    }
    func score(_ title: Title) -> Int {
        Set((title.genres ?? []).map { $0.lowercased() }).intersection(genres).count
    }
    return candidates.enumerated().sorted {
        let left = score($0.element), right = score($1.element)
        return left == right ? $0.offset < $1.offset : left > right
    }.prefix(24).map(\.element)
}
