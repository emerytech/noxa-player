import SwiftUI
import AVFAudio

struct Genre: Decodable, Identifiable {
    let id: String
    let title: String
}

@main struct NoxaPhoneApp: App {
    init() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
    var body: some Scene { WindowGroup { PhoneRoot().preferredColorScheme(.dark).tint(.mint) } }
}

private struct PhoneRoot: View {
    @AppStorage("phoneServer") var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var ticket: String?
    @State private var connected: Server?
    @State private var libraries: [Library] = []
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Group {
            if let server = connected {
                TabView {
                    NavigationStack {
                        LibraryHome(server: server, libraries: libraries)
                            .navigationTitle("Library")
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    NavigationLink { ServerSetupGuide() } label: {
                                        Label("Server setup", systemImage: "questionmark.circle")
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                            Button("Disconnect") {
                                Task {
                                    do {
                                        if !server.isSample { let _: Empty = try await server.request("/api/logout", [:]) }
                                        connected = nil; message = ""; ticket = nil
                                    } catch { message = error.localizedDescription }
                                }
                            }
                                } label: { Image(systemName: "person.crop.circle").accessibilityLabel("Account") }
                                }
                            }
                            .safeAreaInset(edge: .bottom) { if !message.isEmpty { Text(message) } }
                    }.tabItem { Label("Library", systemImage: "rectangle.stack") }
                    NavigationStack { PhoneSearch(server: server) }
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    NavigationStack { PhoneFavorites(server: server) }
                        .tabItem { Label("Favorites", systemImage: "heart") }
                    NavigationStack { RetroTV(server: server, libraries: libraries) }
                        .tabItem { Label("Retro TV", systemImage: "tv") }
                }
            } else {
                NavigationStack {
                    Form {
                        Section("Server") {
                            TextField("Server address", text: $address).keyboardType(.URL)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(ticket != nil)
                        }
                        Section("Viewer account") {
                            if ticket == nil {
                                TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                SecureField("Password", text: $password).textContentType(.password)
                            } else {
                                TextField("Verification code", text: $code).textContentType(.oneTimeCode)
                                Button("Back to sign in") { ticket = nil; code = "" }
                            }
                            Button("Sign in") { Task { await login() } }
                                .disabled(busy || (ticket == nil ? username.isEmpty || password.isEmpty : code.isEmpty))
                        }
                        if !message.isEmpty { Text(message) }
                        NavigationLink("Set up your own server") { ServerSetupGuide() }
                        Button("Explore sample library") { libraries = SampleLibrary.account.libraries; connected = .sample }
                    }.navigationTitle("Noxa Player")
                }
            }
        }.task {
            if let server = try? Server(address), let me: Account = try? await server.request("/api/me"), connected == nil {
                libraries = me.libraries; connected = server
            }
        }
    }
    @MainActor private func login() async {
        busy = true; defer { busy = false }
        do {
            let server = try Server(address)
            if let ticket {
                let _: Empty = try await server.request("/api/login/2fa", ["ticket":ticket,"code":code])
            } else {
                let result: Login = try await server.request("/api/login", ["username":username,"password":password])
                if let challenge = result.ticket { ticket = challenge; return }
            }
            let me: Account = try await server.request("/api/me")
            libraries = me.libraries; password = ""; code = ""; message = ""; ticket = nil; connected = server
        } catch { message = error.localizedDescription }
    }
}

