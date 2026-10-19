import SwiftUI
import PhotosUI
import TikDogCore

@MainActor @Observable final class DogProfileViewModel {
    var isLoading = false
    var error: String?
    private var requestId = UUID()

    func load(dogId: UUID, app: AppModel) async {
        let epoch = app.dataEpoch
        let request = UUID(); requestId = request
        isLoading = true; error = nil
        defer { if request == requestId { isLoading = false } }
        do {
            while !Task.isCancelled {
                let revision = app.stateRevision
                let page = try await app.repository.profile(dogId: dogId)
                guard !Task.isCancelled && app.dataEpoch == epoch && request == requestId else { return }
                guard app.stateRevision == revision else { continue }
                app.replaceProfile(page)
                return
            }
        } catch {
            if !Task.isCancelled && app.dataEpoch == epoch && request == requestId { self.error = error.localizedDescription }
        }
    }
}

struct MyProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var showNewDog = false
    @State private var showSettings = false
    var body: some View {
        NavigationStack {
            Group {
                if let dog = app.selectedOwnDog { DogProfileView(dog: dog, isRoot: true).id(dog.id) }
                else {
                    VStack(spacing: 24) {
                        EmptyState(icon: "pawprint", title: "Every star starts somewhere.", message: "Give your dog a profile. The world is ready to meet them.").frame(maxHeight: 350)
                        Button(app.snapshot.userId == nil ? "Join the pack" : "Meet my dog") { if app.requireMember() { showNewDog = true } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
                        Spacer()
                    }.padding(.top, 40).frame(maxWidth: .infinity).background(Color.dogCream)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(app.ownDogs) { dog in Button { app.selectedOwnDogId = dog.id } label: { Label(dog.name, systemImage: dog.id == app.selectedOwnDog?.id ? "checkmark" : "pawprint") } }
                        Button { if app.requireMember() { showNewDog = true } } label: { Label("Add a dog", systemImage: "plus") }
                    } label: { HStack(spacing: 7) { Text("My pack").font(.system(size: 16, weight: .bold, design: .rounded)); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }.foregroundStyle(Color.dogInk) }.accessibilityIdentifier("packMenu")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "line.3.horizontal").font(.system(size: 21)).foregroundStyle(Color.dogInk) }.accessibilityLabel("Settings") }
            }
            .sheet(isPresented: $showNewDog) { DogEditorView(dog: nil) { app.selectedOwnDogId = $0.id } }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }.tint(.dogInk)
    }
}

