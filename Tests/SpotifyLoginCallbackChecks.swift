import Foundation

@main struct SpotifyLoginCallbackChecks {
    static func main() throws {
        let expected = URL(string: "intune442://spotify-login-callback")!
        let state = "test-state_123-ABC"
        let normal = URL(string: "intune442://spotify-login-callback?code=test-code&state=\(state)")!
        let root = URL(string: "intune442://spotify-login-callback/?code=test-code&state=\(state)")!
        // Reproduce the strict comparison that rejected an otherwise matching root callback.
        precondition(root.path != expected.path)
        for url in [normal, root] {
            let code = try SpotifyLoginCallback.authorizationCode(from: url, expected: expected, state: state)
            precondition(code == "test-code")
        }
        let encoded = URL(string: "intune442://spotify-login-callback?code=a%2Bb%2Fc%3D&state=\(state)")!
        let decoded = try SpotifyLoginCallback.authorizationCode(from: encoded, expected: expected, state: state)
        precondition(decoded == "a+b/c=", "Authorization codes must retain their decoded value")
        func reject(_ suffix: String, _ reason: SpotifyLoginCallback.Failure,
                    base: String = "intune442://spotify-login-callback") {
            do {
                _ = try SpotifyLoginCallback.authorizationCode(from: URL(string: base + suffix)!, expected: expected, state: state)
                preconditionFailure("Unexpectedly accepted invalid callback")
            } catch {
                precondition(error as? SpotifyLoginCallback.Failure == reason, "Wrong failure: \(error)")
                precondition(!error.localizedDescription.contains("test-state"), "Do not display sensitive callback values")
                precondition(!error.localizedDescription.contains("test-code"))
            }
        }
        reject("?code=test-code", .missingState)
        reject("?code=test-code&state=wrong", .wrongState)
        reject("?code=test-code&state=", .missingState)
        reject("?code=test-code&state=\(state)&state=\(state)", .duplicateParameter)
        reject("?code=one&code=two&state=\(state)", .duplicateParameter)
        reject("?state=\(state)", .missingCode)
        reject("?code=&state=\(state)", .missingCode)
        reject("?error=access_denied&state=\(state)", .denied)
        reject("?error=server_error&state=\(state)", .providerError)
        reject("?error=access_denied&code=test-code&state=\(state)", .duplicateParameter)
        reject("?code=test-code&state=\(state)#access_token=never-print", .fragment)
        reject("/wrong?code=test-code&state=\(state)", .path)
        reject("?code=test-code&state=\(state)", .address, base: "otherapp://spotify-login-callback")
        reject("?code=test-code&state=\(state)", .address, base: "intune442://other-host")
        reject("?code=test-code&state=\(state)", .address, base: "intune442://spotify-login-callback:123")
        reject("?code=test-code&state=\(state)", .address, base: "intune442://user@spotify-login-callback")
        print("Callback checks passed: exact/root redirects, code decoding, state validation, duplicates, rejection, safe errors.")
    }
}
