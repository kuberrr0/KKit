import Foundation
import KKitCore
import KKitServices
import KKitServicesAPI
import KKitServicesTesting
import SwiftUI
import Testing

struct FileStorageServiceTests {
    struct Note: Codable, Equatable {
        var title: String
        var tags: [String]
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("KKitStorageTests-\(UUID().uuidString)", isDirectory: true)

    @Test func writesAndReadsJSONPerFeature() throws {
        let storage = FileStorageService(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try storage.readJSON(Note.self, named: "last", for: "quickNote") == nil)
        try storage.writeJSON(Note(title: "Hello", tags: ["a"]), named: "last", for: "quickNote")
        #expect(try storage.readJSON(Note.self, named: "last", for: "quickNote") == Note(title: "Hello", tags: ["a"]))
        #expect(try storage.readJSON(Note.self, named: "last", for: "shelf") == nil)

        let folder = try storage.directory(for: "quickNote")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("last.json").path))

        try storage.removeJSON(named: "last", for: "quickNote")
        #expect(try storage.readJSON(Note.self, named: "last", for: "quickNote") == nil)
    }

    @Test func rejectsPathTricks() {
        let storage = FileStorageService(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) { try storage.writeJSON(1, named: "../escape", for: "quickNote") }
        #expect(throws: (any Error).self) { try storage.writeJSON(1, named: ".hidden", for: "quickNote") }
        #expect(throws: (any Error).self) { try storage.directory(for: "../up") }
    }

    @MainActor
    @Test func featureContextExposesCoreServices() throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "timer")

        try context.storage.write(["x": 1], named: "state")
        #expect(try context.storage.read([String: Int].self, named: "state") == ["x": 1])
        #expect(context.permissions.status(of: .accessibility) == .notDetermined)
        #expect(context.overlays.screens.count == 1)

        let panel = context.overlays.makePanel(.init(placement: .centered(size: .init(width: 100, height: 100))), content: .init(EmptyViewStub()))
        panel.show()
        #expect(panel.isVisible)
    }
}

private struct EmptyViewStub: View {
    var body: some View { EmptyView() }
}