struct DogProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let dog: Dog
    var isRoot = false
    @State private var editing = false
    @State private var savedTab = false
    @State private var model = DogProfileViewModel()
    @State private var localVideo: Video?
    @State private var localAuth = false
    private var current: Dog { app.snapshot.dogs.first { $0.id == dog.id } ?? dog }
    private var isOwner: Bool { current.ownerId == app.snapshot.userId }
    private var videos: [Video] { app.snapshot.videos.filter { $0.dogId == dog.id }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(spacing: 21) {
                VStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        DogAvatar(dog: current, size: 112, ring: true).padding(5).background(.white, in: Circle())
                        Image(systemName: "pawprint.fill").font(.system(size: 15)).foregroundStyle(Color.dogInk).padding(10).background(Color.dogOrange, in: Circle()).rotationEffect(.degrees(14)).offset(x: 1, y: -2)
                    }.padding(.top, 20)
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { Text(current.name).font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1); if current.isFeatured { Image(systemName: "checkmark.seal.fill").font(.system(size: 17)).foregroundStyle(Color.dogOrange) } }
                        Text(current.breed.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.dogMuted)
                    }
                    HStack(spacing: 0) {
                        stat("Videos", value: videos.count)
                        Rectangle().fill(Color.dogInk.opacity(0.1)).frame(width: 1, height: 25)
                        stat("Followers", value: current.followerCount)
                        Rectangle().fill(Color.dogInk.opacity(0.1)).frame(width: 1, height: 25)
                        stat("Following", value: isOwner ? app.snapshot.followingDogIds.count : current.followingCount)
                    }.padding(.vertical, 5).padding(.horizontal, 25)
                    if isOwner && current.moderationStatus != .ready { Label(current.moderationStatus == .pending ? "Profile awaiting review" : "Profile removed by moderation", systemImage: "shield").font(.caption).foregroundStyle(Color.dogMuted) }
                    if !current.bio.isEmpty { Text(current.bio).scaledFont(size: 13).lineSpacing(5).multilineTextAlignment(.center).padding(.horizontal, 30) }
                    if !current.birthday.isEmpty {
                        Label("Born \(birthday)", systemImage: "birthday.cake").font(.system(size: 11)).foregroundStyle(Color.dogMuted)
                    }
                    HStack(spacing: 10) {
                        if isOwner {
                            Button { editing = true } label: { Label("Edit profile", systemImage: "pencil").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle(dark: true)).accessibilityIdentifier("editDog")
                        } else {
                            Button { if app.snapshot.userId == nil { localAuth = true } else { Task { await app.follow(current) } } } label: { Text(app.snapshot.followingDogIds.contains(dog.id) ? "Following ✓" : "Follow \(current.name)") }.buttonStyle(PrimaryButtonStyle(dark: app.snapshot.followingDogIds.contains(dog.id))).disabled(app.pendingActions.contains("follow-\(dog.id)"))
                        }
                        ShareLink(item: "Meet \(current.name), a \(current.breed), on TikDog. \(current.bio)") { Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.dogInk).frame(width: 52, height: 51).background(.white, in: RoundedRectangle(cornerRadius: 18)) }.accessibilityLabel("Share dog profile")
                    }.padding(.horizontal, 26).padding(.top, 4)
                }
                HStack(spacing: 0) {
                    galleryTab("Their little adventures", icon: "square.grid.3x3", saved: false)
                    if isOwner { galleryTab("Saved", icon: "bookmark", saved: true) }
                }.padding(.top, 8).overlay(alignment: .bottom) { Rectangle().fill(Color.dogInk.opacity(0.06)).frame(height: 1) }
                if model.isLoading && videos.isEmpty { ProgressView().padding(30) }
                else if let loadError = model.error {
                    VStack(spacing: 14) {
                        Text(loadError).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("Try again") { Task { await model.load(dogId: dog.id, app: app) } }.buttonStyle(PrimaryButtonStyle())
                    }.padding(24)
                }
                else if (savedTab ? app.savedVideos : videos).isEmpty { EmptyState(icon: savedTab ? "bookmark" : "video", title: savedTab ? "Keep the good stuff." : "A star in the making.", message: savedTab ? "Save videos you love and find them here." : "Their first adventure is just an upload away.") }
                else { VideoGrid(videos: savedTab ? app.savedVideos : videos, onSelect: { localVideo = $0 }) }
            }.padding(.bottom, 20)
        }.background(Color.dogCream).foregroundStyle(Color.dogInk)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isRoot { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }.accessibilityLabel("Close profile") } }
                if !isOwner { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Report profile") { if app.requireMember() { Task { do { try await app.repository.reportContent(kind: .dog, id: dog.id, reason: "inappropriate"); app.applyLocalChange { $0.dogs.removeAll { $0.id == dog.id } }; app.notify("Profile reported and hidden"); dismiss() } catch { app.handle(error) } } } }; Button("Block this account", role: .destructive) { Task { await app.block(current); dismiss() } } } label: { Image(systemName: "ellipsis").foregroundStyle(Color.dogInk) }.accessibilityLabel("Profile options") } }
            }
            .sheet(isPresented: $localAuth) { AuthView() }
            .fullScreenCover(item: $localVideo) { video in FeedView(standaloneVideos: savedTab ? app.savedVideos : videos, initialVideo: video.id, isStandalone: true).preferredColorScheme(.dark) }
            .sheet(isPresented: $editing) { DogEditorView(dog: current) }
            .task(id: dog.id) { await model.load(dogId: dog.id, app: app) }
            .refreshable { await model.load(dogId: dog.id, app: app) }
    }
    private var birthday: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: current.birthday) else { return current.birthday }; return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    private func stat(_ title: String, value: Int) -> some View { VStack(spacing: 5) { Text(value.compactCount).font(.system(size: 22, weight: .bold, design: .rounded)); Text(title).font(.system(size: 10)).foregroundStyle(Color.dogMuted) }.frame(maxWidth: .infinity) }
    private func galleryTab(_ title: String, icon: String, saved: Bool) -> some View {
        Button { savedTab = saved; Haptics.selection() } label: { VStack(spacing: 14) { HStack(spacing: 7) { Image(systemName: icon).font(.system(size: 13)); Text(title).font(.system(size: 11, weight: .semibold)) }.foregroundStyle(savedTab == saved ? Color.dogInk : Color.dogMuted); Capsule().fill(savedTab == saved ? Color.dogOrange : .clear).frame(height: 3) }.frame(maxWidth: .infinity).frame(minHeight: 44) }.padding(.horizontal, 22).accessibilityAddTraits(savedTab == saved ? .isSelected : [])
    }
}

struct VideoGrid: View {
    @Environment(AppModel.self) private var app
    let videos: [Video]
    var onSelect: ((Video) -> Void)? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 3) {
            ForEach(videos) { video in
                Button { if let onSelect { onSelect(video) } else { app.selectedVideo = video } } label: {
                    GeometryReader { geometry in
                        MediaImage(path: video.displayThumbnailPath ?? video.thumbnailPath).frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .overlay(alignment: .topLeading) { if video.moderationStatus != .ready { Text(video.moderationStatus == .pending ? "In review" : "Removed").font(.caption2.bold()).padding(6).background(.regularMaterial, in: Capsule()).padding(6) } }
                            .overlay(alignment: .bottomLeading) { Label(video.viewCount.compactCount, systemImage: "play").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).shadow(radius: 3).padding(9) }
                    }.aspectRatio(0.72, contentMode: .fit).clipped()
                }.accessibilityLabel("Play \(video.caption)")
            }
        }
    }
}

