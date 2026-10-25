import SwiftUI

struct HomeView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var demo = DemoSession.shared
    @ObservedObject private var marc = MarcTestMatch.shared
    @State private var showingMarcChat = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        InTuneLogoView().frame(maxWidth: .infinity)
                        Text("Good music.\nBetter connections.").font(.largeTitle.bold())
                        Text("Meet through the songs you love.").foregroundStyle(.secondary)
                        if demo.isActive {
                            DemoBadge()
                            Text("Explore sample profiles and build your music overview. Everything in demo mode stays on this device; likes don't create real matches or send messages.")
                            Button("Discover sample profiles") {
                                selectedTab = 1
                            }.buttonStyle(.borderedProminent).tint(InTuneBrand.pink).controlSize(.large)
                            HStack(spacing: 16) {
                                stat("\(demo.remaining.count)", "To discover")
                                stat("\(demo.liked.count)", "Demo likes")
                                stat("\(demo.taste.genres.count)", "Your genres")
                            }
                            Text("Your demo likes").font(.title2.bold())
                            if demo.liked.isEmpty {
                                Label("Like a sample profile in Discover to see it here.", systemImage: "heart")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(demo.liked) { person in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(person.name), \(person.age)").font(.headline)
                                    Text(person.taste.showcaseTrack?.name ?? "Sample music").foregroundStyle(.secondary)
                                    Text("Demo like · no mutual match").font(.caption).foregroundStyle(InTuneBrand.pink)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                    .background(InTuneBrand.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                            }
                            Button("View my music overview") { selectedTab = 2 }
                            Button("Reset demo likes and passes", role: .destructive) { demo.resetCards() }
                        } else {
                            if music.connected {
                                if marc.state.matched {
                                    Button {
                                        showingMarcChat = true
                                    } label: {
                                        Label("Message Marc · test match", systemImage: "bubble.left.and.bubble.right")
                                    }.buttonStyle(.borderedProminent)
                                } else {
                                    Button("Meet Marc · test profile") { selectedTab = 1 }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                            if let taste = music.taste {
                                Text("Your music taste").font(.title2.bold())
                                Text(taste.summary)
                                GenreTags(genres: Array(taste.genres.prefix(8)).map(\.name))
                                if let song = taste.showcaseTrack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Your showcase song").font(.caption).foregroundStyle(.secondary)
                                        Text(song.name).font(.headline)
                                        Text(song.artists.map(\.name).joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Button("View my music") { selectedTab = 2 }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Text(music.connected ? "Your Spotify account is connected. Import your music to build your overview." : "Connect Spotify to build your music profile from the artists and songs you love.")
                                    .foregroundStyle(.secondary)
                                Button(music.connected ? "Import my music" : "Connect Spotify") { selectedTab = 2 }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                    }.padding(24)
                }.navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.inline)
                    .inTuneCornerMark()
            }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { MusicCardView() }
                .tabItem { Label("Discover", systemImage: "music.note") }.tag(1)
            NavigationStack { Profile() }
                .tabItem { Label("My music", systemImage: "person.crop.circle") }.tag(2)
        }.tint(InTuneBrand.pink)
            .sheet(isPresented: $showingMarcChat) { MarcChatView() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(InTuneBrand.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
