import SwiftUI
import AVKit

#if os(tvOS)
@main struct ScreenroomApp: App {
    var body: some Scene { WindowGroup { Root() } }
}

struct Root: View {
    @AppStorage("server") private var saved = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var ticket: String?
    @State private var account: Account?
    @State private var active: Server?
    @State private var message = ""
    @State private var busy = false
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            if let account, let active {
                BrowseHome(server: active, libraries: account.libraries) {
                    Task {
                        do {
                            let _: Empty = try await active.request("/api/logout", [:])
                            self.account = nil; self.active = nil; ticket = nil; code = ""
                        } catch { message = error.localizedDescription }
                    }
                }
            } else {
                VStack(spacing: 28) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 90)).foregroundStyle(.mint)
                    Text("Noxa Player").font(.system(size: 92, weight: .black, design: .rounded))
                    Button("Connect to server") { showingLogin = true }
                    .navigationDestination(isPresented: $showingLogin) {
                        VStack(spacing: 18) {
                            if ticket == nil {
                                TextField("Server URL", text: $address).textContentType(.URL)
                                TextField("Username", text: $username).textContentType(.username)
                                SecureField("Password", text: $password).textContentType(.password)
                            } else {
                                TextField("Verification code", text: $code)
                                Button("Back to sign in") { ticket = nil; code = "" }
                            }
                            Button(busy ? "Connecting…" : "Sign in") { Task { await connect() } }
                                .disabled(busy || (ticket == nil && (address.isEmpty || username.isEmpty || password.isEmpty)))
                        }.frame(maxWidth: 680)
                        .navigationTitle("Connect to your Noxa server")
                    }
                    Button("Explore sample libraries") { active = .sample; account = SampleLibrary.account }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(CinemaBackground())
            }
        }
        .task {
            address = saved
            if let server = try? Server(saved), let me: Account = try? await server.request("/api/me") {
                active = server; account = me
            }
        }
        .preferredColorScheme(.dark)
        .alert("Connection", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("OK") { message = "" }
        } message: { Text(message) }
    }

    @MainActor private func connect() async {
        busy = true; defer { busy = false }
        do {
            let server = try Server(address)
            if let ticket {
                let _: Empty = try await server.request("/api/login/2fa", ["ticket": ticket, "code": code])
            } else {
                let login: Login = try await server.request("/api/login", ["username": username, "password": password])
                if let challenge = login.ticket { ticket = challenge; return }
            }
            let me: Account = try await server.request("/api/me")
            password = ""; code = ""; ticket = nil; saved = address; showingLogin = false; active = server; account = me
        } catch { message = error.localizedDescription }
    }
}

struct Shelf: View {
    let server: Server
    let library: Library
    var genre: String? = nil
    @State private var titles: [Title] = []
    @State private var total = 0
    @State private var failure = ""
    @State private var loading = false
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 48)], alignment: .leading, spacing: 44) {
                ForEach(titles) { title in
                    NavigationLink {
                        Detail(server: server, title: title)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Poster(server: server, title: title)
                            Text(title.title).foregroundStyle(.primary).font(.headline).lineLimit(2)
                            if let year=title.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(12)
                    }.buttonStyle(.card)
                }
            }.padding(30)
            if titles.count < total && !loading { Button("Load more") { Task { await load() } } }
            if loading { ProgressView() }
            if !failure.isEmpty { Text(failure); Button("Retry") { Task { await load() } } }
            if !loading && failure.isEmpty && total == 0 { Text("This library is empty.") }
        }.background(CinemaBackground()).navigationTitle(genre ?? library.title).task { if titles.isEmpty { await load() } }
    }
    @MainActor func load() async {
        guard !loading else { return }; loading=true; defer { loading=false }
        do {
            var query=[URLQueryItem(name:"start",value:String(titles.count)),URLQueryItem(name:"size",value:"100"),URLQueryItem(name:"sort",value:"title")]
            if let genre { query.append(.init(name:"genre",value:genre)) }
            let page:Page=try await server.request(Server.path("/api/libraries/\(library.id)/items",query))
            titles += page.items; total=page.total; failure=""
        } catch { failure=error.localizedDescription }
    }
}

