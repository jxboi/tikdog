import Foundation
import CryptoKit
import Testing
@testable import TikDogCore

private struct MemorySession: SessionStorage {
    let session: AuthSession?
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession?) {}
}
private actor FixtureGate {
    static let shared = FixtureGate()
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func begin() { started = true; waiter?.resume(); waiter = nil }
    func waitForStart() async { if !started { await withCheckedContinuation { waiter = $0 } } }
}
private final class SupabaseFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        var status = 200
        var data = Data("null".utf8)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601
        do {
            if url.path == "/auth/v1/settings" {
                data = Data("{\"external\":{\"facebook\":true,\"apple\":false}}".utf8)
            } else if url.path == "/auth/v1/token" || url.path == "/auth/v1/verify" {
                if url.host == "facebook.test" {
                    var body = request.httpBody
                    if body == nil, let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
                        }
                        body = bytes
                    }
                    let payload = try JSONSerialization.jsonObject(with: body ?? Data()) as? [String: String]
                    let verifier = payload?["code_verifier"] ?? ""
                    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                    if url.query != "grant_type=pkce" || verifier.count != 43 || payload?["auth_code"] != challenge || request.value(forHTTPHeaderField: "Authorization") != nil || request.value(forHTTPHeaderField: "apikey") != "sb_publishable_test" { status = 400 }
                }
                let session = AuthSession(accessToken: "renewed-jwt", refreshToken: "renewed-refresh", expiresAt: Date.now.timeIntervalSince1970 + 3600, user: AuthUser(id: DemoContent.ownerId))
                data = try encoder.encode(session)
            } else if url.path.hasPrefix("/storage/v1/object/sign/") {
                let bucket = url.path.components(separatedBy: "/").last!
                let name = "\(DemoContent.ownerId.uuidString.lowercased())/\(DemoContent.dogIds[0].uuidString.lowercased()).\(bucket == "videos" ? "mp4" : "jpg")"
                data = try JSONSerialization.data(withJSONObject: [["path": name, "signedURL": "/object/sign/\(bucket)/\(name)?token=temporary"]])
                if url.host == "avatar.test" {
                    if request.value(forHTTPHeaderField: "Authorization") != "Bearer jwt" { status = 400 }
                } else if request.value(forHTTPHeaderField: "Authorization") != nil { status = 400 }
            } else if url.path == "/rest/v1/rpc/save_dog" {
                var dog = DemoContent.snapshot().dogs[0]
                dog.status = .pending
                dog.avatarPath = "storage://avatars/\(DemoContent.ownerId.uuidString.lowercased())/\(dog.id.uuidString.lowercased()).jpg"
                data = try encoder.encode(dog)
            } else if url.path == "/rest/v1/videos" {
                var video = DemoContent.snapshot().videos[0]
                let base = "\(DemoContent.ownerId.uuidString.lowercased())/\(DemoContent.dogIds[0].uuidString.lowercased())"
                video.status = .pending
                video.mediaPath = "storage://videos/\(base).mp4"
                video.thumbnailPath = "storage://thumbnails/\(base).jpg"
                data = try encoder.encode([video])
            } else if url.path == "/rest/v1/rpc/account_state" {
                data = Data("{\"terms_version\":null,\"is_suspended\":false,\"is_deleting\":false}".utf8)
            } else if url.path == "/auth/v1/logout" && url.host == "logout.test" {
                status = 401
            } else if url.path == "/rest/v1/rpc/dog_profile" {
                let snapshot = DemoContent.snapshot()
                data = try encoder.encode(ProfilePage(dog: snapshot.dogs[0], videos: snapshot.videos.filter { $0.dogId == snapshot.dogs[0].id }))
            } else if url.path == "/rest/v1/rpc/bootstrap" {
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                if ["guest.test", "private.test", "logout.test"].contains(url.host ?? "") {
                    // Publishable keys are API keys, not JWT bearer tokens.
                    if authorization != nil || request.value(forHTTPHeaderField: "apikey") != "sb_publishable_test" { status = 400 }
                } else if url.host != "race.test" && authorization != "Bearer renewed-jwt" { status = 401 }
                var snapshot = DemoContent.snapshot()
                if ["guest.test", "private.test", "logout.test"].contains(url.host ?? "") { snapshot.userId = nil }
                if url.host == "race.test" && authorization == nil { snapshot.userId = nil }
                if url.host == "private.test" {
                    let base = DemoContent.ownerId.uuidString.lowercased() + "/" + DemoContent.dogIds[0].uuidString.lowercased()
                    snapshot.dogs = [snapshot.dogs[0]]; snapshot.videos = [snapshot.videos[0]]
                    snapshot.dogs[0].avatarPath = "storage://avatars/\(base).jpg"
                    snapshot.videos[0].mediaPath = "storage://videos/\(base).mp4"
                    snapshot.videos[0].thumbnailPath = "storage://thumbnails/\(base).jpg"
                }
                data = try encoder.encode(snapshot)
            } else if url.host == "denied.test" {
                status = 403; data = Data("{\"message\":\"You can only upload for your own dog.\"}".utf8)
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            if url.host == "race.test" && url.path == "/rest/v1/rpc/bootstrap" && request.value(forHTTPHeaderField: "Authorization") != nil {
                let body = data
                Task { @Sendable [self, body, response] in
                    await FixtureGate.shared.begin()
                    try? await Task.sleep(for: .milliseconds(150))
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: body); self.client?.urlProtocolDidFinishLoading(self)
                }
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
struct TransportTests {
    private func repository(host: String, session: AuthSession? = nil) -> SupabaseRepository {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SupabaseFixtureProtocol.self]
        return SupabaseRepository(configuration: .init(url: URL(string: "https://\(host)")!, publishableKey: "sb_publishable_test"), sessionStorage: MemorySession(session: session), network: URLSession(configuration: config))
    }
    @Test func tokenLifetimeIsConvertedToPersistedExpiry() throws {
        let body = """
        {"access_token":"jwt","refresh_token":"refresh","expires_in":1800,"user":{"id":"11111111-1111-4111-8111-111111111111"}}
        """
        let before = Date.now.timeIntervalSince1970
        let session = try SupabaseRepository.decoder().decode(AuthSession.self, from: Data(body.utf8))
        #expect((session.expiresAt ?? 0) >= before + 1800)
        #expect((session.expiresAt ?? 0) < before + 1802)
        let restored = try JSONDecoder().decode(AuthSession.self, from: JSONEncoder().encode(session))
        #expect(restored.expiresAt == session.expiresAt)
    }
    @Test func guestsUsePublishableKeyWithoutPretendingItIsAJWT() async throws {
        let snapshot = try await repository(host: "guest.test").bootstrap()
        #expect(snapshot.userId == nil); #expect(snapshot.dogs.count == 4)
    }
    @Test func expiredSessionRefreshesBeforeFetchingData() async throws {
        let expired = AuthSession(accessToken: "expired", refreshToken: "refresh", expiresAt: 0, user: AuthUser(id: DemoContent.ownerId))
        let snapshot = try await repository(host: "member.test", session: expired).bootstrap()
        #expect(snapshot.userId == DemoContent.ownerId)
    }
    @Test func guestsCannotPerformAuthenticatedWrites() async throws {
        let repo = repository(host: "guest.test")
        await #expect(throws: TikDogError.signInRequired) { try await repo.setLike(videoId: UUID(), liked: true) }
    }
    @Test func serverAuthorizationErrorsReachTheCaller() async throws {
        let session = AuthSession(accessToken: "jwt", refreshToken: "refresh", user: AuthUser(id: DemoContent.ownerId))
        let repo = repository(host: "denied.test", session: session)
        await #expect(throws: TikDogError.server("You can only upload for your own dog.")) { try await repo.setLike(videoId: UUID(), liked: true) }
    }
    @Test func privateMediaUsesExpiringAccessWithoutChangingTheOwnedStoragePath() async throws {
        let snapshot = try await repository(host: "private.test").bootstrap()
        let video = try #require(snapshot.videos.first), dog = try #require(snapshot.dogs.first)
        #expect(video.mediaPath.hasPrefix("storage://videos/"))
        #expect(video.playbackPath?.hasPrefix("https://private.test/storage/v1/object/sign/videos/") == true)
        #expect(video.playbackPath?.hasSuffix("?token=temporary") == true)
        #expect(dog.avatarPath.hasPrefix("storage://avatars/"))
        #expect(dog.displayAvatarPath?.contains("/object/sign/avatars/") == true)
        #expect(video.displayThumbnailPath?.contains("/object/sign/thumbnails/") == true)
    }
    @Test func savedProfilePhotoIsImmediatelyDisplayable() async throws {
        let session = AuthSession(accessToken: "jwt", refreshToken: "refresh", user: AuthUser(id: DemoContent.ownerId))
        let dog = try await repository(host: "avatar.test", session: session).saveDog(DemoContent.snapshot().dogs[0])

        #expect(dog.moderationStatus == .pending)
        #expect(dog.avatarPath.hasPrefix("storage://avatars/"))
        #expect(dog.displayAvatarPath?.hasPrefix("https://avatar.test/storage/v1/object/sign/avatars/") == true)
    }
    @Test func recoveredUploadIncludesPlayableMediaAndThumbnail() async throws {
        let session = AuthSession(accessToken: "jwt", refreshToken: "refresh", user: AuthUser(id: DemoContent.ownerId))
        let repo = repository(host: "avatar.test", session: session)
        let draft = DemoContent.snapshot().videos[0]
        let unusedFile = URL.temporaryDirectory.appendingPathComponent("unused-\(UUID())")
        let video = try await repo.publish(draft, file: unusedFile, thumbnail: unusedFile) { _ in }

        #expect(video.id == draft.id)
        #expect(video.moderationStatus == .pending)
        #expect(video.playbackPath?.contains("/object/sign/videos/") == true)
        #expect(video.displayThumbnailPath?.contains("/object/sign/thumbnails/") == true)
    }
    @Test func signInOptionsMatchConfiguredProviders() async throws {
        let providers = try await repository(host: "guest.test").signInProviders()
        #expect(providers.facebook)
        #expect(!providers.apple)
    }

    @Test(arguments: ["", "#", "#_=_"])
    func facebookUsesPKCEAndExchangesTheBoundCodeBeforeSigningIn(fragment: String) async throws {
        let repo = repository(host: "facebook.test")
        let authorization = try await repo.beginFacebookSignIn()
        let parts = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https"); #expect(parts.host == "facebook.test"); #expect(parts.path == "/auth/v1/authorize")
        let items = parts.queryItems ?? []
        #expect(items.first(where: { $0.name == "provider" })?.value == "facebook")
        #expect(items.first(where: { $0.name == "redirect_to" })?.value == "tikdog://auth/callback")
        #expect(items.first(where: { $0.name == "code_challenge_method" })?.value == "s256")
        #expect(!items.contains(where: { $0.name == "code_verifier" }))
        let challenge = try #require(items.first(where: { $0.name == "code_challenge" })?.value)
        // The fixture accepts the exchange only when its verifier hashes to this challenge.
        try await repo.completeFacebookSignIn(authorization, callback: URL(string: "tikdog://auth/callback?code=\(challenge)\(fragment)")!)
        #expect(try await repo.bootstrap().userId == DemoContent.ownerId)
        await #expect(throws: TikDogError.self) { try await repo.completeFacebookSignIn(authorization, callback: URL(string: "tikdog://auth/callback?code=replay")!) }
    }
    @Test func facebookCallbacksRejectInjectedTokensAndUnexpectedURLs() async throws {
        let repo = repository(host: "guest.test")
        for text in ["https://attacker.test/auth/callback?code=x", "tikdog://other/callback?code=x", "tikdog://auth/recovery?code=x", "tikdog://auth/callback#access_token=injected", "tikdog://auth/callback?code=x#access_token=injected", "tikdog://auth/callback?code=x#_=_&access_token=injected", "tikdog://auth/callback?code=x#code=injected", "tikdog://auth/callback?code=x&code=y", "tikdog://auth/callback?code=", "tikdog://user@auth/callback?code=x", "tikdog://auth:42/callback?code=x", "tikdog://auth/callback?error=access_denied&code=x"] {
            let authorization = try await repo.beginFacebookSignIn()
            await #expect(throws: TikDogError.self) { try await repo.completeFacebookSignIn(authorization, callback: URL(string: text)!) }
        }
        #expect(try await repo.bootstrap().userId == nil)
    }
    @Test func facebookCancellationAndSignOutInvalidatePendingAuthorizations() async throws {
        let repo = repository(host: "guest.test")
        let canceled = try await repo.beginFacebookSignIn()
        await repo.cancelFacebookSignIn(canceled)
        await #expect(throws: TikDogError.self) { try await repo.completeFacebookSignIn(canceled, callback: URL(string: "tikdog://auth/callback?code=x")!) }
        let signedOut = try await repo.beginFacebookSignIn()
        try await repo.signOut()
        await #expect(throws: TikDogError.self) { try await repo.completeFacebookSignIn(signedOut, callback: URL(string: "tikdog://auth/callback?code=x")!) }
        #expect(try await repo.bootstrap().userId == nil)
    }
    @Test func startingAnotherFacebookAttemptSupersedesTheOldVerifier() async throws {
        let repo = repository(host: "facebook.test")
        let old = try await repo.beginFacebookSignIn(), current = try await repo.beginFacebookSignIn()
        #expect(old.id != current.id); #expect(old.url != current.url)
        await #expect(throws: TikDogError.self) { try await repo.completeFacebookSignIn(old, callback: URL(string: "tikdog://auth/callback?code=x")!) }
        await repo.cancelFacebookSignIn(old)
        let parts = try #require(URLComponents(url: current.url, resolvingAgainstBaseURL: false))
        let challenge = try #require(parts.queryItems?.first(where: { $0.name == "code_challenge" })?.value)
        try await repo.completeFacebookSignIn(current, callback: URL(string: "tikdog://auth/callback?code=\(challenge)")!)
        #expect(try await repo.bootstrap().userId == DemoContent.ownerId)
    }
    @Test func failedRemoteLogoutStillClearsTheLocalSession() async throws {
        let session = AuthSession(accessToken: "jwt", refreshToken: "refresh", user: AuthUser(id: DemoContent.ownerId))
        let repo = repository(host: "logout.test", session: session)
        try await repo.signOut()
        #expect(try await repo.bootstrap().userId == nil)
    }

    @Test func inFlightMemberResponseIsDiscardedAfterSignOut() async throws {
        let session = AuthSession(accessToken: "renewed-jwt", refreshToken: "refresh", user: AuthUser(id: DemoContent.ownerId))
        let repo = repository(host: "race.test", session: session)
        let inFlight = Task { try await repo.bootstrap() }
        await FixtureGate.shared.waitForStart()
        try await repo.signOut()
        await #expect(throws: CancellationError.self) { try await inFlight.value }
        #expect(try await repo.bootstrap().userId == nil)
    }
    @Test func clientKeysNeverAcceptAServerCredential() {
        #expect(SupabaseConfiguration.isPublishableKey("sb_publishable_fixture"))
        #expect(!SupabaseConfiguration.isPublishableKey("sb_secret_do-not-embed"))
        let payload = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString()
        #expect(!SupabaseConfiguration.isPublishableKey("header.\(payload).signature"))
        #expect(!SupabaseConfiguration.isPublishableKey("YOUR_KEY"))
    }

}
