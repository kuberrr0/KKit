import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureShelf

private func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func makeFile(_ name: String, in folder: URL, contents: String = "hello") throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(contents.utf8).write(to: url)
    return url
}

/// A 4 × 2 PNG.
private func pngData() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP438DwHxkzoAsAAFUhE/EgQkhoAAAAAElFTkSuQmCC")!
}

struct FileActionsTests {
    @Test func numbersTakenNamesLikeFinder() {
        let folder = URL(fileURLWithPath: "/tmp/shelf", isDirectory: true)
        let taken: Set<String> = ["/tmp/shelf/a.zip", "/tmp/shelf/a 2.zip"]
        let url = FileActions.available("a", extension: "zip", in: folder) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "a 3.zip")
    }

    @Test func renamingKeepsTheExtension() {
        let original = URL(fileURLWithPath: "/tmp/report.pdf")
        #expect(FileActions.renamedFileName("summary", original: original) == "summary.pdf")
        #expect(FileActions.renamedFileName("summary.PDF", original: original) == "summary.PDF")
        #expect(FileActions.renamedFileName("  ", original: original) == nil)
        #expect(FileActions.renamedFileName("a/b", original: original) == nil)
        #expect(FileActions.renamedFileName(".hidden", original: original) == nil)
    }

    @Test func convertsAndResizesImages() throws {
        let folder = try makeFolder()
        let source = folder.appendingPathComponent("dot.png")
        try pngData().write(to: source)
        let jpeg = try FileActions.convertImage(source, to: .jpeg, maxPixels: nil, into: folder)
        #expect(jpeg.lastPathComponent == "dot.jpg")
        #expect(FileManager.default.fileExists(atPath: jpeg.path))
        #expect(FileActions.halfSize(of: source) == 2)
        let small = try FileActions.convertImage(source, to: .png, maxPixels: 2, into: folder)
        #expect(small.lastPathComponent == "dot (2×1).png")
    }

    @Test func compressesWithDitto() throws {
        let folder = try makeFolder()
        let file = try makeFile("notes.txt", in: folder)
        let zip = try FileActions.compress(file, into: folder)
        #expect(zip.lastPathComponent == "notes.zip")
        #expect(FileManager.default.fileExists(atPath: zip.path))
    }
}

@MainActor
struct ShelfControllerTests {
    private func makeController() throws -> (TestEnvironment, ShelfController, URL) {
        let environment = TestEnvironment()
        let context = environment.makeContext(for: ShelfFeature.manifest.id)
        let controller = ShelfController(settings: context.settings, pasteboard: environment.pasteboard)
        let folder = try makeFolder()
        controller.attach(folder: folder.appendingPathComponent("Shelf", isDirectory: true), items: [])
        return (environment, controller, folder)
    }

    @Test func addsEachKindOnceAndKeepsReferences() async throws {
        let (_, controller, folder) = try makeController()
        let file = try makeFile("a.txt", in: folder)
        var saved: [ShelfItem] = []
        controller.onChange = { saved = $0 }
        try await controller.add([.file(file), .file(file), .url(URL(string: "https://kkit.app")!), .text("hello"), .text("  ")])
        #expect(controller.items.map(\.title) == ["a.txt", "kkit.app", "hello"])
        #expect(controller.items.first?.fileURL == file)
        #expect(controller.items.first?.isOwnCopy == false)
        #expect(saved.count == 3)
        try await controller.add([.file(file)])
        #expect(controller.itemCount == 3)
    }