struct DogEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let dog: Dog?
    let onSaved: ((Dog) -> Void)?
    @State private var name = ""
    @State private var breed = ""
    @State private var bio = ""
    @State private var birthday = Date.now
    @State private var hasBirthday = false
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoadingPhoto = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false

    init(dog: Dog?, onSaved: ((Dog) -> Void)? = nil) {
        self.dog = dog
        self.onSaved = onSaved
        _name = State(initialValue: dog?.name ?? "")
        _breed = State(initialValue: dog?.breed ?? "")
        _bio = State(initialValue: dog?.bio ?? "")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let date = dog.flatMap { formatter.date(from: $0.birthday) }
        _birthday = State(initialValue: date ?? .now)
        _hasBirthday = State(initialValue: date != nil)
    }
    private var birthdayText: String {
        guard hasBirthday else { return "" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: birthday)
    }
    private var savedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var savedBreed: String { breed.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        savedName != (dog?.name ?? "") || savedBreed != (dog?.breed ?? "") || bio != (dog?.bio ?? "") || birthdayText != (dog?.birthday ?? "") || photoData != nil || isLoadingPhoto
    }
    private var canSave: Bool {
        !saving && !isLoadingPhoto && (dog == nil || hasChanges)
            && !savedName.isEmpty && !savedBreed.isEmpty
    }
    var body: some View {
        let currentPhotoData = photoData
        let currentIsLoadingPhoto = isLoadingPhoto
        return NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack { Spacer(); VStack(spacing: 12) {
                            if let currentPhotoData, let image = UIImage(data: currentPhotoData) { Image(uiImage: image).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle()) }
                            else if let dog { DogAvatar(dog: dog, size: 90) }
                            else { Image(systemName: "camera.fill").font(.system(size: 25)).foregroundStyle(Color.dogOrange).frame(width: 90, height: 90).background(Color.dogOrange.opacity(0.12), in: Circle()) }
                            Text("Choose profile photo").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dogInk)
                            if currentIsLoadingPhoto { ProgressView("Loading photo…").font(.caption) }
                        }; Spacer() }.padding(.vertical, 10)
                    }
                }.listRowBackground(Color.clear)
                Section("The star of the show") {
                    TextField("Dog's name", text: $name).accessibilityIdentifier("dogNameInput")
                    TextField("Breed (mixed breeds welcome)", text: $breed).accessibilityIdentifier("dogBreedInput")
                    Toggle("Add birthday", isOn: $hasBirthday).tint(.dogOrange)
                    if hasBirthday { DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date) }
                    TextField("A little personality (160 characters)", text: $bio, axis: .vertical).lineLimit(3...5)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                Section { Button { Task { await save() } } label: { HStack { Spacer(); if saving { ProgressView() } else { Text(dog == nil ? "Welcome to the pack" : "Save profile").bold() }; Spacer() } }.disabled(!canSave).foregroundStyle(Color.dogInk) }.listRowBackground(Color.dogOrange.opacity(canSave ? 1 : 0.35))
            }.disabled(saving).scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.dogCream).navigationTitle(dog == nil ? "Meet your dog" : "Edit profile").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(saving) } }
                .interactiveDismissDisabled(saving || hasChanges)
                .alert("Discard your profile changes?", isPresented: $confirmDiscard) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                }
                .task(id: photo) {
                    guard let photo else { return }
                    isLoadingPhoto = true; error = nil
                    defer { if self.photo == photo { isLoadingPhoto = false } }
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.preparingThumbnail(of: CGSize(width: 800, height: 800))?.jpegData(compressionQuality: 0.8) else { throw TikDogError.invalidInput("Couldn't open that photo.") }
                        guard !Task.isCancelled && self.photo == photo else { return }
                        photoData = jpeg
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.preferredColorScheme(.light)
    }
    private func save() async {
        guard canSave, app.requireMember(), let userId = app.snapshot.userId else { return }
        let session = app.sessionEpoch
        saving = true; error = nil; defer { saving = false }
        do {
            try ContentRules.validateDog(name: name, breed: breed, bio: bio)
            var avatarPath = dog?.avatarPath ?? ""
            if let photoData {
                let file = URL.temporaryDirectory.appendingPathComponent("\(UUID()).jpg"); try photoData.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
                avatarPath = try await app.repository.uploadAvatar(file: file)
                guard session == app.sessionEpoch else { return }
            }
            var draft = dog ?? Dog(ownerId: userId, name: name, breed: breed)
            draft.name = savedName; draft.breed = savedBreed; draft.bio = bio; draft.birthday = birthdayText; draft.avatarPath = avatarPath
            let saved = try await app.repository.saveDog(draft)
            guard session == app.sessionEpoch else { return }
            app.mergeLocal(dogs: [saved]); onSaved?(saved)
            app.notify("Profile saved. Awaiting moderation review."); dismiss()
        } catch { if session == app.sessionEpoch && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}
