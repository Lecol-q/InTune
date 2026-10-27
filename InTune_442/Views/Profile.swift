import SwiftUI
import Combine

@MainActor
final class MusicProfileModel: ObservableObject {
    static let shared = MusicProfileModel()
    private let spotify = SpotifyMusicService()
    private var genreTask: Task<Void, Never>?
    private var genreGeneration = UUID()
    private var corrections: [String: ArtistGenreCorrection] = [:]
    @Published private(set) var genreLookupRunning = false
    @Published private(set) var genreChecked = 0
    @Published private(set) var genreTotal = 0
    @Published private(set) var genrePaused = false
    @Published var taste: MusicTaste?
    @Published var connected = false
    @Published var busy = false
    @Published var error: String?

    init() {
        // Retire the old test profile's saved conversation without affecting current chats.
        try? MusicVault.delete("marc-test-match")
        corrections = (try? MusicVault.read("genre-corrections", as: [String: ArtistGenreCorrection].self)) ?? [:]
        connected = spotify.isConnected
        DemoSession.shared.setSpotifyConnected(connected)
        do {
            if let saved = try MusicVault.read("taste", as: MusicTaste.self) {
                let enriched = MusicTasteBuilder.build(artists: ArtistGenreCorrection.apply(corrections, to: ArtistGenreService.shared.cachedEnrichment(saved.topArtists)), tracks: saved.topTracks,
                    previousShowcase: saved.showcaseTrackID, now: saved.updatedAt)
                taste = enriched
                if enriched != saved { try MusicVault.write(enriched, key: "taste") }
            }
        } catch { self.error = error.localizedDescription }
    }

    func sync() async {
        guard !busy else { return }
        pauseGenreLookup()
        busy = true
        error = nil
        defer {
            busy = false
            connected = spotify.isConnected
            DemoSession.shared.setSpotifyConnected(connected)
            findMissingGenres()
        }
        do {
            if !spotify.isConnected {
                try await spotify.connect()
                connected = true
                DemoSession.shared.setSpotifyConnected(true)
                taste = nil
                corrections = [:]
            }
            let raw = try await spotify.importTaste(previousShowcase: taste?.showcaseTrackID)
            let imported = MusicTasteBuilder.build(artists: ArtistGenreCorrection.apply(corrections, to: raw.topArtists),
                tracks: raw.topTracks, previousShowcase: raw.showcaseTrackID, now: raw.updatedAt)
            try MusicVault.write(imported, key: "taste")
            taste = imported
        } catch { self.error = error.localizedDescription }
    }

    func pauseGenreLookup() {
        genreGeneration = UUID()
        genreTask?.cancel()
        genreTask = nil
        genreLookupRunning = false
    }

    func findMissingGenres(retryMissing: Bool = false) {
        guard connected, !busy, !genreLookupRunning, let current = taste,
              current.topArtists.contains(where: { !ArtistGenreCatalog.hasGenres($0) }) else { return }
        let generation = UUID()
        genreGeneration = generation
        genreLookupRunning = true
        genrePaused = false
        genreChecked = 0
        genreTotal = current.topArtists.filter { !ArtistGenreCatalog.hasGenres($0) }.count
        genreTask = Task { [weak self] in
            _ = await ArtistGenreService.shared.enrich(current.topArtists, retryMissing: retryMissing) {
                [weak self] artists, checked, total, paused in
                guard let self, self.genreGeneration == generation, self.connected,
                      !Task.isCancelled, let latest = self.taste else { return }
                self.genreChecked = checked
                self.genreTotal = total
                self.genrePaused = self.genrePaused || paused
                let updated = MusicTasteBuilder.build(artists: ArtistGenreCorrection.apply(self.corrections, to: artists),
                    tracks: latest.topTracks, previousShowcase: latest.showcaseTrackID, now: latest.updatedAt)
                if updated != latest {
                    do {
                        try MusicVault.write(updated, key: "taste")
                        self.taste = updated
                    } catch { self.error = error.localizedDescription }
                }
            }
            guard let self, self.genreGeneration == generation else { return }
            self.genreLookupRunning = false
            self.genreTask = nil
        }
    }

    func hasGenreCorrection(_ artist: SpotifyArtist) -> Bool { corrections[artist.id] != nil }

