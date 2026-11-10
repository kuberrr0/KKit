import Foundation

/// What's playing right now, in any app that reports to macOS's Now Playing (Music,
/// Spotify, Safari, Chrome, Podcasts, …).
public struct NowPlayingInfo: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    /// Seconds. `nil` for live streams and apps that don't say.
    public var duration: Double?
    /// Seconds into the track at `timestamp`.
    public var elapsed: Double?
    /// When `elapsed` was measured.
    public var timestamp: Date
    /// 1 while playing at normal speed, 0 while paused.
    public var playbackRate: Double
    public var isPlaying: Bool
    /// The app playing (the browser rather than its web content process, where macOS says).
    public var appBundleID: String?
    public var appPID: Int32?
    /// PNG or JPEG data.
    public var artwork: Data?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: Double? = nil,
        elapsed: Double? = nil,
        timestamp: Date = Date(),
        playbackRate: Double = 0,
        isPlaying: Bool = false,
        appBundleID: String? = nil,
        appPID: Int32? = nil,
        artwork: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.appBundleID = appBundleID
        self.appPID = appPID
        self.artwork = artwork
    }

    /// Seconds into the track at `date`, worked out from the last report, clamped to
    /// the duration. `nil` when the app doesn't report a position.
    public func position(at date: Date) -> Double? {
        guard let elapsed else { return nil }
        var value = elapsed
        if isPlaying {
            value += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        value = max(value, 0)
        if let duration, duration > 0 {
            value = min(value, duration)
        }
        return value
    }

    /// "Artist — Album", whichever parts there are.
    public var subtitle: String? {
        let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

/// Media transport commands, sent to whichever app is the Now Playing app.
public enum NowPlayingCommand: String, Sendable, CaseIterable {
    case play
    case pause
    case togglePlayPause = "toggle"
    case nextTrack = "next"
    case previousTrack = "previous"
}

/// Whether the Now Playing source works on this Mac.
public enum NowPlayingAvailability: Sendable, Equatable {
    /// Not started yet, or starting.
    case unknown
    case available
    /// The reason, for Settings.
    case unavailable(String)
}

/// The system's Now Playing information and media controls. macOS has no public API
/// for this; the implementation uses the private MediaRemote framework through a small
/// helper (ARCHITECTURE.md §8) and reports `.unavailable` when that doesn't work.
/// It only listens while someone subscribes.
@MainActor
public protocol NowPlayingService: AnyObject {
    var availability: NowPlayingAvailability { get }
    /// `nil` when nothing is playing or paused.
    var nowPlaying: NowPlayingInfo? { get }
    /// The current value, then every change.
    func updates() -> AsyncStream<NowPlayingInfo?>
    /// Changes of `availability`, starting with the current one.
    func availabilityUpdates() -> AsyncStream<NowPlayingAvailability>
    func send(_ command: NowPlayingCommand)
    /// Jumps to `seconds` into the current track.
    func seek(to seconds: Double)
}
