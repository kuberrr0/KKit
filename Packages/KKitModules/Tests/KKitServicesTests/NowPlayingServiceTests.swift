import Foundation
import KKitCore
import KKitServicesAPI
import Testing
@testable import KKitServices

struct NowPlayingAdapterMessageTests {
    private func parse(_ json: String) -> NowPlayingAdapterMessage? {
        NowPlayingAdapterMessage(line: Data(json.utf8))
    }

    @Test func parsesStatusLines() {
        #expect(parse(#"{"type":"ready"}"#) == .ready)
        #expect(parse(#"{"type":"none"}"#) == .nothingPlaying)
        #expect(parse(#"{"type":"unavailable","reason":"No"}"#) == .unavailable("No"))
        #expect(parse(#"{"type":"something"}"#) == nil)
        #expect(parse("not json") == nil)
    }

    @Test func parsesInfo() throws {
        let artwork = Data([1, 2, 3]).base64EncodedString()
        let line = """
        {"type":"info","title":"Song","artist":"Artist","album":"Album","duration":200.5,"elapsed":12,\
        "rate":1,"playing":true,"timestamp":1000000,"pid":42,"bundleID":"com.spotify.client","artwork":"\(artwork)"}
        """
        guard case .info(let info, let unchanged) = parse(line) else {
            Issue.record("not parsed as info")
            return
        }
        #expect(!unchanged)
        #expect(info.title == "Song")
        #expect(info.subtitle == "Artist — Album")
        #expect(info.duration == 200.5)
        #expect(info.elapsed == 12)
        #expect(info.isPlaying)
        #expect(info.playbackRate == 1)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_000_000))
        #expect(info.appPID == 42)
        #expect(info.appBundleID == "com.spotify.client")
        #expect(info.artwork == Data([1, 2, 3]))
    }

    @Test func infoWithoutTitleIsNothing() {
        #expect(parse(#"{"type":"info","title":""}"#) == .nothingPlaying)
    }

    @Test func keepsArtworkFlagAndInfersPlaying() {
        guard case .info(let info, let unchanged) = parse(#"{"type":"info","title":"A","rate":0,"duration":0,"artworkUnchanged":true}"#) else {
            Issue.record("not parsed as info")
            return
        }
        #expect(unchanged)
        #expect(!info.isPlaying)
        // A zero duration means the app didn't say.
        #expect(info.duration == nil)
    }

    @Test func lineReaderSplitsChunks() {
        let received = Received()
        let reader = NowPlayingLineReader { received.add($0) }
        reader.append(Data(#"{"type":"rea"#.utf8))
        #expect(received.messages.isEmpty)
        reader.append(Data("dy\"}\n{\"type\":\"none\"}\n{\"ty".utf8))
        #expect(received.messages == [.ready, .nothingPlaying])
    }
}

@MainActor
struct MediaRemoteNowPlayingServiceTests {
    @Test func missingHelperIsUnavailable() async {
        let service = MediaRemoteNowPlayingService(adapterBundle: nil)
        #expect(service.availability == .unknown)
        let updates = service.updates()
        _ = updates
        guard case .unavailable = service.availability else {
            Issue.record("expected unavailable, got \(service.availability)")
            return
        }
        #expect(service.nowPlaying == nil)
    }

    @Test func artworkCarriesOverWhenUnchanged() {
        let service = MediaRemoteNowPlayingService(adapterBundle: nil)
        service.receive(.ready)
        #expect(service.availability == .available)
        service.receive(.info(NowPlayingInfo(title: "A", artwork: Data([9])), artworkUnchanged: false))
        service.receive(.info(NowPlayingInfo(title: "B"), artworkUnchanged: true))
        #expect(service.nowPlaying?.title == "B")
        #expect(service.nowPlaying?.artwork == Data([9]))
        service.receive(.nothingPlaying)
        #expect(service.nowPlaying == nil)
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [NowPlayingAdapterMessage] = []

    func add(_ message: NowPlayingAdapterMessage) {
        lock.withLock { storage.append(message) }
    }

    var messages: [NowPlayingAdapterMessage] {
        lock.withLock { storage }
    }
}
