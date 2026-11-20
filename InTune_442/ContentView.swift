import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    @State private var profile = LocalProfile.load()

    var body: some View {
        Group {
            if let profile {
                HomeView()
                    .environment(\.localProfile, profile)
                    .environment(\.saveLocalProfile, save)
            } else {
                NavigationStack {
                    ProfileForm(profile: nil, save: save)
                }
            }
        }
            .task(id: profile?.id) {
                if profile != nil { MusicProfileModel.shared.findMissingGenres() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard profile != nil else { return }
                if phase == .active { MusicProfileModel.shared.findMissingGenres() }
                else { MusicProfileModel.shared.pauseGenreLookup() }
            }
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
    private func save(_ updated: LocalProfile) throws {
        try updated.persist()
        profile = updated
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
