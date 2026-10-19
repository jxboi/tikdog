import Foundation

struct UploadDraft: Codable, Equatable, Sendable {
    var id: UUID
    var fileName: String
    var dogId: UUID?
    var caption: String
    var hashtags: String
    var trimStart: Double
    var trimEnd: Double
    var updatedAt: Date
}

actor UploadDraftStore {
    nonisolated let directory: URL
    private var latestRevision = -1
    private func isMovieFileName(_ name: String) -> Bool {
        let file = URL(fileURLWithPath: name)
        return name == file.lastPathComponent && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil && !file.pathExtension.isEmpty
    }

    init(directory: URL) { self.directory = directory }

    static func accountDirectory(ownerId: UUID, isDemo: Bool) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("TikDog/UploadDrafts/\(isDemo ? "demo" : "connected")/\(ownerId.uuidString)", isDirectory: true)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    func importMovie(_ source: URL) throws -> URL {
        guard latestRevision != .max else { throw CancellationError() }
        try prepareDirectory()
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        return destination
    }

    func load() throws -> UploadDraft? {
        let manifest = directory.appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        let draft = try JSONDecoder().decode(UploadDraft.self, from: Data(contentsOf: manifest))
        guard isMovieFileName(draft.fileName),
              draft.trimStart.isFinite, draft.trimEnd.isFinite,
              draft.trimStart >= 0, (1...60.1).contains(draft.trimEnd - draft.trimStart),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(draft.fileName).path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return draft
    }

    func save(_ draft: UploadDraft, revision: Int) throws {
        guard revision > latestRevision else { return }
        try prepareDirectory()
        guard isMovieFileName(draft.fileName),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(draft.fileName).path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let previous = try? load()
        try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("draft.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        latestRevision = revision
        if let previous, previous.fileName != draft.fileName { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.fileName)) }
    }

    func clear(revision: Int) throws {
        guard revision > latestRevision else { return }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        latestRevision = revision
    }
}
