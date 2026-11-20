import Foundation

@MainActor
final class FirebaseCommunityClient {
    private struct Session: Codable {
        let projectID: String
        let uid: String
        let idToken: String
        let refreshToken: String
        let expiresAt: Date
    }
    private struct AuthResult: Decodable {
        let localId: String
        let idToken: String
        let refreshToken: String
        let expiresIn: String
    }
    private struct RefreshResult: Decodable {
        let user_id: String
        let id_token: String
        let refresh_token: String
        let expires_in: String
    }
    let config: FirebaseCommunityConfig
    private let http: URLSession
    private var session: Session?
    var uid: String? { session?.uid }
    private var resourceRoot: String { "projects/\(config.projectID)/databases/(default)/documents" }
    private var rootURL: String { "https://firestore.googleapis.com/v1/" + resourceRoot }

    init(config: FirebaseCommunityConfig? = nil, http: URLSession = .shared) {
        let config = config ?? FirebaseCommunityConfig.load()
        self.config = config
        self.http = http
        if let saved = try? MusicVault.read("community-auth", as: Session.self), saved.projectID == config.projectID {
            session = saved
        }
    }

    func signIn(email: String, password: String, create: Bool) async throws {
        guard config.configured else { throw CommunityError(message: "Shared profiles are not configured. Add your team's Firebase project ID and Web API key to CommunityConfig.json first.") }
        let endpoint = create ? "signUp" : "signInWithPassword"
        var url = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/accounts:" + endpoint)!
        url.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        let data = try await request(url: url.url!, method: "POST", object: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "returnSecureToken": true
        ])
        let result = try JSONDecoder().decode(AuthResult.self, from: data)
        try save(Session(projectID: config.projectID, uid: result.localId, idToken: result.idToken,
                         refreshToken: result.refreshToken, expiresAt: Date().addingTimeInterval(Double(result.expiresIn) ?? 3600)))
    }

    func signOut() throws {
        try MusicVault.delete("community-auth")
        session = nil
    }

    private func save(_ next: Session) throws {
        try MusicVault.write(next, key: "community-auth")
        session = next
    }
    private func token() async throws -> String {
        guard let saved = session else { throw CommunityError(message: "Sign in to your InTune account first.") }
        if saved.expiresAt.timeIntervalSinceNow > 60 { return saved.idToken }
        var url = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
        url.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"),
                           URLQueryItem(name: "refresh_token", value: saved.refreshToken)]
        var req = URLRequest(url: url.url!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await http.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CommunityError(message: "Your InTune session needs a new sign-in. Sign out, then sign in again.")
        }
        let result = try JSONDecoder().decode(RefreshResult.self, from: data)
        guard result.user_id == saved.uid else { throw CommunityError(message: "Your account session could not be verified. Sign in again.") }
        try save(Session(projectID: config.projectID, uid: result.user_id, idToken: result.id_token,
                         refreshToken: result.refresh_token, expiresAt: Date().addingTimeInterval(Double(result.expires_in) ?? 3600)))
        return result.id_token
    }

    func get(_ path: String) async throws -> FirestoreDocument? {
        let data = try await firestore(url: rootURL + "/" + path, method: "GET", allowMissing: true)
        return data.isEmpty ? nil : try JSONDecoder().decode(FirestoreDocument.self, from: data)
    }
    func list(_ path: String, orderBy: String? = nil) async throws -> [FirestoreDocument] {
        struct Result: Decodable { let documents: [FirestoreDocument]?; let nextPageToken: String? }
        var documents: [FirestoreDocument] = []
        var page: String?
        repeat {
            var url = URLComponents(string: rootURL + "/" + path)!
            url.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
            if let orderBy { url.queryItems?.append(URLQueryItem(name: "orderBy", value: orderBy)) }
            if let page { url.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
            let data = try await firestore(url: url.url!.absoluteString, method: "GET")
            let result = try JSONDecoder().decode(Result.self, from: data)
            documents += result.documents ?? []
            page = result.nextPageToken
        } while page != nil
        return documents
    }
    func query(collection: String, field: String, operation: String, value: FirestoreValue) async throws -> [FirestoreDocument] {
        struct Row: Decodable { let document: FirestoreDocument? }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        let object: [String: Any] = ["structuredQuery": ["from": [["collectionId": collection]],
            "where": ["fieldFilter": ["field": ["fieldPath": field], "op": operation, "value": encoded]], "limit": 100]]
        let data = try await firestore(url: rootURL + ":runQuery", method: "POST", object: object)
        return try JSONDecoder().decode([Row].self, from: data).compactMap(\.document)
    }
    func put(_ path: String, fields: [String: FirestoreValue], timestamp: String? = nil, createOnly: Bool = false) async throws {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fields))
        var write: [String: Any] = ["update": ["name": resourceRoot + "/" + path, "fields": encoded]]
        if let timestamp { write["updateTransforms"] = [["fieldPath": timestamp, "setToServerValue": "REQUEST_TIME"]] }
        if createOnly { write["currentDocument"] = ["exists": false] }
        _ = try await firestore(url: rootURL + ":commit", method: "POST", object: ["writes": [write]])
    }
    private func firestore(url: String, method: String, object: [String: Any]? = nil, allowMissing: Bool = false) async throws -> Data {
        let authorization = try await token()
        return try await request(url: URL(string: url)!, method: method, object: object,
                                 bearer: authorization, allowMissing: allowMissing)
    }
    private func request(url: URL, method: String, object: [String: Any]? = nil,
                         bearer: String? = nil, allowMissing: Bool = false) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        if let object {
            req.httpBody = try JSONSerialization.data(withJSONObject: object)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await http.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        if status == 404 && allowMissing { return Data() }
        switch status {
        case 400:
            if url.host == "identitytoolkit.googleapis.com" {
                throw CommunityError(message: "Could not sign in or create the account. Check your email/password, password requirements, and that Email/Password sign-in is enabled in Firebase.")
            }
            throw CommunityError(message: "Firebase rejected this request. Check the project's database and configuration.")
        case 401: throw CommunityError(message: "Your InTune session expired. Sign out and sign in again.")
        case 403: throw CommunityError(message: "Firebase denied access. Make sure the supplied Firestore rules are deployed to this project.")
        case 404: throw CommunityError(message: "The shared database was not found. Create Firestore in your team's Firebase project.")
        case 429: throw CommunityError(message: "Too many requests. Wait a moment and try again.")
        default: throw CommunityError(message: "Could not reach the shared service (HTTP \(status)). Try again.")
        }
    }
}
