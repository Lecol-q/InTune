import SwiftUI
import UIKit

// Compatibility wrapper for the repository's older UIKit scene entry point.
// Spotify profile import now uses the Web API with PKCE rather than App Remote playback.
class ViewController: UIHostingController<Profile> {
    init() { super.init(rootView: Profile()) }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: Profile())
    }
}
