import SwiftUI

struct ShowcaseSongCard: View {
    let song: ShowcaseSong
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var playback = SongPreviewPlayer.shared
    @State private var metadata: SongPreviewMetadata?
    @State private var loading = false
    @State private var lookupFailed = false
    @State private var lookupID: UUID?
    private var playing: Bool { playback.songID == song.id && playback.isPlaying }
    private var buffering: Bool { playback.songID == song.id && playback.isBuffering }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SHOWCASE SONG", systemImage: "music.note").font(.caption.bold()).foregroundStyle(.secondary)
            VinylSleeveView(artworkURL: metadata?.artworkURL,
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
        .task(id: song.id) { await load() }
        .onChange(of: song.id) { oldID, _ in playback.stop(ifPlaying: oldID) }
        .onDisappear { playback.stop(ifPlaying: song.id); lookupID = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop(ifPlaying: song.id) } }
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
