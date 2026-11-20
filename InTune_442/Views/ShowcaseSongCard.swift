import SwiftUI

struct SongAlbumArtwork: View {
    let song: ShowcaseSong
    @State private var resolvedArtworkURL: URL?

    private var artworkURL: URL? { song.artworkURL ?? resolvedArtworkURL }

    var body: some View {
        ZStack {
            MusicArtwork(title: song.title)
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        MusicArtwork(title: song.title)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .clipped()
            }
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Album cover for \(song.title) by \(song.artist)")
        .task(id: song.id) { await findArtworkIfNeeded() }
    }

    @MainActor
    private func findArtworkIfNeeded() async {
        guard song.artworkURL == nil else { return }
        resolvedArtworkURL = nil
        do {
            let metadata = try await SongPreviewService.shared.lookup(song)
            guard !Task.isCancelled else { return }
            resolvedArtworkURL = metadata?.artworkURL
        } catch {
            // The decorative artwork remains as the fallback when no catalog match exists.
        }
    }
}

struct ShowcaseSongCard: View {
    let song: ShowcaseSong
    var compact = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var playback = SongPreviewPlayer.shared
    @State private var metadata: SongPreviewMetadata?
    @State private var loading = false
    @State private var lookupFailed = false
    @State private var lookupID: UUID?
    private var playing: Bool { playback.songID == song.id && playback.isPlaying }
    private var buffering: Bool { playback.songID == song.id && playback.isBuffering }

    var body: some View {
        Group {
            if compact { compactContent } else { fullContent }
        }
        .task(id: song.id) { await load() }
        .onChange(of: song.id) { oldID, _ in playback.stop(ifPlaying: oldID) }
        .onDisappear { playback.stop(ifPlaying: song.id); lookupID = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop(ifPlaying: song.id) } }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("SHOWCASE SONG", systemImage: "music.note")
                .font(.caption2.bold()).foregroundStyle(.secondary)
            Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                if loading {
                    ProgressView("Finding preview…").font(.caption2)
                } else if let url = metadata?.audioURL {
                    Button { playback.toggle(songID: song.id, url: url) } label: {
                        Label(buffering ? "Cancel" : (playing ? "Pause" : "Play"),
                              systemImage: buffering ? "xmark" : (playing ? "pause.fill" : "play.fill"))
                    }
                    .buttonStyle(.borderedProminent).tint(InTuneBrand.pink).controlSize(.small)
                } else if lookupFailed {
                    Button("Retry") { Task { await load() } }.font(.caption2)
                } else {
                    Text("No preview available").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Link(destination: song.spotifyDestination) {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.bordered).tint(InTuneBrand.pink).controlSize(.small)
                .accessibilityLabel(song.directSpotifyURL == nil ? "Find on Spotify" : "View on Spotify")
            }
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SHOWCASE SONG", systemImage: "music.note").font(.caption.bold()).foregroundStyle(.secondary)
            VinylSleeveView(artworkURL: song.artworkURL ?? metadata?.artworkURL,
                            isExpanded: playing,
                            isPlaying: playing)
                .id(song.id)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.headline)
                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
            }
            if loading {
                ProgressView("Finding song preview…").font(.caption)
            } else if let url = metadata?.audioURL {
                Button {
                    playback.toggle(songID: song.id, url: url)
                } label: {
                    Label(buffering ? "Cancel loading preview" : (playing ? "Pause preview" : "Play preview"),
                          systemImage: buffering ? "xmark" : (playing ? "pause.fill" : "play.fill"))
                }.buttonStyle(.borderedProminent).tint(InTuneBrand.pink)
            } else {
                Text(lookupFailed ? "Preview couldn't load. Check your connection and try again." : "No matching preview is available in your region.")
                    .font(.caption).foregroundStyle(.secondary)
                if lookupFailed { Button("Retry preview lookup") { Task { await load() } }.font(.caption) }
            }
            if playback.failedSongID == song.id {
                Text("This preview couldn't play. Try again or open the full song.").font(.caption).foregroundStyle(.secondary)
            }
            Link(destination: song.spotifyDestination) {
                Label(song.directSpotifyURL == nil ? "Find on Spotify" : "View on Spotify", systemImage: "arrow.up.right")
            }
            .buttonStyle(.bordered)
            .tint(InTuneBrand.pink)
            if let storeURL = metadata?.storeURL {
                Link("Preview provided courtesy of iTunes", destination: storeURL)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        let requestID = UUID()
        lookupID = requestID
        metadata = nil; loading = true; lookupFailed = false
        do {
            let result = try await SongPreviewService.shared.lookup(song)
            guard !Task.isCancelled, lookupID == requestID else { return }
            metadata = result; loading = false
        } catch {
            guard !Task.isCancelled, lookupID == requestID else { return }
            loading = false; lookupFailed = true
        }
    }
}
