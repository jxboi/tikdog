import SwiftUI
import TikDogCore

struct ActivityView: View {
    @Environment(AppModel.self) private var app
    @State private var filter = "All"
    private var items: [ActivityItem] {
        app.snapshot.activities.filter {
            switch filter {
            case "Followers": $0.kind == "follow"
            case "Reviews": $0.kind == "review"
            case "Interactions": $0.kind != "follow" && $0.kind != "review"
            default: true
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Activity").scaledFont(size: 32, weight: .bold, design: .rounded, relativeTo: .largeTitle).tracking(-1)
                    if app.snapshot.userId != nil && !app.snapshot.activities.isEmpty {
                    ScrollView(.horizontal) { HStack(spacing: 9) {
                        ForEach(["All", "Followers", "Interactions"] + (app.snapshot.activities.contains { $0.kind == "review" } ? ["Reviews"] : []), id: \.self) { item in
                            Button { filter = item } label: {
                                Text(item).scaledFont(size: 12, weight: .semibold, relativeTo: .caption)
                                    .foregroundStyle(filter == item ? .white : Color.dogMuted)
                                    .padding(.horizontal, 17).frame(minHeight: 44)
                                    .background(filter == item ? Color.dogInk : .white, in: Capsule())
                            }.accessibilityAddTraits(filter == item ? .isSelected : [])
                        }
                    } }.scrollIndicators(.hidden).accessibilityIdentifier("activityFilters")
                    }
                    if app.snapshot.userId == nil {
                        EmptyState(icon: "heart", title: "Good things are waiting.", message: "Join the pack to see who's cheering for your dog.")
                        Button("Join the pack") { app.showAuth = true }.buttonStyle(PrimaryButtonStyle())
                    } else if items.isEmpty { EmptyState(icon: "heart", title: "The start of something lovely.", message: "New followers, likes, and comments will find you here.") }
                    else {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button {
                                    if let videoId = item.videoId, let video = app.snapshot.videos.first(where: { $0.id == videoId }) {
                                        if item.kind == "review" { app.selectedSubmission = video } else { app.selectedVideo = video }
                                    } else if let dog = app.snapshot.dogs.first(where: { $0.id == item.dogId }) { app.selectedDog = dog }
                                    else { app.notify("This submission is no longer available.") }
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        if let dog = app.snapshot.dogs.first(where: { $0.id == item.dogId }) { DogAvatar(dog: dog, size: 49) }
                                        else { Image(systemName: icon(item.kind)).font(.system(size: 20)).foregroundStyle(Color.dogOrange).frame(width: 49, height: 49).background(Color.dogOrange.opacity(0.12), in: Circle()) }
                                        VStack(alignment: .leading, spacing: 7) { Text(item.message).scaledFont(size: 13, weight: .medium).lineSpacing(4).multilineTextAlignment(.leading); Text(item.createdAt, style: .relative).scaledFont(size: 10, relativeTo: .caption2).foregroundStyle(Color.dogMuted) }
                                        Spacer(minLength: 0)
                                    }.padding(.vertical, 19)
                                }
                                if item.id != items.last?.id { Divider().opacity(0.4) }
                            }
                        }
                    }
                }.padding(24)
            }.background(Color.dogCream).foregroundStyle(Color.dogInk).toolbar(.hidden, for: .navigationBar)
                .task { await app.refreshActivity(); await app.markRead() }.refreshable { await app.load(); await app.markRead() }
        }
    }
    private func icon(_ kind: String) -> String { switch kind { case "follow": "person.badge.plus"; case "comment": "bubble.right.fill"; case "milestone": "sparkles"; case "review": "checkmark.shield.fill"; default: "heart.fill" } }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var showDelete = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) { Image(systemName: "pawprint.fill").foregroundStyle(Color.dogOrange).font(.title2); VStack(alignment: .leading, spacing: 5) { Text("TikDog").font(.system(size: 20, weight: .bold, design: .rounded)); Text("A little place for very good dogs.").font(.caption).foregroundStyle(Color.dogMuted) } }.padding(.vertical, 10)
                    if app.isDemo { Label("You're exploring the demo pack", systemImage: "sparkles").font(.subheadline) }
                }
                Section("Your account") {
                    if app.snapshot.userId == nil { Button("Sign in or create an account") { dismiss(); app.showAuth = true } }
                    else {
                        Text(app.snapshot.displayName)
                        if !app.isDemo { Button("Sign out") { Task { await signOut() } }.disabled(deleting) }
                    }
                    if app.isDemo { Text("Demo changes stay on this device.").font(.caption).foregroundStyle(Color.dogMuted) }
                }
                Section("Made for a kind community") {
                    NavigationLink("Community guidelines & terms") { LegalView(kind: "terms") }
                    NavigationLink("Privacy policy") { LegalView(kind: "privacy") }
                    NavigationLink("Contact & support") { LegalView(kind: "support") }
                    if app.snapshot.userId != nil { NavigationLink("Blocked accounts") { BlockedAccountsView() } }
                    NavigationLink("Video credits") { ScrollView { Text("The demo dogs are fictional characters illustrated by licensed stock footage. No endorsement by the creators is implied.\n\nDog videos: Pexels contributors. Downloaded and used under the Pexels License. Bundled clips are shortened, resized, and muted for the demo.\n\nSee MEDIA_CREDITS.md in the project for original sources, authors, and license details.").font(.body).lineSpacing(6).padding(24); Link("Pexels License", destination: URL(string: "https://www.pexels.com/license/")!).padding() }.background(Color.dogCream).navigationTitle("Credits") }
                }
                if app.snapshot.userId != nil {
                    Section { Button(role: .destructive) { showDelete = true } label: { if deleting { ProgressView() } else { Text("Delete account") } }.disabled(deleting) } footer: { Text("This removes your dogs, videos, and account data.") }
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background(Color.dogCream).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(deleting) } }
                .confirmationDialog("Delete your account and all your dogs' content? This can't be undone.", isPresented: $showDelete, titleVisibility: .visible) { Button("Delete account", role: .destructive) { Task { await deleteAccount() } }; Button("Keep my pack", role: .cancel) {} }
                .interactiveDismissDisabled(deleting)
        }.preferredColorScheme(.light).tint(.dogInk)
    }
    private func signOut() async { deleting = true; defer { deleting = false }; do { try await app.signOut(); dismiss() } catch { self.error = error.localizedDescription } }
    private func deleteAccount() async { deleting = true; defer { deleting = false }; do { try await app.deleteAccount(); dismiss(); app.notify("Your account has been deleted") } catch { self.error = error.localizedDescription; if let state = try? await app.repository.accountState() { app.accountState = state } } }
}

