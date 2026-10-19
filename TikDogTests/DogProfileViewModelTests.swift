import XCTest
import TikDogCore
@testable import TikDog

@MainActor final class DogProfileViewModelTests: XCTestCase {
    func testOlderProfileCannotOverwriteTheCompletedRefresh() async throws {
        let snapshot = DemoContent.snapshot()
        let old = ProfilePage(dog: snapshot.dogs[0], videos: [snapshot.videos[0]])
        var new = old; new.dog.bio = "Updated profile"; new.videos = []
        let responses = DeferredProfiles(pages: [old, new])
        let app = AppModel(repository: DeferredRepository(profileResponses: responses))
        await app.load()
        let model = DogProfileViewModel()

        let first = Task { await model.load(dogId: old.dog.id, app: app) }
        await responses.firstGate.waitUntilStarted()
        let second = Task { await model.load(dogId: old.dog.id, app: app) }
        await responses.secondGate.waitUntilStarted()
        await responses.secondGate.finish()
        await second.value
        await responses.firstGate.finish()
        await first.value

        XCTAssertEqual(app.snapshot.dogs.first { $0.id == old.dog.id }?.bio, "Updated profile")
        XCTAssertFalse(app.snapshot.videos.contains { $0.dogId == old.dog.id })
        XCTAssertFalse(model.isLoading)
    }

    func testOlderCompletionCannotClearLoadingForTheCurrentRequest() async throws {
        let snapshot = DemoContent.snapshot()
        let page = ProfilePage(dog: snapshot.dogs[0], videos: [])
        let responses = DeferredProfiles(pages: [page, page])
        let app = AppModel(repository: DeferredRepository(profileResponses: responses))
        await app.load()
        let model = DogProfileViewModel()

        let first = Task { await model.load(dogId: page.dog.id, app: app) }
        await responses.firstGate.waitUntilStarted()
        let second = Task { await model.load(dogId: page.dog.id, app: app) }
        await responses.secondGate.waitUntilStarted()
        await responses.firstGate.finish()
        await first.value
        let stillLoading = model.isLoading
        await responses.secondGate.finish()
        await second.value

        XCTAssertTrue(stillLoading)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderProfileCannotOverwriteANewlySavedIdentity() async throws {
        let snapshot = DemoContent.snapshot()
        let old = ProfilePage(dog: snapshot.dogs[0], videos: [snapshot.videos[0]])
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(profileDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let model = DogProfileViewModel()
        let gate = await delay.enqueue()
        let read = Task { await model.load(dogId: old.dog.id, app: app) }
        await gate.waitUntilStarted()

        var draft = old.dog; draft.name = "Cabby Junior"
        let saved = try await repository.saveDog(draft)
        app.mergeLocal(dogs: [saved])
        await gate.finish()
        await read.value

        XCTAssertEqual(app.snapshot.dogs.first { $0.id == old.dog.id }?.name, "Cabby Junior")
        XCTAssertEqual(app.snapshot.dogs.first { $0.id == old.dog.id }?.moderationStatus, .pending)
        XCTAssertFalse(model.isLoading)
    }

    func testInitialProfileLoadRetriesAfterAnUnrelatedWrite() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(profileDelay: delay))
        await app.load()
        let dog = try XCTUnwrap(app.visibleDogs.first)
        app.applyLocalChange { $0.videos.removeAll { $0.dogId == dog.id } }
        let model = DogProfileViewModel()
        let gate = await delay.enqueue()
        let profile = Task { await model.load(dogId: dog.id, app: app) }
        await gate.waitUntilStarted()

        await app.markRead()
        await gate.finish()
        await profile.value

        XCTAssertTrue(app.snapshot.videos.contains { $0.dogId == dog.id })
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
    }

    func testProfileStartedDuringRefreshCannotOverwriteTheCommittedRefresh() async throws {
        let bootstrap = DeferredBootstrap(), profiles = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: bootstrap, profileDelay: profiles)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.visibleDogs.first { $0.name == "Mochi" })
        let bootGate = await bootstrap.enqueue(), profileGate = await profiles.enqueue()
        let refresh = Task { await app.load() }
        await bootGate.waitUntilStarted()
        let model = DogProfileViewModel()
        let profile = Task { await model.load(dogId: dog.id, app: app) }
        await profileGate.waitUntilStarted()
        try await repository.base.setFollow(dogId: dog.id, following: false)

        await bootGate.finish()
        await refresh.value
        XCTAssertEqual(app.snapshot.dogs.first { $0.id == dog.id }?.followerCount, dog.followerCount - 1)
        await profileGate.finish()
        await profile.value

        XCTAssertEqual(app.snapshot.dogs.first { $0.id == dog.id }?.followerCount, dog.followerCount - 1)
        XCTAssertFalse(model.isLoading)
    }
}
