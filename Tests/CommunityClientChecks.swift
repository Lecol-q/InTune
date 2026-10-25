import Foundation

enum MusicVault {
    static var data: [String: Data] = [:]
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        guard let bytes = data[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
    static func write<T: Encodable>(_ value: T, key: String) throws { data[key] = try JSONEncoder().encode(value) }
    static func delete(_ key: String) throws { data[key] = nil }
}
final class CommunityMock: URLProtocol {
    static var requests: [URLRequest] = []
    static var commit: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private func bodyData() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
    override func startLoading() {
        Self.requests.append(request)
        let host = request.url!.host!
        let body: String
        let status: Int
        if host == "identitytoolkit.googleapis.com" {
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            let object = try! JSONSerialization.jsonObject(with: bodyData()) as! [String: Any]
            precondition(object["email"] as? String == "alice@example.test")
            body = #"{"localId":"alice","idToken":"test-id-token","refreshToken":"test-refresh-token","expiresIn":"3600"}"#
            status = 200
        } else {
            precondition(host == "firestore.googleapis.com")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-id-token")
            if request.url!.path.hasSuffix(":commit") {
                Self.commit = try! JSONSerialization.jsonObject(with: bodyData()) as? [String: Any]
                body = "{}"; status = 200
            } else if request.url!.path.hasSuffix(":runQuery") {
                body = #"[{"readTime":"2026-10-25T00:00:00Z"}]"#; status = 200
            } else { body = "{}"; status = 404 }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct CommunityClientChecks {
    @MainActor static func main() async throws {
        let config = FirebaseCommunityConfig(projectID: "demo-intune", apiKey: "public-fixture-key")
        precondition(config.configured)
        precondition(!FirebaseCommunityConfig(projectID: "bad/project", apiKey: "x").configured)
        precondition(CommunityMatch.identifier("bob", "alice") == CommunityMatch.identifier("alice", "bob"))
        let profile = CommunityProfile(id: "alice", name: "Alice", age: 21, bio: "Hello", artists: ["Artist"],
            genres: ["jazz rap"], showcase: "Song", active: true)
        let fields = profile.fields
        precondition(Set(fields.keys) == Set(["ownerID","name","age","bio","artists","genres","showcase","active"]))
        let decoded = try JSONDecoder().decode([String: FirestoreValue].self, from: JSONEncoder().encode(fields))
        let document = FirestoreDocument(name: "projects/demo-intune/databases/(default)/documents/profiles/alice", fields: decoded)
        precondition(CommunityProfile(document: document) == profile)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [CommunityMock.self]
        let client = FirebaseCommunityClient(config: config, http: URLSession(configuration: sessionConfig))
        try await client.signIn(email: "alice@example.test", password: "not-a-real-password", create: false)
        precondition(client.uid == "alice")
        try await client.put("profiles/alice", fields: fields)
        let writes = CommunityMock.commit!["writes"] as! [[String: Any]]
        let update = writes[0]["update"] as! [String: Any]
        precondition((update["name"] as! String).hasSuffix("/profiles/alice"))
        let published = update["fields"] as! [String: Any]
        precondition(published["password"] == nil && published["idToken"] == nil && published["email"] == nil)
        try await client.put("matches/alice__bob/messages/id", fields: ["senderID": .string("alice"), "text": .string("hello")],
                             timestamp: "sentAt", createOnly: true)
        let messageWrite = (CommunityMock.commit!["writes"] as! [[String: Any]])[0]
        precondition((messageWrite["currentDocument"] as! [String: Bool])["exists"] == false)
        precondition((messageWrite["updateTransforms"] as! [[String: String]])[0]["setToServerValue"] == "REQUEST_TIME")
        let missing = try await client.get("profiles/missing")
        precondition(missing == nil)
        let empty = try await client.query(collection: "profiles", field: "active", operation: "EQUAL", value: .bool(true))
        precondition(empty.isEmpty)
        try client.signOut()
        precondition(client.uid == nil && MusicVault.data["community-auth"] == nil)
        let count = CommunityMock.requests.count
        do {
            try await client.put("profiles/alice", fields: fields)
            preconditionFailure("Unauthenticated write should be blocked")
        } catch {}
        precondition(CommunityMock.requests.count == count)
        print("Community client checks passed: config, identity, profile allowlist, Firestore codecs, auth headers, timestamps, empty data, sign-out.")
    }
}
