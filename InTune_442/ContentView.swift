import SwiftUI

struct ContentView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        HomeView()
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