    func saveGenres(for artist: SpotifyArtist, text: String) -> Bool {
        let tags = ArtistGenreCorrection.parse(text)
        guard !tags.isEmpty, tags.count <= 8, tags.allSatisfy({ $0.count <= 60 }) else {
            error = "Enter 1–8 genre tags, with up to 60 characters each."
            return false
        }
        var updated = corrections
        let latest = taste?.topArtists.first { $0.id == artist.id } ?? artist
        updated[artist.id] = ArtistGenreCorrection(tags: tags, original: corrections[artist.id]?.original ?? latest)
        return storeCorrections(updated)
    }

    func useCatalogGenres(for artist: SpotifyArtist) -> Bool {
        guard let original = corrections[artist.id]?.original, let current = taste else { return false }
        var updated = corrections
        updated.removeValue(forKey: artist.id)
        let restored = current.topArtists.map { item -> SpotifyArtist in
            guard item.id == artist.id else { return item }
            var result = item
            result.genres = original.genres
            result.genreSourceName = original.genreSourceName
            result.genreSourceURL = original.genreSourceURL
            return result
        }
        pauseGenreLookup()
        guard storeCorrections(updated, artists: restored) else { return false }
        findMissingGenres()
        return true
    }

    private func storeCorrections(_ updated: [String: ArtistGenreCorrection], artists: [SpotifyArtist]? = nil) -> Bool {
        guard let current = taste else { return false }
        let result = MusicTasteBuilder.build(artists: ArtistGenreCorrection.apply(updated, to: artists ?? current.topArtists),
            tracks: current.topTracks, previousShowcase: current.showcaseTrackID, now: current.updatedAt)
        do {
            // Overrides are the durable source of truth; startup reapplies them to the cached taste.
            try MusicVault.write(updated, key: "genre-corrections")
            corrections = updated
            taste = result
            try MusicVault.write(result, key: "taste")
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func selectShowcase(_ id: String?) {
        guard var updated = taste else { return }
        updated.showcaseTrackID = id
        do {
            try MusicVault.write(updated, key: "taste")
            taste = updated
        } catch { self.error = error.localizedDescription }
    }

    func disconnect() {
        pauseGenreLookup()
        do {
            try spotify.disconnect()
            corrections = [:]
            taste = nil
            connected = false
            DemoSession.shared.setSpotifyConnected(false)
            error = nil
        } catch {
            connected = spotify.isConnected
            DemoSession.shared.setSpotifyConnected(connected)
            self.error = error.localizedDescription
        }
    }
}

struct Profile: View {
    @ObservedObject private var model = MusicProfileModel.shared
    @ObservedObject private var demo = DemoSession.shared
    private var displayedTaste: MusicTaste? { demo.isActive ? demo.taste : model.taste }
    @State private var editingArtist: SpotifyArtist?
    @State private var confirmingDisconnect = false

    var body: some View {
        Form {
            Section("Your Spotify connection") {
                Text("Connect Spotify to import your top artists and songs and generate your music taste overview.")
                Text("You choose a showcase song. This prototype saves your music on this device. Missing artist genres are looked up in public MusicBrainz and Wikidata metadata; sharing profiles still requires the profile backend.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(model.connected ? "Refresh music from Spotify" : "Connect Spotify") {
                    Task {
                        await model.sync()
                    }
                }
                .disabled(model.busy)
                if model.busy { ProgressView("Loading your music…") }
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let taste = displayedTaste {
                Section("Music taste overview") {
                    Text(taste.summary)
                    Text(demo.isActive ? "Sample overview generated by the same genre-ranking algorithm used for Spotify imports." : "Based on your top Spotify artists and tracks over approximately six months.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(demo.isActive ? "Fictional sample data · not your Spotify history" : "Updated \(taste.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Top genres") {
                    if taste.genres.isEmpty {
                        Text("No genre tags found yet. Artist metadata is checked in the background. You can add missing tags below. Your songs and artists are still available.")
                    }
                    GenreTags(genres: Array(taste.genres.prefix(8)).map(\.name))
                    if !demo.isActive {
                        Text("Genres available for \(taste.topArtists.filter { ArtistGenreCatalog.hasGenres($0) }.count) of \(taste.topArtists.count) artists")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.genreLookupRunning {
                            ProgressView("Checking genre sources for your top 10…")
                        } else if taste.topArtists.contains(where: { !ArtistGenreCatalog.hasGenres($0) }) {
                            if model.genrePaused { Text("Some lookups could not finish. Retry when connected.").font(.caption) }
                            Button("Check all missing genres") { model.findMissingGenres(retryMissing: true) }
                                .disabled(model.busy)
                        }
                    }
                    Text("Genres are ranked from available artist tags, including your edits, not measured play counts. Tags describe the artist's catalog, not every individual song.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Showcase song") {
                    Picker("Song", selection: Binding<String?>(
                        get: { displayedTaste?.showcaseTrackID },
                        set: { id in
                            if demo.isActive { demo.selectShowcase(id) }
                            else { model.selectShowcase(id) }
                        }
                    )) {
                        Text("Choose a song").tag(String?.none)
                        ForEach(taste.topTracks) { track in
                            Text("\(track.name) — \(track.artists.map(\.name).joined(separator: ", "))")
                                .tag(Optional(track.id))
                        }
                    }
                    if let track = taste.showcaseTrack {
                        ShowcaseSongCard(song: .selected(track))
                    }
                }
                Section("Top 10 artists") {
                    ForEach(taste.topArtists) { artist in
                        VStack(alignment: .leading, spacing: 8) {
                            if let url = spotifyURL(artist.external_urls?["spotify"]) {
                                Link(artist.name, destination: url).font(.headline)
                            } else { Text(artist.name).font(.headline) }
                            if ArtistGenreCatalog.hasGenres(artist) {
                                GenreTags(genres: artist.genres ?? [])
                                if let name = artist.genreSourceName,
                                   let source = artist.genreSourceURL, let url = URL(string: source),
                                   url.scheme == "https",
                                   (name == "MusicBrainz" && url.host == "musicbrainz.org" ||
                                    name == "Wikidata" && url.host == "www.wikidata.org") {
                                    Link("Genre source: \(name)", destination: url).font(.caption)
                                }
                            } else {
                                Text("Genre tags not available yet").font(.caption).foregroundStyle(.secondary)
                            }
                            if artist.genreSourceName == "Your tags" {
                                Text("Your tags").font(.caption).foregroundStyle(.secondary)
                            }
                            if !demo.isActive {
                                Button(ArtistGenreCatalog.hasGenres(artist) ? "Edit genre tags" : "Add genre tags") {
                                    editingArtist = artist
                                }.font(.caption).buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Top songs") {
                    if taste.topTracks.isEmpty { Text("No top songs available yet.") }
                    ForEach(taste.topTracks.prefix(10)) { track in trackRow(track) }
                }
                if !demo.isActive { Section {
                    Text("Music data supplied by Spotify. Artist and song links open Spotify.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Spotify", destination: URL(string: "https://open.spotify.com")!)
                } }
            }
            if model.connected || model.taste != nil {
                Section {
                    Button("Disconnect Spotify and delete imported music", role: .destructive) {
                        confirmingDisconnect = true
                    }.disabled(model.busy)
                    Link("Manage access in Spotify", destination: URL(string: "https://www.spotify.com/account/apps/")!)
                }
            }
        }
        .navigationTitle("My music")
        .inTuneCornerMark()
        .task { model.findMissingGenres() }
        .sheet(item: $editingArtist) { artist in ArtistGenreEditor(artist: artist) }
        .confirmationDialog("Delete your imported music and saved Spotify connection from this device?", isPresented: $confirmingDisconnect) {
            Button("Disconnect and delete", role: .destructive) { model.disconnect() }
        } message: {
            Text("You can also revoke InTune's access on Spotify's Manage apps page.")
        }
    }

    private func spotifyURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              url.host == "open.spotify.com" else { return nil }
        return url
    }

    @ViewBuilder private func trackRow(_ track: SpotifyTrack) -> some View {
        if let url = spotifyURL(track.external_urls?["spotify"]) {
            Link(destination: url) { trackLabel(track) }
        } else { trackLabel(track) }
    }

    private func trackLabel(_ track: SpotifyTrack) -> some View {
        VStack(alignment: .leading) {
            Text(track.name).font(.headline)
            Text(track.artists.map(\.name).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