struct Detail: View {
    let server:Server
    let title:Title
    @State private var children:[Title]=[]
    @State private var episodes:[Title]=[]
    @State private var selectedSeason=""
    @FocusState private var focusedEpisode: String?
    @FocusState private var primaryFocused: Bool
    @State private var returnEpisode: String?
    @State private var episodeBlurb = ""
    @State private var resumeEpisode:Title?
    @State private var playbackTitle:Title?
    @State private var detail:Title?
    @State private var failure=""
    @State private var favorite:Bool?
    @State private var savingFavorite=false
    @State private var playing=false
    @State private var loaded=false
    var grouped:Bool { ["show","season"].contains(title.type) }
    var body:some View {
        ScrollView {
            HStack(alignment:.top,spacing:76) {
                Poster(server:server,title:detail ?? title).frame(width:390).clipShape(RoundedRectangle(cornerRadius:22))
                VStack(alignment:.leading,spacing:24) {
                    Text(title.label).font(.system(size:72,weight:.bold,design:.rounded))
                    let info = detail ?? title
                    Text(([info.year.map(String.init),info.duration.map { "\($0 / 60000) min" }].compactMap { $0 } + (info.genres ?? [])).joined(separator:"  ·  ")).foregroundStyle(.mint)
                    if let pos=info.position, let duration=info.duration, pos>0 && duration>0 {
                        ProgressView(value:min(1,Double(pos)/Double(duration))).tint(.mint)
                    }
                    if let summary = (detail ?? title).summary, !summary.isEmpty {
                        Text(summary).font(.body).foregroundStyle(.white.opacity(0.83))
                    }
                    if grouped {
                        if let next = resumeEpisode ?? episodes.first(where:{ $0.watched != true }) ?? episodes.first {
                            Button(resumeEpisode == nil ? "Play " + next.label : "Continue " + next.label) {
                                returnEpisode=nil; playbackTitle=next; playing=true
                            }.focused($primaryFocused)
                        }
                        if title.type == "show", !children.isEmpty {
                            Picker("Season", selection:$selectedSeason) {
                                ForEach(children) { Text($0.label).tag($0.id) }
                            }
                        }
                        ForEach(episodes) { episode in
                            Button { returnEpisode=episode.id; playbackTitle=episode; playing=true } label: {
                                HStack(spacing:24) {
                                    Poster(server:server,title:episode).frame(width:116,height:78).clipped()
                                    VStack(alignment:.leading) {
                                        Text(episode.label).lineLimit(2)
                                        if focusedEpisode == episode.id && !episodeBlurb.isEmpty {
                                            Text(episodeBlurb).font(.caption).lineLimit(2)
                                        }
                                        if let duration=episode.duration {
                                            Text("\(duration/60000) min").font(.caption)
                                            if let pos=episode.position, pos>0, duration>0 { ProgressView(value:min(1,Double(pos)/Double(duration))) }
                                        }
                                    }
                                    Spacer()
                                }
                            }.focused($focusedEpisode, equals: episode.id)
                        }
                        if loaded && children.isEmpty { Text("No episodes available.") }
                    } else {
                        Button { playbackTitle=detail ?? title; playing=true } label: {
                            Label((info.position ?? 0)>0 && info.watched != true ? "Resume" : "Play", systemImage:"play.fill")
                        }
                    }
                    if let favorite {
                        Button {
                            Task { await setFavorite(!favorite) }
                        } label: {
                            Label(favorite ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: favorite ? "heart.fill" : "heart")
                        }.disabled(savingFavorite)
                    }
                    if !failure.isEmpty { Text(failure); Button("Retry") { Task { await load() } } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(60)
        }.background {
            GeometryReader { geo in
                Poster(server:server,title:detail ?? title,landscape:true)
                    .frame(width:geo.size.width,height:geo.size.height).clipped().opacity(0.25)
            }.background(Color.black)
        }.task { await load() }
        .task(id: focusedEpisode) {
            episodeBlurb = ""
            guard let id = focusedEpisode else { return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let item: Title? = try? await server.request("/api/items/\(id)")
            if !Task.isCancelled { episodeBlurb = item?.summary ?? "" }
        }
        .task(id:selectedSeason) {
            guard !selectedSeason.isEmpty else { return }
            episodes=[]
            do {
                let list:[Title]=try await server.request("/api/items/\(selectedSeason)/children")
                try Task.checkCancellation()
                episodes=list
            } catch { if !Task.isCancelled { failure=error.localizedDescription } }
        }
        .fullScreenCover(isPresented: $playing, onDismiss: {
            Task {
                await load()
                if grouped {
                    primaryFocused=false; focusedEpisode=nil
                    try? await Task.sleep(for:.milliseconds(250))
                    if let returnEpisode { focusedEpisode=returnEpisode }
                    else { primaryFocused=true }
                }
            }
        }) {
            Playback(server: server, title: playbackTitle ?? detail ?? title)
        }
    }
    @MainActor private func setFavorite(_ on: Bool) async {
        guard !savingFavorite else { return }
        savingFavorite = true
        defer { savingFavorite = false }
        do {
            let _: Empty = try await server.request("/api/items/\(title.id)/watchlist", ["on": on])
            favorite = on
            failure = ""
        } catch { failure = error.localizedDescription }
    }
    @MainActor func load() async {
        do {
            if grouped { children = try await server.request("/api/items/\(title.id)/children") }
            if title.type == "season" { episodes=children }
            if title.type == "show" {
                let feed:HomeFeed? = try? await server.request("/api/home")
                resumeEpisode=feed?.continue.first { $0.show_id==title.id && $0.type=="episode" }
                if selectedSeason.isEmpty { selectedSeason=children.first?.id ?? "" }
            }
            if title.type != "season" { detail = try await server.request("/api/items/\(title.id)") }
            if title.type == "movie" || title.type == "show" { favorite = detail?.in_watchlist }
            loaded = true; failure = ""
        } catch { failure = error.localizedDescription }
    }
}

#endif

struct Playback: View {
    let server: Server
    let title: Title
    var startAtBeginning = false
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var stream: Stream?
    @State private var failure = ""
    @State private var observer: Any?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !failure.isEmpty {
                VStack { Text(failure); Button("Back") { dismiss() } }
            } else if stream != nil {
                #if os(iOS)
                PhoneVideoScreen(player: player).ignoresSafeArea()
                #else
                VideoPlayer(player: player).ignoresSafeArea()
                #endif
            }
            else { ProgressView() }
        }
        .task {
            do {
                let position = startAtBeginning || title.watched == true ? 0 : title.position ?? 0
                let info: Stream = try await server.request("/api/play", ["id": title.id,"offset":position,"quality":"original",
                    "caps":["video":["h264","hevc","hevc10"],"audio":["aac","ac3","eac3","mp3"],"containers":["mov","mp4"]]])
                if Task.isCancelled { let _: Empty? = try? await server.request("/api/stop", ["stream":info.stream]); return }
                stream = info
                let item = AVPlayerItem(asset: try server.asset(info.url))
                player.replaceCurrentItem(with: item)
                if info.offset > 0 { await player.seek(to: CMTime(value: Int64(info.offset), timescale: 1000)) }
                observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 600), queue: .main) { time in
                    Task { await report(info, time: time, state: "playing") }
                }
                player.play()
            } catch { failure = error.localizedDescription }
        }
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #else
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).padding(12) }
                .foregroundStyle(.white).accessibilityLabel("Done")
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, item === player.currentItem { failure = item.error?.localizedDescription ?? "Playback failed." }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, item === player.currentItem { dismiss() }
        }
        .onDisappear {
            player.pause()
            if let observer { player.removeTimeObserver(observer); self.observer = nil }
            if let stream {
                let time = player.currentTime()
                Task {
                    await report(stream, time: time, state: "stopped")
                    let _: Empty? = try? await server.request("/api/stop", ["stream":stream.stream])
                }
            }
        }
    }
    func report(_ info: Stream, time: CMTime, state: String) async {
        guard time.seconds.isFinite, time.seconds > 0 else { return }
        let _: Empty? = try? await server.request("/api/progress", ["id":title.id,"stream":info.stream,
            "position":Int(time.seconds * 1000),"duration":info.duration,"state":state])
    }
}

