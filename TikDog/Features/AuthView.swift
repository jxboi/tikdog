import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import TikDogCore

struct AuthView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var facebookAuthentication = FacebookWebAuthentication()
    @State private var busy = false
    @State private var error: String?
    @State private var nonce = ""
    @State private var consent = false
    @State private var providers: SignInProviders?
    @State private var providerError: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "pawprint.fill").font(.system(size: 47)).foregroundStyle(Color.dogOrange).rotationEffect(.degrees(-12)).padding(.top, 30)
                    Text("Join TikDog").font(.system(size: 37, weight: .bold, design: .rounded)).tracking(-1.3).multilineTextAlignment(.center)
                    Text("Follow dogs, leave comments, and share your own videos.").font(.system(size: 13)).foregroundStyle(Color.dogMuted)
                    if app.isDemo {
                        Text("You're exploring the local demo. Facebook and Apple sign-in are available in the connected app.").font(.subheadline).foregroundStyle(Color.dogMuted).multilineTextAlignment(.center).padding()
                        Button("Keep exploring") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink("Terms of use") { LegalView(kind: "terms") }
                            NavigationLink("Privacy policy") { LegalView(kind: "privacy") }
                            Toggle("I am 16 or older and accept the terms and privacy policy", isOn: $consent).font(.caption).accessibilityIdentifier("signupConsent")
                        }.font(.caption)
                        SignInWithAppleButton(.continue) { request in
                            let newNonce = Self.randomNonce(); nonce = newNonce
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = SHA256.hash(data: Data(newNonce.utf8)).map { String(format: "%02x", $0) }.joined()
                        } onCompletion: { result in
                            Task { await apple(result) }
                        }.signInWithAppleButtonStyle(.black).frame(height: 51).clipShape(RoundedRectangle(cornerRadius: 16)).disabled(busy || !consent || providers?.apple != true).accessibilityIdentifier("appleSignIn")
                        if providers?.apple == false { Text("Apple sign-in isn't available yet.").font(.caption).foregroundStyle(Color.dogMuted).accessibilityIdentifier("appleUnavailable") }
                        Button { Task { await facebook() } } label: {
                            HStack(spacing: 12) {
                                Text("f").font(.system(size: 29, weight: .bold))
                                Text("Continue with Facebook").font(.system(size: 16, weight: .semibold))
                            }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 51)
                                .background(Color(red: 0.086, green: 0.467, blue: 1), in: RoundedRectangle(cornerRadius: 16))
                        }.accessibilityIdentifier("facebookSignIn").accessibilityLabel("Continue with Facebook").disabled(busy || !consent || providers?.facebook != true)
                        if providers == nil && providerError == nil { ProgressView("Checking sign-in options…").font(.caption) }
                        if let providerError {
                            Text(providerError).font(.caption).foregroundStyle(.red)
                            Button("Check sign-in options again") { Task { await loadProviders() } }
                        }
                        if busy { ProgressView("Signing in…").font(.caption) }
                        if let error { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).accessibilityIdentifier("authError") }
                    }
                }.padding(.horizontal, 30).padding(.bottom, 35)
            }.background(Color.dogCream).foregroundStyle(Color.dogInk).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }.accessibilityLabel("Continue as guest").disabled(busy) } }
        }.preferredColorScheme(.light).interactiveDismissDisabled(busy).onDisappear { facebookAuthentication.cancel() }.task { await loadProviders() }
    }
    private func loadProviders() async {
        guard let backend = app.repository as? SupabaseRepository else { return }
        providerError = nil
        do { providers = try await backend.signInProviders() }
        catch { providerError = "Couldn't check sign-in options. Check your connection and try again." }
    }
    private func facebook() async {
        guard consent, providers?.facebook == true, let backend = app.repository as? SupabaseRepository else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let authorization = try await backend.beginFacebookSignIn()
            do {
                let callback = try await facebookAuthentication.authenticate(url: authorization.url)
                try await backend.completeFacebookSignIn(authorization, callback: callback)
                try await finishSignIn(backend)
            } catch {
                await backend.cancelFacebookSignIn(authorization)
                throw error
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
        catch { self.error = error.localizedDescription }
    }
    private func apple(_ result: Result<ASAuthorization, Error>) async {
        guard consent, providers?.apple == true, let backend = app.repository as? SupabaseRepository else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let auth = try result.get()
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential, let data = credential.identityToken, let token = String(data: data, encoding: .utf8), let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8), !nonce.isEmpty else { throw TikDogError.unavailable }
            do { try await backend.signInWithApple(idToken: token, nonce: nonce, authorizationCode: code) }
            catch {
                // Authentication can succeed before the revocation credential is registered.
                await app.load(); app.showTerms = false; throw error
            }
            try await finishSignIn(backend)
        } catch let error as ASAuthorizationError where error.code == .canceled { }
        catch { self.error = error.localizedDescription }
    }
    private func finishSignIn(_ backend: SupabaseRepository) async throws {
        do {
            let state = try await backend.accountState()
            if !state.isSuspended && !state.isDeleting { try await backend.acceptTerms() }
        } catch { await app.load(); app.showTerms = false; throw error }
        await app.load(); app.notify("Welcome to the pack"); dismiss()
    }
    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString + UUID().uuidString }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
