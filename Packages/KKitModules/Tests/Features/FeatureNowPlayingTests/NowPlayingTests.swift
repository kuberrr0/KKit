import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureNowPlaying

struct NowPlayingFormatTests {
    @Test func formatsTimes() {
        #expect(NowPlayingFormat.time(0) == "0:00")
        #expect(NowPlayingFormat.time(7.9) == "0:07")
        #expect(NowPlayingFormat.time(205) == "3:25")
        #expect(NowPlayingFormat.time(3723) == "1:02:03")
        #expect(NowPlayingFormat.time(-4) == "0:00")
    }

    @Test func progress() {
        #expect(NowPlayingFormat.progress(position: 30, duration: 120) == 0.25)
        #expect(NowPlayingFormat.progress(position: 500, duration: 120) == 1)
        #expect(NowPlayingFormat.progress(position: 30, duration: nil) == nil)
        #expect(NowPlayingFormat.progress(position: nil, duration: 120) == nil)
    }
}

struct NowPlayingInfoTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func positionAdvancesOnlyWhilePlaying() {
        var info = NowPlayingInfo(title: "Song", duration: 200, elapsed: 50, timestamp: start, playbackRate: 1, isPlaying: true)
        #expect(info.position(at: start.addingTimeInterval(10)) == 60)
        #expect(info.position(at: start.addingTimeInterval(1000)) == 200)
        info.isPlaying = false
        info.playbackRate = 0
        #expect(info.position(at: start.addingTimeInterval(10)) == 50)
        info.elapsed = nil
        #expect(info.position(at: start) == nil)
    }

    @Test func subtitleJoinsArtistAndAlbum() {
        #expect(NowPlayingInfo(title: "A", artist: "B", album: "C").subtitle == "B — C")
        #expect(NowPlayingInfo(title: "A", artist: "B").subtitle == "B")
        #expect(NowPlayingInfo(title: "A", artist: "", album: nil).subtitle == nil)
    }
}

@MainActor
struct NowPlayingFeatureTests {
    private func makeFeature(_ env: TestEnvironment) -> NowPlayingFeature {
        NowPlayingFeature(context: env.makeContext(for: "nowPlaying"))
    }

    private let playing = NowPlayingInfo(title: "Song", artist: "Artist", duration: 180, elapsed: 10, playbackRate: 1, isPlaying: true, appBundleID: "com.apple.Music")

    @Test func showsCompactWhilePlayingAndPageWhilePaused() async throws {
        let env = TestEnvironment()
        let feature = makeFeature(env)
        try await feature.start()
        await env.settle()
        #expect(env.island.activityIDs.isEmpty)
        #expect(env.nowPlaying.subscriberCount == 1)

        env.nowPlaying.nowPlaying = playing
        await env.settle()
        let activity = try #require(env.island.activity("nowPlaying"))
        #expect(activity.compactLeading != nil)
        #expect(activity.expanded != nil)

        var paused = playing
        paused.isPlaying = false
        env.nowPlaying.nowPlaying = paused
        await env.settle()
        let pausedActivity = try #require(env.island.activity("nowPlaying"))
        #expect(pausedActivity.compactLeading == nil)
        #expect(pausedActivity.expanded != nil)

        env.nowPlaying.nowPlaying = nil
        await env.settle()
        #expect(env.island.activityIDs.isEmpty)

        await feature.stop()
        await env.settle()
        #expect(env.nowPlaying.subscriberCount == 0)
    }

    @Test func compactCanBeTurnedOff() async throws {
        let env = TestEnvironment()
        let feature = makeFeature(env)
        try await feature.start()
        env.nowPlaying.nowPlaying = playing
        await env.settle()
        #expect(env.island.activity("nowPlaying")?.compactLeading != nil)

        env.makeContext(for: "nowPlaying").settings[NowPlayingSettings.showCompact] = false
        await env.settle()
        #expect(env.island.activity("nowPlaying")?.compactLeading == nil)
        await feature.stop()
    }

    @Test func commandsSendToTheService() async throws {
        let env = TestEnvironment()
        let feature = makeFeature(env)
        try await feature.start()
        for id in ["nowPlaying.playPause", "nowPlaying.next", "nowPlaying.previous"] {
            let command = try #require(feature.commands.first { $0.id.rawValue == id })
            try await command.perform(CommandInvocation())
        }
        #expect(env.nowPlaying.commands == [.togglePlayPause, .nextTrack, .previousTrack])
        await feature.stop()
    }
}