struct CinemaBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.065)
            RadialGradient(colors: [.teal.opacity(0.45), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 1300)
            RadialGradient(colors: [.indigo.opacity(0.40), .clear], center: .bottomLeading,
                           startRadius: 0, endRadius: 1000)
        }.ignoresSafeArea()
    }
}

struct Poster: View {
    let server: Server
    let title: Title
    var landscape = false
    @State private var artwork: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [.teal.opacity(0.6), .indigo.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if server.isSample, let image = UIImage(named: title.type == "movie" ? "HorizonPoster.jpg" : "FirstLightPoster.jpg") {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: title.type == "show" ? "tv" : "film").font(.largeTitle)
            }
        }
        .aspectRatio(landscape ? 16.0/9 : 2.0/3, contentMode: .fit).clipped().accessibilityHidden(true)
        .task(id: title.id) {
            artwork = nil
            guard let thumb = landscape ? title.art : title.thumb else { return }
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "p", value: thumb), URLQueryItem(name: "w", value: landscape ? "1280" : "360"), URLQueryItem(name: "h", value: landscape ? "720" : "540")]
            guard let query = components.percentEncodedQuery, let url = try? server.endpoint("/api/img?" + query) else { return }
            if let (data, response) = try? await Server.session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 {
                if !Task.isCancelled { artwork = UIImage(data: data) }
            }
        }
    }
}