private struct ServerSetupGuide: View {
    var body: some View {
        List {
            Section("1. Install Noxa") {
                Text("Choose a computer that can stay on while you watch. Use Docker Compose on a compatible Docker host, a Proxmox container, or the Debian or Ubuntu installer.")
                Link("Open installation instructions", destination: URL(string: "https://github.com/xenix13/Noxa/blob/main/docs/installation.md")!)
            }
            Section("2. Open your server") {
                Text("On your home network, open the server’s address in a browser. For example, if its local IP is 192.168.1.50, open http://192.168.1.50:8420. Enter the setup code from the installer or Docker logs and create your administrator account.")
            }
            Section("3. Add your media") {
                Text("Make your Movies and TV Shows folders readable on the server. For Docker, mount the folders into the container, then select those container paths in Noxa. Add a movie library and a show library, scan them, and play one title in the browser.")
                Link("Library and user setup", destination: URL(string: "https://github.com/xenix13/Noxa/blob/main/docs/getting-started.md")!)
            }
            Section("4. Connect this iPhone") {
                Text("Create a viewer account with access to the libraries you want. Connect your iPhone to the same Wi-Fi, return to sign-in, enter the same server address, and sign in as that viewer. For viewing away from home, use your server’s HTTPS address or your VPN.")
            }
        }.navigationTitle("Set up your server").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhonePosterRow: View {
    let server: Server
    let titles: [Title]
    var body: some View {
ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(titles) { title in
                                        NavigationLink { PhoneDetail(server: server, title: title) } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Poster(server: server, title: title).clipShape(RoundedRectangle(cornerRadius: 10))
                                                Text(title.title).font(.caption.bold()).lineLimit(2)
                                            }.frame(width: 112)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.horizontal)
                            }.scrollIndicators(.hidden)
    }
}

