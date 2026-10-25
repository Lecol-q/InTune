import Foundation

// Public OAuth client identifier; a mobile app must never contain a client secret.
// Register this exact redirect URI in the Spotify developer dashboard.
let redirectUri = URL(string: "intune442://spotify-login-callback")!
let spotifyClientId = "e044442ca1b148f69898149f2086024a"
