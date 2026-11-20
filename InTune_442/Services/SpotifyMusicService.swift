import AuthenticationServices
import CryptoKit
import Security
import UIKit

struct SpotifyMusicError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Both tokens and the device-only music cache use Keychain, never UserDefaults.
enum MusicVault {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "InTune") + ".spotify-music",
         kSecAttrAccount as String: key]
    }
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SpotifyMusicError(message: "Could not read your saved Spotify connection (\(status)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func write<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SpotifyMusicError(message: "Could not save your Spotify connection (\(status)).")
        }
    }
    static func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpotifyMusicError(message: "Could not remove saved Spotify data (\(status)).")
        }
    }
}

@MainActor
final class SpotifyMusicService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }
    private var webSession: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private let http: URLSession
    private let clientID: String
    private let callback: URL

    init(clientID: String? = nil, callback: URL? = nil,
         http: URLSession = .shared) {
        self.clientID = clientID ?? spotifyClientId
        self.callback = callback ?? redirectUri
        self.http = http
    }

    var isConnected: Bool { (try? MusicVault.read("tokens", as: Tokens.self)) != nil }

    func connect() async throws {
        guard webSession == nil else { throw SpotifyMusicError(message: "Spotify login is already open.") }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw SpotifyMusicError(message: "Open your profile to connect Spotify.")
        }
        anchor = window
        defer { webSession = nil; anchor = nil }
        let verifier = try randomString()
        let state = try randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: callback.absoluteString),
            URLQueryItem(name: "scope", value: "user-top-read"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        let returned: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: callback.scheme) { returned, error in
                if let error { continuation.resume(throwing: error) }
                else if let returned { continuation.resume(returning: returned) }
                else { continuation.resume(throwing: SpotifyMusicError(message: "Spotify did not return a login result.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyMusicError(message: "Unable to open Spotify login."))
            }
        }
        let code = try SpotifyLoginCallback.authorizationCode(
            from: returned, expected: callback, state: state
        )
        let result = try await exchange([
            "client_id": clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": callback.absoluteString, "code_verifier": verifier
        ])
        guard let refresh = result.refresh_token else {
            throw SpotifyMusicError(message: "Spotify did not return a refresh token. Please reconnect.")
        }
        // A newly authorized account must not inherit another account's cached profile or chat.
        try LocalTestProfiles.shared.clear()
        try MusicVault.delete("taste")
        try MusicVault.delete("genre-corrections")
        try save(result, refreshToken: refresh)
    }

    func importTaste(previousShowcase: String?) async throws -> MusicTaste {
        let token = try await validToken()
        // Sequential requests avoid refresh races and keep error handling predictable.
        let artists: SpotifyPage<SpotifyArtist> = try await get("artists", token: token)
        let tracks: SpotifyPage<SpotifyTrack> = try await get("tracks", token: token)
        let enrichedArtists = ArtistGenreService.shared.cachedEnrichment(artists.items)
        return MusicTasteBuilder.build(artists: enrichedArtists, tracks: tracks.items,
                                      previousShowcase: previousShowcase)
    }

    func disconnect() throws {
        try MusicVault.delete("tokens")
        try MusicVault.delete("taste")
        try MusicVault.delete("genre-corrections")
        try ArtistGenreService.shared.clearCache()
        try LocalTestProfiles.shared.clear()
        // Remove the old demo's insecure token cache as part of migration.
        UserDefaults.standard.removeObject(forKey: "access-token-key")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    private func validToken() async throws -> String {
        guard let saved = try MusicVault.read("tokens", as: Tokens.self) else {
            throw SpotifyMusicError(message: "Connect your Spotify account first.")
        }
        if saved.expiresAt.timeIntervalSinceNow > 60 { return saved.accessToken }
        let response = try await exchange(["client_id": clientID, "grant_type": "refresh_token",
                                           "refresh_token": saved.refreshToken])
        try save(response, refreshToken: response.refresh_token ?? saved.refreshToken)
        return response.access_token
    }

    private func save(_ response: TokenResponse, refreshToken: String) throws {
        try MusicVault.write(Tokens(accessToken: response.access_token, refreshToken: refreshToken,
                                   expiresAt: Date().addingTimeInterval(response.expires_in)), key: "tokens")
    }

    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" +
            $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200 else {
            if status == 400 || status == 401 {
                try MusicVault.delete("tokens")
            }
            throw SpotifyMusicError(message: "Spotify could not authorize this connection. Reconnect and check the app's client ID and registered redirect URI.")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func get<T: Decodable>(_ type: String, token: String) async throws -> T {
        let limit = type == "artists" ? MusicTasteBuilder.artistLimit : 50
        let url = URL(string: "https://api.spotify.com/v1/me/top/\(type)?time_range=medium_term&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch response.statusCode {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 401:
            try MusicVault.delete("tokens")
            throw SpotifyMusicError(message: "Your Spotify connection expired or was revoked. Please reconnect.")
        case 403:
            throw SpotifyMusicError(message: "Spotify denied access. Ask the app owner to add your account in the Spotify developer dashboard and confirm user-top-read access.")
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After") ?? "a few"
            throw SpotifyMusicError(message: "Spotify is limiting requests. Try again in \(delay) seconds.")
        default:
            throw SpotifyMusicError(message: "Spotify could not load your music (HTTP \(response.statusCode)). Try again later.")
        }
    }

    private func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SpotifyMusicError(message: "Unable to securely start Spotify login. Try again.")
        }
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