private struct PhoneSearch: View {
    let server: Server
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var error = ""
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Movies, shows, and episodes", text: $query)
                    .submitLabel(.search).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search")
                }
            }
            if term.count < 2 { Text("Enter at least two characters.").foregroundStyle(.secondary) }
            else if !error.isEmpty { Text(error) }
            else if let results {
                section("Movies", results.movies)
                section("TV Shows", results.shows)
                section("Episodes", results.episodes)
                if results.movies.isEmpty && results.shows.isEmpty && results.episodes.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            } else { ProgressView() }
        }.navigationTitle("Search")
         .task(id: term) {
             results = nil; error = ""
             guard term.count >= 2 else { return }
             do {
                 try await Task.sleep(for: .milliseconds(280))
                 let found: SearchResults = try await server.request(Server.path("/api/search", [.init(name: "q", value: term)]))
                 try Task.checkCancellation()
                 results = found
             } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
         }
    }

    @ViewBuilder private func section(_ name: String, _ titles: [Title]) -> some View {
        if !titles.isEmpty {
            Section(name) {
                ForEach(titles) { item in
                    NavigationLink { PhoneDetail(server: server, title: item) } label: {
                        VStack(alignment: .leading) {
                            Text(item.label)
                            if let show = item.show { Text(show).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

private struct PhoneFavorites: View {
    let server: Server
    @State private var titles: [Title]?
    @State private var error = ""
    var body: some View {
        Group {
            if !error.isEmpty { VStack { Text(error); Button("Retry") { Task { await load() } } } }
            else if let titles {
                if titles.isEmpty { ContentUnavailableView("No favorites yet", systemImage: "heart", description: Text("Open a movie or show and tap Add to Favorites.")) }
                else { ScrollView { PhonePosterRow(server: server, titles: titles) } }
            } else { ProgressView() }
        }.navigationTitle("Favorites").task { await load() }
    }
    private func load() async {
        do { titles = try await server.request("/api/watchlist"); error = "" }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct LibraryHome: View {
    let server: Server
    let libraries: [Library]
    @State private var shelves: [String: [Title]] = [:]
    @State private var failures: Set<String> = []
    @State private var picks: [Title] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let feature = libraries.compactMap({ shelves[$0.id]?.first }).first {
                    NavigationLink { PhoneDetail(server: server, title: feature) } label: {
                        Poster(server: server, title: feature, landscape: true)
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title).font(.largeTitle.bold()).lineLimit(2)
                                    if let year = feature.year { Text(String(year)).font(.subheadline) }
                                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                 .background(LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                            }.clipShape(RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).padding(.horizontal)
                }
                DisclosureGroup {
                    Text("Browse your movies and shows or channel surf in Retro TV with the Siri Remote. Invited testers can open TestFlight on Apple TV, install Noxa Player, and sign in with the same server address and viewer account.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                } label: {
                    Label("Noxa Player on Apple TV", systemImage: "appletv")
                        .font(.headline)
                }
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                if !picks.isEmpty {
                    Text("What to Watch").font(.title2.bold()).padding(.horizontal)
                    PhonePosterRow(server: server, titles: picks)
                }
                ForEach(libraries) { library in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { LibraryScreen(server: server, library: library) } label: {
                            HStack {
                                Text(library.title).font(.title2.bold())
                                Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.mint)
                            }
                        }.buttonStyle(.plain).padding(.horizontal)
                        if let titles = shelves[library.id] {
                            PhonePosterRow(server: server, titles: titles)
                        } else if failures.contains(library.id) {
                            Button("Retry loading titles") { Task { await load(library) } }.padding(.horizontal)
                        } else { ProgressView().padding(.horizontal) }
                    }.task(id: library.id) { if shelves[library.id] == nil { await load(library) } }
                }
            }.padding(.vertical)
        }.background(CinemaBackground()).task {
            if let feed: HomeFeed = try? await server.request("/api/home") {
                let favorites: [Title] = (try? await server.request("/api/watchlist")) ?? []
                picks = viewerPicks(feed: feed, favorites: favorites)
            }
        }
    }

    private func load(_ library: Library) async {
        do {
            let page: Page = try await server.request(Server.path("/api/libraries/\(library.id)/items", [.init(name: "size", value: "12"), .init(name: "sort", value: "title")]))
            shelves[library.id] = page.items
            failures.remove(library.id)
        } catch { if !Task.isCancelled { failures.insert(library.id) } }
    }
}

private struct LibraryScreen: View {
    let server: Server
    let library: Library
    @State private var items: [Title] = []
    @State private var more = true
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        ScrollView {
            if let feature = items.first {
                NavigationLink { PhoneDetail(server: server, title: feature) } label: {
                    ZStack(alignment: .bottomLeading) {
                        Poster(server: server, title: feature, landscape: true)
                        LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                        Text(feature.label).font(.title.bold()).padding()
                    }.aspectRatio(16.0/9, contentMode: .fit)
                     .clipShape(RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).padding(.horizontal)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 14)], alignment: .leading, spacing: 18) {
                ForEach(items) { title in
                    NavigationLink {
                        PhoneDetail(server: server, title: title)
                    } label: {
                        VStack(alignment:.leading) {
                            Poster(server: server, title: title).clipShape(RoundedRectangle(cornerRadius:8))
                            Text(title.title).font(.subheadline.bold()).lineLimit(2)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding()
            if !error.isEmpty { Text(error) }
            if more { Button(busy ? "Loading…" : "Load more") { Task { await load() } }.disabled(busy) }
        }.background(CinemaBackground()).navigationTitle(library.title).task { if items.isEmpty { await load() } }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let page: Page = try await server.request(Server.path("/api/libraries/\(library.id)/items",
                [.init(name:"start",value:String(items.count)),.init(name:"size",value:"50"),.init(name:"sort",value:"title")]))
            items += page.items; more = !page.items.isEmpty && items.count < page.total; error = ""
        } catch { self.error = error.localizedDescription }
    }
}

private struct PhoneDetail: View {
    let server: Server
    let title: Title
    @State private var children: [Title] = []
    @State private var playing = false
    @State private var message = ""
    @State private var favorite: Bool?
    @State private var saving = false
    var grouped: Bool { title.type == "show" || title.type == "season" }
    var body: some View {
        List {
            Poster(server: server, title: title, landscape: true).listRowInsets(EdgeInsets())
            if let summary = title.summary, !summary.isEmpty { Text(summary) }
            if grouped {
                ForEach(children) { child in
                    NavigationLink(child.label) { PhoneDetail(server: server, title: child) }
                }
            } else { Button("Play") { playing = true } }
            if let favorite {
                Button {
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            let _: Empty = try await server.request("/api/items/\(title.id)/watchlist", ["on": !favorite])
                            self.favorite = !favorite; message = ""
                        } catch { message = error.localizedDescription }
                    }
                } label: { Label(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "heart.fill" : "heart") }
                .disabled(saving)
            }
            if !message.isEmpty { Text(message) }
        }.navigationTitle(title.label)
        .task(id:title.id) {
            if ["movie", "show"].contains(title.type) {
                do { let item: Title = try await server.request("/api/items/\(title.id)"); favorite = item.in_watchlist ?? false }
                catch { message = error.localizedDescription }
            }
            if grouped {
                do { children = try await server.request("/api/items/\(title.id)/children") }
                catch { message = error.localizedDescription }
            }
        }.fullScreenCover(isPresented:$playing) { Playback(server:server,title:title) }
    }
}
