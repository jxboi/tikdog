import SwiftUI
import TikDogCore

struct LegalDocument: Decodable {
    var title: String
    var sections: [[String]]
}
struct LegalView: View {
    let kind: String
    private var document: LegalDocument? {
        guard let url = Bundle.main.url(forResource: "Legal", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let docs = try? JSONDecoder().decode([String: LegalDocument].self, from: data) else { return nil }
        return docs[kind]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let document {
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        if section.count == 2 {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(section[0]).font(.headline)
                                Text(section[1]).font(.body).textSelection(.enabled)
                            }
                        }
                    }
                } else { Text("This document couldn't load. Please retry.") }
                if let url = ReleaseConfiguration.url(for: kind) { Link("Read on our website", destination: url) }
            }.padding(24)
        }.background(Color.dogCream).navigationTitle(document?.title ?? "Policies").navigationBarTitleDisplayMode(.inline)
    }
}
enum ReleaseConfiguration {
    static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
    static func url(for kind: String) -> URL? {
        let key = kind == "privacy" ? "TIKDOG_PRIVACY_URL" : kind == "terms" ? "TIKDOG_TERMS_URL" : "TIKDOG_SUPPORT_URL"
        guard let text = value(key), let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
struct TermsConsentView: View {
    @Environment(AppModel.self) private var app
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A safe place for good dogs.").font(.title2.bold())
                    Text("You must be 16 or older. Keep animals safe, respect other people, and share only content you have permission to use. New contributions are reviewed before they appear publicly.")
                }
                Section {
                    NavigationLink("Terms of use") { LegalView(kind: "terms") }
                    NavigationLink("Privacy policy") { LegalView(kind: "privacy") }
                    Toggle("I am 16 or older and accept the terms and privacy policy", isOn: $agreed).accessibilityIdentifier("termsAgreement")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Continue") { Task {
                    busy = true; defer { busy = false }
                    do { try await app.repository.acceptTerms(); app.accountState.termsVersion = CommunityTerms.version; app.showTerms = false }
                    catch { self.error = error.localizedDescription }
                } }.disabled(!agreed || busy).accessibilityIdentifier("acceptTerms")
                Button("Sign out") { Task { do { try await app.signOut(); app.showTerms = false } catch { self.error = error.localizedDescription } } }.disabled(busy)
            }.navigationTitle("Welcome to the pack").interactiveDismissDisabled()
        }.tint(.dogOrange)
    }
}
