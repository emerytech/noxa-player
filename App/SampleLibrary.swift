import Foundation

/// Offline catalog for people who want to explore the player before connecting a server.
struct SampleLibrary {
    static let account = Account(libraries: [
        Library(id: "movies", title: "Movies", type: "movie"),
        Library(id: "series", title: "TV Shows", type: "show")
    ])

    static func response<T: Decodable>(path: String, body: [String: Any]?) throws -> T {
        let movie = ["id":"film","type":"movie","title":"Horizon","duration":18000,"summary":"An original study in moving color."] as [String: Any]
        let show = ["id":"studies","type":"show","title":"Color Studies"]
        let season = ["id":"season","type":"season","title":"Season 1"]
        let episode = ["id":"light","type":"episode","title":"First Light","duration":18000,"season":1,"episode":1] as [String: Any]
        let route = String(path.split(separator: "?").first ?? "")
        let favorites = UserDefaults.standard.stringArray(forKey: "sample.favorites") ?? []
        let catalog: [[String: Any]] = [movie, show]
        let query = URLComponents(string: path)?.queryItems ?? []
        let response: Any
        switch route {
        case "/api/home":
            let progress = UserDefaults.standard.integer(forKey: "sample.progress.film")
            response = ["hero": movie, "continue": progress > 0 ? [movie] : [],
                        "rows": [["library": ["id":"movies","title":"Movies","type":"movie"], "items":[movie]],
                                 ["library": ["id":"series","title":"TV Shows","type":"show"], "items":[show]]]] as [String: Any]
        case "/api/search":
            let term = query.first { $0.name == "q" }?.value ?? ""
            func matches(_ item: [String: Any]) -> Bool {
                (item["title"] as? String)?.localizedCaseInsensitiveContains(term) == true
            }
            response = ["movies": [movie].filter(matches), "shows": [show].filter(matches),
                        "episodes": [episode].filter(matches)] as [String: Any]
        case "/api/watchlist":
            response = catalog.filter { favorites.contains($0["id"] as? String ?? "") }
        case "/api/items/film/watchlist", "/api/items/studies/watchlist":
            let id = route.contains("/film/") ? "film" : "studies"
            var updated = favorites.filter { $0 != id }
            if body?["on"] as? Bool == true { updated.append(id) }
            UserDefaults.standard.set(updated, forKey: "sample.favorites")
            response = ["ok":true]
        case "/api/libraries/movies/genres", "/api/libraries/series/genres":
            response = [["id":"Experimental","title":"Experimental"]]
        case "/api/libraries/movies/items", "/api/libraries/series/items":
            let genre = query.first { $0.name == "genre" }?.value
            let items = genre == nil || genre == "Experimental" ? [route.contains("/movies/") ? movie : show] : []
            response = ["items":items,"total":items.count] as [String: Any]
        case "/api/items/studies/children": response = [season]
        case "/api/items/season/children": response = [episode]
        case "/api/items/studies":
            response = (show as [String: Any]).merging(["in_watchlist":favorites.contains("studies")]) { _, new in new }
        case "/api/items/film", "/api/items/light":
            var item = route.hasSuffix("film") ? movie : episode
            item["in_watchlist"] = favorites.contains("film")
            item["position"] = UserDefaults.standard.integer(forKey: "sample.progress." + (item["id"] as? String ?? ""))
            response = item
        case "/api/play":
            let id = body?["id"] as? String ?? ""
            response = ["stream":id,"url": id == "film" ? "Horizon" : "FirstLight","duration":18000,"offset":body?["offset"] as? Int ?? 0] as [String: Any]
        case "/api/progress":
            if let id = body?["id"] as? String, let position = body?["position"] as? Int {
                UserDefaults.standard.set(position >= 17500 ? 0 : position, forKey: "sample.progress." + id)
            }
            response = [String:String]()
        case "/api/stop", "/api/logout": response = [String:String]()
        default: throw ServerError("This sample is unavailable.")
        }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: response))
    }
}
