import Foundation
import AVFoundation
import Combine

@MainActor
final class SongPreviewPlayer: ObservableObject {
    static let shared = SongPreviewPlayer()
    @Published private(set) var songID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var failedSongID: String?
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var finishedObserver: NSObjectProtocol?

    func toggle(songID: String, url: URL) {
        if self.songID == songID, let player {
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { failedSongID = songID; return }
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: 30, preferredTimescale: 600)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.songID = songID
        failedSongID = nil
        isPlaying = true
        statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.stop()
                    self.failedSongID = songID
                }
            }
        }
        finishedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.player?.currentItem === item else { return }
                    self.stop()
                }
            }
        player.play()
    }
    func stop(ifPlaying id: String? = nil) {
        if let id, songID != id { return }
        player?.pause()
        player = nil
        statusObservation = nil
        if let finishedObserver { NotificationCenter.default.removeObserver(finishedObserver) }
        finishedObserver = nil
        songID = nil
        isPlaying = false
        failedSongID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