    @Test func keepsCopiesWhenAskedAndDeletesThemOnRemove() async throws {
        let (environment, controller, folder) = try makeController()
        environment.settings.set(true, for: "shelf.keepCopies")
        let file = try makeFile("b.txt", in: folder)
        try await controller.add([.file(file)])
        let item = try #require(controller.items.first)
        #expect(item.isOwnCopy)
        let copy = try #require(item.fileURL)
        #expect(copy != file)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        controller.remove(item)
        #expect(controller.items.isEmpty)
        // The user's own file is never touched.
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func droppedImagesBecomeFiles() async throws {
        let (_, controller, _) = try makeController()
        try await controller.add([.image(pngData(), type: "public.png")])
        let item = try #require(controller.items.first)
        #expect(item.isOwnCopy)
        #expect(item.isImage)
        #expect(item.fileURL?.pathExtension == "png")
    }

    @Test func dropsTheOldestBeyondTheLimit() async throws {
        let (environment, controller, _) = try makeController()
        environment.settings.set(2, for: "shelf.maxItems")
        try await controller.add([.text("one"), .text("two"), .text("three")])
        #expect(controller.items.compactMap(\.plainText) == ["two", "three"])
    }

    @Test func autoClearRemovesOldItems() async throws {
        let (environment, controller, _) = try makeController()
        var clock = Date(timeIntervalSince1970: 0)
        controller.now = { clock }
        try await controller.add([.text("old")])
        clock = Date(timeIntervalSince1970: 7200)
        try await controller.add([.text("new")])
        environment.settings.set(ShelfAutoClear.hour, for: "shelf.autoClear")
        controller.removeExpired()
        #expect(controller.items.compactMap(\.plainText) == ["new"])
    }

    @Test func forgetsFilesThatAreGone() throws {
        let (_, controller, folder) = try makeController()
        let present = try makeFile("here.txt", in: folder)
        let gone = folder.appendingPathComponent("gone.txt")
        let items = [
            ShelfItem(content: .file(present), addedAt: Date()),
            ShelfItem(content: .file(gone), addedAt: Date()),
            ShelfItem(content: .text("note"), addedAt: Date()),
        ]
        controller.attach(folder: folder, items: items)
        #expect(controller.items.count == 2)
    }

    @Test func renamesFiles() async throws {
        let (_, controller, folder) = try makeController()
        let file = try makeFile("draft.md", in: folder)
        _ = try makeFile("taken.md", in: folder)
        try await controller.add([.file(file)])
        let item = try #require(controller.items.first)
        #expect(throws: ShelfError.self) { try controller.rename(item, to: "taken") }
        try controller.rename(item, to: "final")
        #expect(controller.items.first?.fileURL?.lastPathComponent == "final.md")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("final.md").path))
    }

    @Test func copiesFilesAndText() async throws {
        let (environment, controller, folder) = try makeController()
        let file = try makeFile("c.txt", in: folder)
        try await controller.add([.file(file), .text("hi")])
        controller.copy([controller.items[0]])
        #expect(environment.pasteboard.writes.last?.fileURLs == [file])
        controller.copy([controller.items[1]])
        #expect(environment.pasteboard.writes.last?.string == "hi")
        controller.copyPath(controller.items[0])
        #expect(environment.pasteboard.writes.last?.string == file.path)
    }

    @Test func addsWhatsOnTheClipboard() async throws {
        let (environment, controller, _) = try makeController()
        environment.pasteboard.simulateCopy(.text("copied words"))
        try await controller.addClipboard()
        #expect(controller.items.first?.plainText == "copied words")
    }
}

@MainActor
struct ShelfFeatureTests {
    @Test func publishesTheShelfAndOffersDropZones() async throws {
        let environment = TestEnvironment()
        let feature = ShelfFeature(context: environment.makeContext(for: ShelfFeature.manifest.id))
        try await feature.start()
        let shelf = try #require(environment.services.resolve((any ShelfServicing).self))
        try await shelf.add([.text("from another feature")])
        #expect(shelf.itemCount == 1)
        #expect(feature.islandDropZones.map(\.id) == ["shelf", "airDrop"])
        #expect(feature.islandPages.map(\.id) == [ShelfFeature.pageID])
        #expect(feature.commands.allSatisfy { $0.id.rawValue.hasPrefix("shelf.") })
        await feature.stop()
        #expect(environment.services.resolve((any ShelfServicing).self) == nil)
    }

    @Test func addToShelfTakesFilesLinksAndText() {
        let file = SearchResult(id: "f", title: "f", icon: .symbol("doc"), score: 1, kind: .file(URL(fileURLWithPath: "/tmp/f")))
        let command = SearchResult(id: "c", title: "c", icon: .symbol("gear"), score: 1, kind: .command("x.y", argument: nil))
        #expect(ShelfFeature.droppedItem(for: file) == .file(URL(fileURLWithPath: "/tmp/f")))
        #expect(ShelfFeature.droppedItem(for: command) == nil)
    }
}
