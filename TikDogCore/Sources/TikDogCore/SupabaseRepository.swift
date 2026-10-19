import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SupabaseConfiguration: Sendable {
    public let url: URL
    public let publishableKey: String
    public init(url: URL, publishableKey: String) { self.url = url; self.publishableKey = publishableKey }
    public static func isPublishableKey(_ value: String) -> Bool {
        if value.hasPrefix("sb_publishable_") { return value.count > 15 }
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { return false }
        var body = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let data = Data(base64Encoded: body), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return claims["role"] as? String == "anon"
    }

}
public protocol SessionStorage: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession?) throws
}

public struct FacebookAuthorization: Sendable {
    public let id: UUID
    public let url: URL
}

public struct SignInProviders: Equatable, Sendable {
    public let facebook: Bool
    public let apple: Bool
}

public actor SupabaseRepository: TikDogRepository {
    public nonisolated let isDemo = false
    private let config: SupabaseConfiguration
    private let storage: any SessionStorage
    private var session: AuthSession?
    private var sessionGeneration = UUID()
    private var refreshTask: Task<AuthSession, Error>?
    private struct PendingFacebookAuthorization {
        let id: UUID
        let verifier: String
        let sessionGeneration: UUID
    }
    private var pendingFacebook: PendingFacebookAuthorization?
    private var facebookRequestID: UUID?
    private let network: URLSession

    public init(configuration: SupabaseConfiguration, sessionStorage: any SessionStorage, network: URLSession = .shared) {
        config = configuration; storage = sessionStorage; session = try? sessionStorage.load(); self.network = network
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: try value.singleValueContainer(), debugDescription: "Invalid date")
        }
        return decoder
    }
    private func encoder() -> JSONEncoder { let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.dateEncodingStrategy = .iso8601; return e }
    private func token() async throws -> String {
        guard let session else { return config.publishableKey }
        if let expiry = session.expiresAt, expiry < Date.now.timeIntervalSince1970 + 60 {
            let generation = sessionGeneration
            let task: Task<AuthSession, Error>
            if let pending = refreshTask { task = pending }
            else {
                task = Task {
                    let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
                    let data = try await self.raw(path: "auth/v1/token?grant_type=refresh_token", method: "POST", body: body, bearer: self.config.publishableKey)
                    return try Self.decoder().decode(AuthSession.self, from: data)
                }
                refreshTask = task
            }
            do {
                let renewed = try await task.value
                guard generation == sessionGeneration else { throw CancellationError() }
                try storage.save(renewed); self.session = renewed; refreshTask = nil
                return renewed.accessToken
            } catch {
                if generation == sessionGeneration {
                    refreshTask = nil
                    if error as? TikDogError == .signInRequired { try clearSession() }
                }
                throw error
            }
        }
        return session.accessToken
    }
    private func clearSession() throws {
        pendingFacebook = nil; facebookRequestID = nil
        sessionGeneration = UUID(); refreshTask?.cancel(); refreshTask = nil; session = nil
        try storage.save(nil)
    }
    private func setSession(_ value: AuthSession) throws {
        pendingFacebook = nil; facebookRequestID = nil
        try storage.save(value); sessionGeneration = UUID(); refreshTask?.cancel(); refreshTask = nil; session = value
    }
    private func raw(path: String, method: String = "GET", body: Data? = nil, bearer: String, contentType: String = "application/json") async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.url.appendingPathComponent("/")) else { throw TikDogError.unavailable }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        if !bearer.hasPrefix("sb_publishable_") { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let generation = sessionGeneration
        let (data, response) = try await network.data(for: request)
        guard generation == sessionGeneration else { throw CancellationError() }
        try check(response: response, data: data); return data
    }
    private func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw TikDogError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = error?["message"] as? String ?? error?["msg"] as? String ?? error?["error_description"] as? String ?? "The server couldn't complete this request (\(http.statusCode))."
            if http.statusCode == 401 { throw TikDogError.signInRequired }
            throw TikDogError.server(message)
        }
    }
    private func rpc<T: Decodable>(_ name: String, _ parameters: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let bearer = try await token()
        let data = try await raw(path: "rest/v1/rpc/\(name)", method: "POST", body: JSONSerialization.data(withJSONObject: parameters), bearer: bearer)
        return try Self.decoder().decode(type, from: data)
    }
    private func mutate(_ name: String, _ parameters: [String: String]) async throws {
        guard session != nil else { throw TikDogError.signInRequired }
        let bearer = try await token()
        _ = try await raw(path: "rest/v1/rpc/\(name)", method: "POST", body: JSONSerialization.data(withJSONObject: parameters), bearer: bearer)
    }
    public func signInProviders() async throws -> SignInProviders {
        struct Settings: Decodable { let external: [String: Bool] }
        let data = try await raw(path: "auth/v1/settings", bearer: config.publishableKey)
        let settings = try Self.decoder().decode(Settings.self, from: data)
        return SignInProviders(facebook: settings.external["facebook"] == true, apple: settings.external["apple"] == true)
    }
    public func beginFacebookSignIn() throws -> FacebookAuthorization {
        let verifier = Self.base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        guard var parts = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false) else { throw TikDogError.unavailable }
        parts.queryItems = [
            URLQueryItem(name: "provider", value: "facebook"),
            URLQueryItem(name: "redirect_to", value: "tikdog://auth/callback"),
            URLQueryItem(name: "scopes", value: "email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let url = parts.url else { throw TikDogError.unavailable }
        let id = UUID(); facebookRequestID = id
        pendingFacebook = PendingFacebookAuthorization(id: id, verifier: verifier, sessionGeneration: sessionGeneration)
        return FacebookAuthorization(id: id, url: url)
    }
    public func cancelFacebookSignIn(_ authorization: FacebookAuthorization) {
        if facebookRequestID == authorization.id { pendingFacebook = nil; facebookRequestID = nil }
    }
    public func completeFacebookSignIn(_ authorization: FacebookAuthorization, callback: URL) async throws {
        guard let pending = pendingFacebook, pending.id == authorization.id, pending.sessionGeneration == sessionGeneration else {
            throw TikDogError.invalidInput("This sign-in attempt has expired. Please try again.")
        }
        pendingFacebook = nil
        do {
            guard callback.scheme == "tikdog", callback.host == "auth", callback.path == "/callback",
                  callback.user == nil, callback.password == nil, callback.port == nil,
                  // Facebook's #_=_ marker can survive the browser's redirect chain.
                  [nil, "", "_=_"].contains(callback.fragment),
                  let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
                throw TikDogError.invalidInput("The sign-in response was invalid. Please try again.")
            }
            let items = parts.queryItems ?? []
            if items.contains(where: { $0.name == "error" || $0.name == "error_description" }) {
                throw TikDogError.invalidInput("Facebook sign-in was not completed. Please try again.")
            }
            let codes = items.filter { $0.name == "code" }
            guard codes.count == 1, let code = codes.first?.value, (1...2048).contains(code.count), !code.contains(where: { $0.isWhitespace }) else {
                throw TikDogError.invalidInput("The sign-in response was invalid. Please try again.")
            }
            let data = try await raw(path: "auth/v1/token?grant_type=pkce", method: "POST", body: JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": pending.verifier]), bearer: config.publishableKey)
            guard facebookRequestID == authorization.id else { throw CancellationError() }
            try setSession(Self.decoder().decode(AuthSession.self, from: data))
        } catch {
            cancelFacebookSignIn(authorization)
            throw error
        }
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public func signInWithApple(idToken: String, nonce: String, authorizationCode: String) async throws {
        let data = try await raw(path: "auth/v1/token?grant_type=id_token", method: "POST", body: JSONSerialization.data(withJSONObject: ["provider": "apple", "id_token": idToken, "nonce": nonce]), bearer: config.publishableKey)
        let value = try Self.decoder().decode(AuthSession.self, from: data); try setSession(value)
        try await registerAppleAuthorization(code: authorizationCode)
    }
    public func registerAppleAuthorization(code: String) async throws {
        _ = try await raw(path: "functions/v1/apple-credentials", method: "POST", body: JSONSerialization.data(withJSONObject: ["authorization_code": code]), bearer: try await token())
    }
    public func signOut() async throws {
        let access = session?.accessToken
        try clearSession()
        if let access { _ = try? await raw(path: "auth/v1/logout", method: "POST", bearer: access) }
    }
    public func accountState() async throws -> AccountState {
        guard session != nil else { return AccountState() }
        return try await rpc("account_state")
    }
    public func acceptTerms() async throws { try await mutate("accept_terms", ["terms_version": CommunityTerms.version]) }
    public func reportContent(kind: ReportTarget, id: UUID, reason: String) async throws { try await mutate("report_content", ["target_kind": kind.rawValue, "target_id": id.uuidString, "report_reason": reason]) }
    public func blockedAccounts() async throws -> [BlockedAccount] { try await rpc("blocked_accounts") }
    public func unblock(ownerId: UUID) async throws { try await mutate("unblock_owner", ["target_owner": ownerId.uuidString]) }
    public func bootstrap() async throws -> AppSnapshot {
        let generation = sessionGeneration
        var snapshot: AppSnapshot = try await rpc("bootstrap")
        // Pending uploads belong in the owner's gallery, never in a public feed.
        for dog in snapshot.dogs where dog.ownerId == snapshot.userId {
            let page: ProfilePage = try await rpc("dog_profile", ["target_dog": dog.id.uuidString])
            snapshot.videos.removeAll { $0.dogId == dog.id }; snapshot.videos.append(contentsOf: page.videos)
        }
        (snapshot.dogs, snapshot.videos) = try await resolveMedia(dogs: snapshot.dogs, videos: snapshot.videos)
        guard generation == sessionGeneration else { throw CancellationError() }
        return snapshot
    }
    public func feed(kind: FeedKind, offset: Int, limit: Int) async throws -> FeedPage {
        var page: FeedPage = try await rpc("get_feed", ["feed_kind": kind.rawValue, "page_offset": String(offset), "page_limit": String(limit)])
        (page.dogs, page.videos) = try await resolveMedia(dogs: page.dogs, videos: page.videos)
        return page
    }
    public func discover(query: String) async throws -> [Dog] {
        let dogs: [Dog] = try await rpc("discover_dogs", ["search_query": query])
        return try await resolveMedia(dogs: dogs, videos: []).0
    }
    public func profile(dogId: UUID) async throws -> ProfilePage {
        let page: ProfilePage = try await rpc("dog_profile", ["target_dog": dogId.uuidString])
        let (dogs, videos) = try await resolveMedia(dogs: [page.dog], videos: page.videos)
        return ProfilePage(dog: dogs[0], videos: videos)
    }
    private struct SignedObject: Decodable { var path: String; var signedURL: String?; var error: String? }
    private func resolveMedia(dogs: [Dog], videos: [Video]) async throws -> ([Dog], [Video]) {
        let paths = Set(dogs.map(\.avatarPath) + videos.flatMap { [$0.mediaPath, $0.thumbnailPath] })
        var signed: [String: String] = [:]
        for bucket in ["videos", "thumbnails", "avatars"] {
            let prefix = "storage://\(bucket)/"
            let objects = paths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
            guard !objects.isEmpty else { continue }
            let data = try await raw(path: "storage/v1/object/sign/\(bucket)", method: "POST", body: JSONSerialization.data(withJSONObject: ["paths": objects, "expiresIn": 900]), bearer: try await token())
            // Storage uses signedURL (not PostgREST snake_case).
            let results = try JSONDecoder().decode([SignedObject].self, from: data)
            for object in results {
                if let path = object.signedURL, path.hasPrefix("/object/sign/") {
                    signed[prefix + object.path] = config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/storage/v1" + path
                }
            }
        }
        return (dogs.map { dog in var dog = dog; dog.displayAvatarPath = signed[dog.avatarPath] ?? ""; return dog },
                videos.map { video in var video = video; video.playbackPath = signed[video.mediaPath] ?? ""; video.displayThumbnailPath = signed[video.thumbnailPath] ?? ""; return video })
    }
    public func setLike(videoId: UUID, liked: Bool) async throws { try await mutate("set_like", ["target_video": videoId.uuidString, "enabled": String(liked)]) }
    public func setBookmark(videoId: UUID, saved: Bool) async throws { try await mutate("set_bookmark", ["target_video": videoId.uuidString, "enabled": String(saved)]) }
    public func setFollow(dogId: UUID, following: Bool) async throws { try await mutate("set_follow", ["target_dog": dogId.uuidString, "enabled": String(following)]) }
    public func comments(videoId: UUID) async throws -> [DogComment] { try await rpc("get_comments", ["target_video": videoId.uuidString]) }
    public func addComment(videoId: UUID, body: String) async throws -> DogComment { try await rpc("add_comment", ["target_video": videoId.uuidString, "comment_body": body]) }
    public func saveDog(_ dog: Dog) async throws -> Dog {
        guard let user = session?.user.id, user == dog.ownerId else { throw TikDogError.signInRequired }
        try ContentRules.validateDog(name: dog.name, breed: dog.breed, bio: dog.bio)
        let saved: Dog = try await rpc("save_dog", ["dog_id": dog.id.uuidString, "dog_name": dog.name, "dog_breed": dog.breed, "dog_birthday": dog.birthday, "dog_bio": dog.bio, "dog_avatar": dog.avatarPath])
        return try await resolveMedia(dogs: [saved], videos: []).0[0]
    }
    private func upload(file: URL, path: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: config.url.appendingPathComponent("storage/v1/object/\(path)")); request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey"); request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type"); request.setValue("false", forHTTPHeaderField: "x-upsert")
        let delegate = UploadProgress(callback: progress)
        let (data, response) = try await network.upload(for: request, fromFile: file, delegate: delegate)
        try check(response: response, data: data)
    }
    private func removeObject(bucket: String, path: String) async throws {
        _ = try await raw(path: "storage/v1/object/\(bucket)", method: "DELETE", body: JSONSerialization.data(withJSONObject: ["prefixes": [path]]), bearer: try await token())
    }
    public func uploadAvatar(file: URL) async throws -> String {
        guard let user = session?.user.id else { throw TikDogError.signInRequired }
        let path = "\(user.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await upload(file: file, path: "avatars/\(path)", contentType: "image/jpeg") { _ in }
        return "storage://avatars/\(path)"
    }
    private func existingVideo(id: UUID) async throws -> Video? {
        let data = try await raw(path: "rest/v1/videos?id=eq.\(id.uuidString)&select=*", bearer: try await token())
        let videos = try Self.decoder().decode([Video].self, from: data)
        return try await resolveMedia(dogs: [], videos: videos).1.first
    }
    public func publish(_ video: Video, file: URL, thumbnail: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Video {
        guard let user = session?.user.id else { throw TikDogError.signInRequired }
        try ContentRules.validateVideo(caption: video.caption, duration: video.duration)
        let path = "\(user.uuidString.lowercased())/\(video.id.uuidString.lowercased())"
        if let existing = try await existingVideo(id: video.id), existing.dogId == video.dogId { progress(1); return existing }
        var uploadedVideo = false, uploadedCover = false, attemptedPublish = false
        do {
            try await upload(file: file, path: "videos/\(path).mp4", contentType: "video/mp4") { progress($0 * 0.9) }; uploadedVideo = true
            try await upload(file: thumbnail, path: "thumbnails/\(path).jpg", contentType: "image/jpeg") { progress(0.9 + $0 * 0.08) }; uploadedCover = true
            var published = video
            published.mediaPath = "storage://videos/\(path).mp4"
            published.thumbnailPath = "storage://thumbnails/\(path).jpg"
            attemptedPublish = true
            let result: Video = try await rpc("publish_video", ["video_id": video.id.uuidString, "featured_dog": video.dogId.uuidString, "video_caption": video.caption, "video_tags": video.hashtags.joined(separator: ","), "media_url": published.mediaPath, "thumbnail_url": published.thumbnailPath, "duration_seconds": String(video.duration)])
            progress(1); return try await resolveMedia(dogs: [], videos: [result]).1[0]
        } catch {
            if attemptedPublish {
                do {
                    if let recovered = try await existingVideo(id: video.id), recovered.dogId == video.dogId { progress(1); return recovered }
                } catch { throw error } // Preserve media when the commit result is unknown.
            }
            if uploadedVideo { try? await removeObject(bucket: "videos", path: "\(path).mp4") }
            if uploadedCover { try? await removeObject(bucket: "thumbnails", path: "\(path).jpg") }
            throw error
        }
    }
    public func vote(dogId: UUID) async throws -> [DailyStanding] { try await rpc("cast_daily_vote", ["target_dog": dogId.uuidString]) }
    public func report(videoId: UUID, reason: String) async throws { try await mutate("report_video", ["target_video": videoId.uuidString, "report_reason": reason]) }
    public func block(ownerId: UUID) async throws { try await mutate("block_owner", ["target_owner": ownerId.uuidString]) }
    public func markActivityRead() async throws { try await mutate("read_activity", [:]) }
    public func deleteVideo(id: UUID) async throws {
        guard session != nil else { throw TikDogError.signInRequired }
        _ = try await raw(path: "functions/v1/delete-video", method: "POST", body: JSONSerialization.data(withJSONObject: ["video_id": id.uuidString]), bearer: try await token())
    }
    public func deleteAccount() async throws {
        guard session != nil else { throw TikDogError.signInRequired }
        _ = try await raw(path: "functions/v1/delete-account", method: "POST", body: Data("{}".utf8), bearer: try await token())
        try clearSession()
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let callback: @Sendable (Double) -> Void
    init(callback: @escaping @Sendable (Double) -> Void) { self.callback = callback }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { callback(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }
}
