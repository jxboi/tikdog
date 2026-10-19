import AuthenticationServices
import UIKit
import TikDogCore

@MainActor final class FacebookWebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL) async throws -> URL {
        guard session == nil else { throw TikDogError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            let authentication = ASWebAuthenticationSession(url: url, callbackURLScheme: "tikdog") { [weak self] callback, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: TikDogError.unavailable) }
                }
            }
            authentication.presentationContextProvider = self
            session = authentication
            if !authentication.start() {
                session = nil
                continuation.resume(throwing: TikDogError.unavailable)
            }
        }
    }

    func cancel() { session?.cancel() }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