struct BlockedAccountsView: View {
    @Environment(AppModel.self) private var app
    @State private var accounts: [BlockedAccount] = []
    @State private var error: String?
    @State private var busy = false
    @State private var isLoading = true
    @State private var loadRequest = UUID()
    var body: some View {
        List {
            if isLoading && accounts.isEmpty { ProgressView("Loading blocked accounts…") }
            else if accounts.isEmpty && error == nil { Text("You haven't blocked any accounts.").foregroundStyle(.secondary) }
            ForEach(accounts) { account in
                HStack {
                    Text(account.name); Spacer()
                    Button("Unblock") { Task {
                        busy = true; defer { busy = false }
                        do { try await app.repository.unblock(ownerId: account.id); accounts.removeAll { $0.id == account.id }; app.applyLocalChange { $0.blockedOwnerIds.remove(account.id) }; await app.load() }
                        catch { self.error = error.localizedDescription }
                    } }.disabled(busy).accessibilityHint("Allow \(account.name)'s dogs and activity to appear again")
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
                Button("Try again") { Task { await load() } }.disabled(isLoading)
            }
        }.navigationTitle("Blocked accounts")
            .task { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        let request = UUID(); loadRequest = request
        let session = app.sessionEpoch
        isLoading = true; error = nil
        defer { if loadRequest == request { isLoading = false } }
        do {
            let latest = try await app.repository.blockedAccounts()
            guard !Task.isCancelled && loadRequest == request && session == app.sessionEpoch else { return }
            accounts = latest
        } catch {
            if !Task.isCancelled && loadRequest == request && session == app.sessionEpoch { self.error = error.localizedDescription }
        }
    }
}
