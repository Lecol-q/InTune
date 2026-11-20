import Foundation

@main struct DemoSessionChecks {
    @MainActor static func main() throws {
        let suite = "intune.demo.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let demo = DemoSession(defaults: defaults)
        precondition(demo.enabled && demo.remaining.count == 4)
        let first = demo.remaining[0]
        demo.decide(first, like: true)
        demo.decide(first, like: false)
        precondition(demo.liked.count == 1 && demo.remaining.count == 3 && demo.passedIDs.isEmpty)
        demo.decide(demo.remaining[0], like: false)
        let id = DemoMusic.tracks[1].id
        demo.selectShowcase(id)
        let restored = DemoSession(defaults: defaults)
        precondition(restored.remaining.count == 2 && restored.liked.count == 1)
        precondition(restored.taste.showcaseTrack?.id == id)
        precondition(!restored.sharedGenres(with: first).isEmpty)
        for person in restored.remaining { restored.decide(person, like: false) }
        precondition(restored.remaining.isEmpty)
        restored.resetCards()
        precondition(restored.remaining.count == 4 && restored.liked.isEmpty)
        precondition(restored.taste.showcaseTrack?.id == id)
        restored.enabled = false
        precondition(!DemoSession(defaults: defaults).enabled)
        restored.setSpotifyConnected(true)
        precondition(!restored.enabled && !restored.isActive)
        restored.enabled = true
        precondition(!restored.isActive, "A connected Spotify account must never show demo content")
        restored.setSpotifyConnected(false)
        restored.enabled = false
        precondition(!restored.isActive, "Disabling demo hides it without a Spotify account")
        let again = DemoSession(defaults: defaults)
        precondition(!again.isActive, "Disabled demo stays disabled after relaunch")
        restored.enabled = true
        restored.setCommunityConnected(true)
        precondition(!restored.enabled && !restored.isActive)
        restored.enabled = true
        precondition(!restored.isActive, "An InTune account also suppresses demo content")
        restored.setCommunityConnected(false)
        print("Demo checks passed: default mode, likes/passes, duplicate prevention, persistence, showcase, shared genres, exhaustion, reset, mode toggle.")
    }
}
