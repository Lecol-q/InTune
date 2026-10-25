import Foundation

/// Callback validation is kept independent of the browser so security checks can be tested.
enum SpotifyLoginCallback {
    enum Failure: Error, LocalizedError, Equatable {
        case address, path, fragment, duplicateParameter, missingState, wrongState
        case denied, providerError, missingCode

        var errorDescription: String? {
            switch self {
            case .address:
                "Spotify returned an unexpected login address [callback_address]. Check the registered redirect URI in the Spotify dashboard."
            case .path:
                "Spotify returned an unexpected login path [callback_path]. Check the registered redirect URI in the Spotify dashboard."
            case .fragment:
                "Spotify returned an unsupported login response [callback_fragment]. Please start a new connection."
            case .duplicateParameter:
                "Spotify returned an ambiguous login response [callback_parameters]. Please start a new connection."
            case .missingState:
                "Spotify's response was missing the login verification value [state_missing]. Please start a new connection."
            case .wrongState:
                "Spotify's response did not match this login attempt [state_mismatch]. Please start a new connection."
            case .denied:
                "Spotify access was not granted. You can connect again anytime."
            case .providerError:
                "Spotify reported an authorization error [provider_error]. Please reconnect or check the app's Spotify configuration."
            case .missingCode:
                "Spotify did not return an authorization code [code_missing]. Please start a new connection."
            }
        }
    }

    static func authorizationCode(from returned: URL, expected: URL, state: String) throws -> String {
        guard let actual = URLComponents(url: returned, resolvingAgainstBaseURL: false),
              let target = URLComponents(url: expected, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == target.scheme?.lowercased(),
              actual.host?.lowercased() == target.host?.lowercased(),
              actual.port == target.port, actual.user == nil, actual.password == nil else {
            throw Failure.address
        }
        // A host-only redirect may be returned with an explicit root slash.
        // Only the empty/root path pair is equivalent; other paths remain exact.
        func rootNormalized(_ path: String) -> String { path.isEmpty ? "/" : path }
        guard rootNormalized(actual.percentEncodedPath) == rootNormalized(target.percentEncodedPath) else {
            throw Failure.path
        }
        guard actual.fragment == nil else { throw Failure.fragment }
        let items = actual.queryItems ?? []
        for name in ["state", "code", "error"] {
            guard items.filter({ $0.name == name }).count <= 1 else { throw Failure.duplicateParameter }
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let receivedState = value("state"), !receivedState.isEmpty else { throw Failure.missingState }
        guard !state.isEmpty, receivedState == state else { throw Failure.wrongState }
        if let error = value("error") {
            guard value("code") == nil else { throw Failure.duplicateParameter }
            throw error == "access_denied" ? Failure.denied : Failure.providerError
        }
        guard let code = value("code"), !code.isEmpty else { throw Failure.missingCode }
        return code
    }
}