private struct RetroStation: Identifiable {
    let id: String
    let name: String
    let programs: [Title]

    var isFeatured: Bool {
        let category = name.components(separatedBy: " · ").first
        return category == "Classic Westerns" || category == "Public TV Classics"
    }

    func schedule(at date: Date) -> (current: Title, offset: Int, next: Title, starts: Date) {
        let length = programs.reduce(0) { $0 + ($1.duration ?? 0) }
        var time = Int(date.timeIntervalSince1970 * 1000) % length
        for (index, title) in programs.enumerated() {
            let duration = title.duration ?? 0
            if time < duration {
                return (title, time, programs[(index + 1) % programs.count],
                        date.addingTimeInterval(Double(duration - time) / 1000))
            }
            time -= duration
        }
        return (programs[0], 0, programs[0], date)
    }
}

private extension Array where Element == RetroStation {
    var guideOrder: [Int] {
        indices.filter { self[$0].id == "for-you" } + indices.filter { self[$0].isFeatured } + indices.filter { self[$0].id != "for-you" && !self[$0].isFeatured }
    }
}

private struct RetroGuide: View {
    let stations: [RetroStation]
    let channel: Int
    let select: (Int) -> Void
    @FocusState private var focused: Int?

    private func programName(_ title: Title) -> String {
        title.show.map { $0 + " · " + title.label } ?? title.title
    }

    var body: some View {
        let indices = stations.guideOrder
        VStack(alignment: .leading, spacing: 24) {
            Text("Channel Guide").font(.largeTitle.bold())
            ScrollView {
                VStack(spacing: 22) {
                    ForEach(indices, id: \.self) { index in
                        let station = stations[index]
                        Button { select(index) } label: {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                let schedule = station.schedule(at: tick.date)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(format: "CH %02d", index + 2) + "   " + station.name).font(.headline)
                                    Text("Now   " + programName(schedule.current))
                                    Text("Up next   " + schedule.starts.formatted(date: .omitted, time: .shortened) + "   " + programName(schedule.next)).font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .focused($focused, equals: index)
                        .accessibilityIdentifier("retro-guide-" + station.name)
                    }
                }.padding(32)
            }
        }.padding(48)
        .onAppear { focused = stations.indices.contains(channel) && stations[channel].isFeatured ? channel : indices.first }
    }
}

private struct RetroGlass: ViewModifier {
    let compact: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if compact {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.black.opacity(0.8), lineWidth: 4) }
                .padding(10)
                .background(LinearGradient(colors: [Color(white: 0.10), Color(white: 0.29)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 36))
        } else {
            content.aspectRatio(4.0/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 46))
                .padding(18).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 55))
        }
    }
}

