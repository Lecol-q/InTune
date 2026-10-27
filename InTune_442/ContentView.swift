import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        HomeView()
            .task { MusicProfileModel.shared.findMissingGenres() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { MusicProfileModel.shared.findMissingGenres() }
                else { MusicProfileModel.shared.pauseGenreLookup() }
            }
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