private extension View {
    @ViewBuilder func retroGuidePresentation<Guide: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Guide) -> some View {
        #if os(iOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

struct RetroTV: View {
    @Environment(\.scenePhase) private var scenePhase
    let server: Server
    let libraries: [Library]
    @State private var stations: [RetroStation] = []
    @State private var channel = 0
    @State private var power = true
    @State private var error = ""
    @State private var loaded = false
    @AppStorage("retroVolume") private var volume = 0.8
    @State private var guide = false
    @State private var generation = 0
    @State private var tuning = false
    @State private var nowPlaying = ""
    @State private var remoteReplay: Title?
    @State private var castingToReceiver = false
    @State private var player = AVPlayer()

    @AppStorage("retroCompactBezel") private var compact = false
    @State private var replay: Title?

    #if os(tvOS)
    private var television: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 38))
        return layout {
            ZStack(alignment: .topLeading) {
                Color.black
                if power {
                    RetroScreen(player: player)
                    if tuning {
                        Canvas { context, size in
                            for line in 0..<180 {
                                let shade = Double((line * 37 + channel * 11) % 89) / 110
                                let y = CGFloat(line) * size.height / 180
                                context.fill(Path(CGRect(x:0,y:y,width:size.width,height:size.height/180)),with:.color(.white.opacity(shade)))
                            }
                        }.background(.black).accessibilityHidden(true)
                    }
                    Canvas { context, size in
                        for y in stride(from: 0, to: size.height, by: 5) {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12)))
                        }
                    }.allowsHitTesting(false)
                    if stations.indices.contains(channel) {
                        VStack(alignment: .leading) {
                            Text(String(format: "CH %02d", channel + 2)).font(.system(size: 54, weight: .bold, design: .monospaced))
                            Text(stations[channel].name)
                            Text(nowPlaying).font(.caption)
                        }.foregroundStyle(.green).shadow(color: .black, radius: 3).padding(38)
                    }
                    if !error.isEmpty { Text(error).padding().background(.black).frame(maxWidth: .infinity,maxHeight: .infinity) }
                    else if !loaded { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
                }
            }.modifier(RetroGlass(compact: compact))
            let controls = compact ? AnyLayout(HStackLayout(spacing: 18)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            controls {
                if !compact {
                Canvas { context, size in
                    for y in stride(from: 4, to: size.height, by: 10) {
                        context.fill(Path(roundedRect: CGRect(x: 2, y: y, width: size.width-4, height: 5), cornerRadius: 2), with: .color(.black.opacity(0.7)))
                    }
                }.frame(height: 32).accessibilityHidden(true)
                Text("RETRO TV").font(.system(size:48,weight:.black,design:.rounded))
                }
                Button(power ? "Power Off" : "Power On") { power.toggle() }
                Button("CH ▲") { tune(1) }.disabled(!power || stations.isEmpty)
                Button("CH ▼") { tune(-1) }.disabled(!power || stations.isEmpty)
                HStack {
                    Button("−") { volume=max(0,volume-0.1) }.accessibilityLabel("Volume down")
                    Text("\(Int((volume*10).rounded()))").monospacedDigit()
                    Button("+") { volume=min(1,volume+0.1) }.accessibilityLabel("Volume up")
                }
                Button("Guide") { guide = true }.disabled(stations.isEmpty)
                Button("Start Over") {
                    guard stations.indices.contains(channel) else { return }
                    replay = stations[channel].schedule(at: Date()).current
                }.disabled(!power || !stations.indices.contains(channel))
                Button(compact ? "Classic Bezel" : "Compact Bezel") { compact.toggle() }
                if !error.isEmpty { Button("Retry") { generation += 1; if stations.isEmpty { Task { await load() } } } }
            }.font(compact ? .caption : .body).frame(width:compact ? nil : 340)
        }.padding(compact ? 16 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors:[Color(white:0.32),Color(white:0.18),Color(white:0.12)],startPoint:.topLeading,endPoint:.bottomTrailing),
                        in: RoundedRectangle(cornerRadius:42))
            .overlay { RoundedRectangle(cornerRadius:42).strokeBorder(.white.opacity(0.13),lineWidth:3) }
            .shadow(color:.black.opacity(0.8),radius:24,y:18)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(RadialGradient(colors:[Color(red:0.13,green:0.12,blue:0.1),.black],center:.center,startRadius:180,endRadius:1100))
            .ignoresSafeArea(.container)
    }
    #else
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingControls = true
    @AppStorage("phoneRetroControlsDelay") private var controlsDelay = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var editingControls = false

    @State private var routeIsExternal = false
    private var externalPlayback: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-testAirPlayRemote") { return true }
        #endif
        return routeIsExternal
    }
    @State private var destination = "AirPlay"

    private func refreshDestination() {
        let receiver = AVAudioSession.sharedInstance().currentRoute.outputs.first { $0.portType == .airPlay }
        destination = receiver?.portName ?? "AirPlay"
        castingToReceiver = receiver != nil
    }

    private var airPlayRemote: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(destination, systemImage: "airplayvideo").font(.headline)
                Spacer()
                RetroRoutePicker().frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 10) {
                programInfo
                if stations.indices.contains(channel) {
                    let next = stations[channel].schedule(at: Date()).next
                    Text("Up next · " + next.label).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label("Swipe down for next channel", systemImage: "arrow.down")
                    .font(.footnote)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    tune(value.translation.height > 0 ? 1 : -1)
                }
            })
            phoneControls.controlSize(.large)
        }.padding().background(CinemaBackground())
    }

    private func phoneScreen(portrait: Bool) -> some View {
        ZStack {
                    Color.black
                    RetroScreen(player: player)
                    if tuning || !loaded { ProgressView().tint(.white) }
                }
        .contentShape(Rectangle())
        .accessibilityIdentifier("retro-screen")
        .highPriorityGesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard !stations.isEmpty else { return }
            let delta = value.translation
            if abs(delta.width) > abs(delta.height) {
                tune(delta.width < 0 ? 1 : -1)
            } else if portrait {
                tune(delta.height > 0 ? 1 : -1)
            }
        })
        .onTapGesture(count: 2) { showingControls.toggle() }
        .onTapGesture { if !portrait || !showingControls { showingControls.toggle() } }
    }

    private var programInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            if stations.indices.contains(channel) {
                Text(String(format: "CH %02d", channel + 2) + "  ·  " + stations[channel].name)
                    .font(.subheadline.bold()).foregroundStyle(.mint)
                Text(nowPlaying).font(.title2.bold()).lineLimit(2)
            }
        }
    }

    @ViewBuilder private var phoneControls: some View {
                HStack {
                    Button { tune(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    Spacer()
                    Button { tune(1) } label: { Label("Next", systemImage: "chevron.right") }
                }.buttonStyle(.bordered).disabled(stations.isEmpty)
                HStack {
                    Button { editingControls = true } label: {
                        Image(systemName: "slider.horizontal.3").accessibilityLabel("Control visibility")
                    }
                    Button("Guide") { guide = true }
                    if externalPlayback {
                        Button(remoteReplay == nil ? "Start Over" : "Back to Live") {
                            remoteReplay = remoteReplay == nil ? stations[channel].schedule(at: Date()).current : nil
                        }
                    } else {
                        Button("Start Over") { replay = stations[channel].schedule(at: Date()).current }
                    }
                }.buttonStyle(.borderedProminent).disabled(!stations.indices.contains(channel))
                if !error.isEmpty {
                    Text(error)
                    Button("Retry") { generation += 1; if stations.isEmpty { Task { await load() } } }
                }
    }

    private var television: some View {
        let wide = verticalSizeClass == .compact
        return Group {
            if externalPlayback {
                airPlayRemote.background { RetroScreen(player: player).accessibilityHidden(true) }
            } else if wide {
                phoneScreen(portrait: false)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .accessibilityLabel("Toggle playback controls")
                        .accessibilityAddTraits(.isButton)
                        .overlay(alignment: .bottom) {
                            if showingControls || !error.isEmpty {
                                HStack(alignment: .bottom, spacing: 24) {
                                    programInfo.frame(maxWidth: .infinity, alignment: .leading)
                                    VStack(spacing: 4) { phoneControls }.frame(maxWidth: 245)
                                }.padding(.horizontal).padding(.vertical, 6)
                                 .background(LinearGradient(colors: [.clear, .black.opacity(0.86)], startPoint: .top, endPoint: .bottom))
                            }
                        }.background { Color.black.ignoresSafeArea() }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                        phoneScreen(portrait: true).aspectRatio(16.0/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.25)) }
                        ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            programInfo
                            if showingControls || !error.isEmpty { phoneControls }
                        }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                }.padding().background(CinemaBackground())
            }
        }.overlay(alignment: .topTrailing) {
            if !externalPlayback {
                RetroRoutePicker().frame(width: 48, height: 48)
                    .background(.thinMaterial, in: Circle()).padding(8)
            }
        }
        .onReceive(player.publisher(for: \.isExternalPlaybackActive)) { active in
            routeIsExternal = active
            refreshDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in refreshDestination() }
        .navigationTitle("Retro TV")
         .toolbar(wide ? .hidden : .visible, for: .navigationBar, .tabBar)
         .statusBarHidden(wide)
         .confirmationDialog("Control visibility", isPresented: $editingControls, titleVisibility: .visible) {
             Button("Always on") { controlsDelay = 0 }
             Button("Hide after 5 seconds") { controlsDelay = 5 }
             Button("Hide after 10 seconds") { controlsDelay = 10 }
         }
         .task(id: "\(controlsDelay)-\(showingControls)-\(channel)-\(guide)-\(replay != nil)-\(editingControls)-\(loaded)-\(scenePhase)-\(wide)-\(voiceOver)") {
             guard controlsDelay > 0, showingControls, loaded, !guide, replay == nil, !editingControls, !voiceOver, scenePhase == .active else { return }
             do { try await Task.sleep(for: .seconds(controlsDelay)); showingControls = false } catch {}
         }
    }
    #endif

    private var allowsBroadcast: Bool {
        #if os(iOS)
        return true // Keep the channel session alive during the transition to Picture in Picture.
        #else
        return scenePhase == .active
        #endif
    }

    var body: some View {
        television
            .onChange(of:volume) { _, value in player.volume=Float(value) }
            .task { await load() }
            .task(id:"\(power)-\(stations.indices.contains(channel) ? stations[channel].id : "")-\(generation)-\(castingToReceiver)-\(remoteReplay?.id ?? "")-\(replay != nil)-\(allowsBroadcast)") { await broadcast() }
            .fullScreenCover(item: $replay) { title in
                Playback(server: server, title: title, startAtBeginning: true)
            }
            .retroGuidePresentation(isPresented: $guide) {
                #if os(iOS)
                NavigationStack {
                    List(stations.guideOrder, id: \.self) { index in
                        Button {
                            remoteReplay = nil
                            channel = index
                            guide = false
                        } label: {
                            TimelineView(.periodic(from: .now, by: 10)) { tick in
                                let station = stations[index]
                                let lineup = station.schedule(at: tick.date)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(String(format: "CH %02d", index + 2) + "   " + station.name).font(.headline)
                                    Text("Now · " + (lineup.current.show.map { $0 + " · " } ?? "") + lineup.current.label)
                                    Text("Up next · " + lineup.starts.formatted(date: .omitted, time: .shortened) + " · " + (lineup.next.show.map { $0 + " · " } ?? "") + lineup.next.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.accessibilityIdentifier("station-" + stations[index].name)
                    }.navigationTitle("Channel Guide")
                     .toolbar { Button("Done") { guide = false } }
                }
                #else
                RetroGuide(stations: stations, channel: channel) { index in
                    channel = index
                    power = true
                    guide = false
                }
                #endif
            }
    }

    private func tune(_ delta:Int) { guard !stations.isEmpty else { return }; remoteReplay = nil; channel=(channel+stations.count+delta)%stations.count }

    private func personalStation() async -> RetroStation? {
        guard let favorites: [Title] = try? await server.request("/api/watchlist"),
              let feed: HomeFeed = try? await server.request("/api/home"),
              !favorites.isEmpty || !(feed.suggestions ?? []).isEmpty else { return nil }
        let picks = viewerPicks(feed: feed, favorites: favorites)
        var lineup: [Title] = []
        var seen = Set<String>()
        for index in 0..<min(12, max(favorites.count, picks.count)) {
            for list in [favorites, picks] where index < list.count {
                if Task.isCancelled { return nil }
                var item = list[index]
                if item.type == "show" {
                    guard let seasons: [Title] = try? await server.request("/api/items/\(item.id)/children"),
                          let season = seasons.first,
                          let episodes: [Title] = try? await server.request("/api/items/\(season.id)/children"),
                          let episode = episodes.first(where: { ($0.duration ?? 0) > 0 }) else { continue }
                    item = episode
                }
                if (item.duration ?? 0) > 0 && seen.insert(item.id).inserted { lineup.append(item) }
            }
        }
        return lineup.isEmpty ? nil : RetroStation(id: "for-you", name: "For You", programs: lineup)
    }

    @MainActor private func load() async {
        var result:[RetroStation]=[]
        async let personal = personalStation()
        do {
            for library in libraries {
                let genres:[Genre] = try await server.request("/api/libraries/\(library.id)/genres")
                for genre in genres.sorted(by: { ($0.title != "Classic Westerns" ? 1 : 0, $0.title) < ($1.title != "Classic Westerns" ? 1 : 0, $1.title) }) {
                    let classic = genre.title == "Classic Westerns" && library.type == "show"
                    let page:Page = try await server.request(Server.path("/api/libraries/\(library.id)/items", [.init(name:"genre",value:genre.id),.init(name:"size",value:"24"),.init(name:"sort",value:"title")]))
                    var candidates=page.items
                    if library.type=="show" {
                        candidates=[]
                        var series: [[Title]] = []
                        for show in page.items.prefix(classic ? page.items.count : 3) {
                            let seasons:[Title]=try await server.request("/api/items/\(show.id)/children")
                            var list: [Title] = []
                            for season in seasons.prefix(classic ? seasons.count : 1) {
                                let episodes:[Title]=try await server.request("/api/items/\(season.id)/children")
                                list.append(contentsOf: episodes.prefix(classic ? episodes.count : 4))
                            }
                            if !list.isEmpty { series.append(list) }
                        }
                        if classic, let longest = series.map(\.count).max() {
                            // Spread shorter runs throughout the broadcast cycle.
                            for i in 0..<longest {
                                for list in series where i == 0 || i * list.count / longest != (i - 1) * list.count / longest {
                                    candidates.append(list[i * list.count / longest])
                                }
                            }
                        } else { candidates = series.flatMap { $0 } }
                    }
                    let programs=candidates.filter { ($0.duration ?? 0)>0 }
                    if !programs.isEmpty {
                        try Task.checkCancellation()
                        result.append(RetroStation(id:library.id+"/"+genre.id,name:classic ? genre.title : genre.title+" · "+library.title,programs:programs))
                        stations=result; loaded=true
                    }
                }
            }
            try Task.checkCancellation()
            if let station = await personal { result.append(station) }
            try Task.checkCancellation()
            stations=result; loaded=true; error=result.isEmpty ? "No programs with running times available." : ""
        } catch { if !Task.isCancelled { self.error=error.localizedDescription } }
    }

    @MainActor private func broadcast() async {
        guard allowsBroadcast,replay == nil,power,stations.indices.contains(channel) else { return }
        let station=stations[channel]
        #if os(iOS)
        let sessionPlayer = player
        #else
        let sessionPlayer=AVPlayer()
        #endif
        sessionPlayer.preventsDisplaySleepDuringVideoPlayback = true
        sessionPlayer.volume=Float(volume)
        player=sessionPlayer
        var ownedItem: AVPlayerItem?
        defer {
            if sessionPlayer.currentItem === ownedItem {
                sessionPlayer.pause()
                sessionPlayer.replaceCurrentItem(with: nil)
            }
            // A newer channel may already own the foreground playback session.
            if player === sessionPlayer { UIApplication.shared.isIdleTimerDisabled = false }
        }
        while !Task.isCancelled {
            let schedule = station.schedule(at: Date())
            let title = remoteReplay ?? schedule.current
            let offset = remoteReplay == nil ? schedule.offset : 0
            tuning=true
            nowPlaying=title.show.map { $0+" · "+title.label } ?? title.title
            error=""
            do {
                let info:Stream=try await server.request("/api/play",["id":title.id,"offset":offset,"cast":castingToReceiver,"quality":"original","caps":["video":["h264","hevc","hevc10"],"audio":["aac","ac3","eac3","mp3"],"containers":["mov","mp4"]]])
                defer { Task { let _:Empty? = try? await server.request("/api/stop",["stream":info.stream]) } }
                try Task.checkCancellation()
                let item=AVPlayerItem(asset:try server.asset(info.url))
                ownedItem = item
                sessionPlayer.replaceCurrentItem(with:item)
                if info.offset>0 { await sessionPlayer.seek(to:CMTime(value:Int64(info.offset),timescale:1000)) }
                try Task.checkCancellation()
                UIApplication.shared.isIdleTimerDisabled = true
                sessionPlayer.play()
                tuning=false
                let end=Date().addingTimeInterval(Double((title.duration ?? 0)-offset)/1000)
                while Date()<end {
                    try await Task.sleep(for:.seconds(1))
                    if item.status == .failed { throw item.error ?? ServerError("Unable to tune this channel.") }
                }
                if remoteReplay != nil { remoteReplay = nil; return }
            } catch { if !Task.isCancelled { tuning=false; self.error=error.localizedDescription }; return }
        }
    }
}

#if os(iOS)
private struct RetroRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .label
        return picker
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

private struct PhoneVideoScreen: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
#endif

private final class CRTSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var video: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct RetroScreen: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> CRTSurface {
        let view = CRTSurface()
        view.isUserInteractionEnabled = false
        view.video.videoGravity = .resizeAspect
        return view
    }
    #if os(iOS)
    final class Coordinator {
        var pictureInPicture: AVPictureInPictureController?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    #endif

    func updateUIView(_ view: CRTSurface, context: Context) {
        if view.video.player !== player { view.video.player = player }
        #if os(iOS)
        if context.coordinator.pictureInPicture == nil, AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(playerLayer: view.video)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            context.coordinator.pictureInPicture = controller
        }
        #endif
    }
}
