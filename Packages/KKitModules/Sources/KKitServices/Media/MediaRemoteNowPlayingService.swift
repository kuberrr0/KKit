import Darwin
import Foundation
import KKitCore
import KKitServicesAPI
import os

/// Now Playing through Apple's private MediaRemote framework.
///
/// Since macOS 15.4 MediaRemote only answers Apple's own processes, so KKit doesn't
/// call it directly. While someone subscribes, it runs `/usr/bin/perl` with a one-line
/// script that loads KKit's small helper library (`KKitMediaRemoteAdapter.framework`,
/// built from `Helpers/MediaRemoteAdapter`). The helper writes a JSON line whenever
/// what's playing changes and takes commands on its standard input. When the helper or
/// perl is missing, or MediaRemote refuses, `availability` says so and features show
/// nothing.
@MainActor
public final class MediaRemoteNowPlayingService: NowPlayingService {
    public private(set) var availability: NowPlayingAvailability = .unknown {
        didSet {
            if availability != oldValue {
                availabilityBroadcast.send(availability)
            }
        }
    }

    public private(set) var nowPlaying: NowPlayingInfo?

    private let broadcast = Broadcast<NowPlayingInfo?>()
    private let availabilityBroadcast = Broadcast<NowPlayingAvailability>()
    private let adapterBinary: URL?
    private let perl: URL
    private let log = KKitLog.logger("nowPlaying")

    private var process: Process?
    private var input: FileHandle?
    private var receivedReady = false
    private var restarts = 0
    private var restartTask: Task<Void, Never>?
    private var lastError: String?

    /// - Parameter adapterBundle: `KKitMediaRemoteAdapter.framework` inside the app.
    public init(adapterBundle: URL?, perl: URL = URL(fileURLWithPath: "/usr/bin/perl")) {
        adapterBinary = adapterBundle.flatMap { Bundle(url: $0)?.executableURL }
        self.perl = perl
        broadcast.onFirstSubscriber = { [weak self] in self?.startHelper() }
        broadcast.onLastSubscriberGone = { [weak self] in self?.stopHelper() }
    }

    /// The helper inside this app, if it's there.
    public static var bundledAdapter: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("KKitMediaRemoteAdapter.framework")
    }

    public func updates() -> AsyncStream<NowPlayingInfo?> {
        broadcast.stream(initial: .some(nowPlaying))
    }

    public func availabilityUpdates() -> AsyncStream<NowPlayingAvailability> {
        availabilityBroadcast.stream(initial: availability)
    }

    public func send(_ command: NowPlayingCommand) {
        guard write(command.rawValue) else { return }
        // Show the change straight away; the helper's report follows.
        guard var info = nowPlaying else { return }
        let playing: Bool
        switch command {
        case .play: playing = true
        case .pause: playing = false
        case .togglePlayPause: playing = !info.isPlaying
        case .nextTrack, .previousTrack: return
        }
        let now = Date()
        info.elapsed = info.position(at: now)
        info.timestamp = now
        info.isPlaying = playing
        info.playbackRate = playing ? 1 : 0
        publish(info)
    }

    public func seek(to seconds: Double) {
        let target = max(seconds, 0)
        guard write("seek \(target)") else { return }
        guard var info = nowPlaying else { return }
        info.elapsed = target
        info.timestamp = Date()
        publish(info)
    }

    // MARK: Helper process

    private func startHelper() {
        restartTask?.cancel()
        restartTask = nil
        guard process == nil else { return }
        guard let adapterBinary, FileManager.default.fileExists(atPath: adapterBinary.path) else {
            availability = .unavailable(String(localized: "KKit's Now Playing helper is missing from the app."))
            return
        }
        guard FileManager.default.isExecutableFile(atPath: perl.path) else {
            availability = .unavailable(String(localized: "Now Playing needs /usr/bin/perl, which isn't on this Mac."))
            return
        }

        let process = Process()
        process.executableURL = perl
        process.arguments = ["-e", Self.script, adapterBinary.path]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // Writing after the helper quit returns an error instead of killing KKit.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let reader = NowPlayingLineReader { [weak self] message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(message) }
            }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        let log = self.log
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            log.error("Now Playing helper: \(text, privacy: .public)")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.lastError = text }
            }
        }
        let identifier = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperEnded(identifier, status: status) }
            }
        }

        do {
            try process.run()
        } catch {
            log.error("Couldn't start the Now Playing helper: \(error.localizedDescription, privacy: .public)")
            availability = .unavailable(String(localized: "KKit couldn't start its Now Playing helper."))
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        receivedReady = false
    }

    private func stopHelper() {
        restartTask?.cancel()
        restartTask = nil
        guard let process else { return }
        self.process = nil
        // Closing its input makes the helper quit; terminate in case it's stuck.
        try? input?.close()
        input = nil
        if process.isRunning {
            process.terminate()
        }
        publish(nil)
    }

    private func helperEnded(_ identifier: ObjectIdentifier, status: Int32) {
        guard let process, ObjectIdentifier(process) == identifier else { return }
        self.process = nil
        try? input?.close()
        input = nil
        publish(nil)
        guard broadcast.hasSubscribers else { return }
        if case .unavailable = availability {
            return
        }
        guard receivedReady, restarts < Self.restartDelays.count else {
            log.error("The Now Playing helper stopped (status \(status)); giving up")
            availability = .unavailable(lastError.map { String(localized: "The Now Playing helper stopped: \($0)") }
                ?? String(localized: "The Now Playing helper keeps stopping."))
            return
        }
        let delay = Self.restartDelays[restarts]
        restarts += 1
        log.info("The Now Playing helper stopped (status \(status)); restarting in \(delay) s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.broadcast.hasSubscribers else { return }
            self.startHelper()
        }
    }

    private static let restartDelays: [Double] = [1, 5, 30]

    @discardableResult
    private func write(_ line: String) -> Bool {
        guard let input else { return false }
        do {
            try input.write(contentsOf: Data((line + "\n").utf8))
            return true
        } catch {
            log.error("Couldn't send \(line, privacy: .public) to the Now Playing helper: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Messages

    func receive(_ message: NowPlayingAdapterMessage) {
        switch message {
        case .ready:
            receivedReady = true
            restarts = 0
            availability = .available
        case .unavailable(let reason):
            availability = .unavailable(reason)
        case .nothingPlaying:
            publish(nil)
        case .info(var info, let artworkUnchanged):
            if artworkUnchanged {
                info.artwork = nowPlaying?.artwork
            }
            publish(info)
        }
    }

    private func publish(_ info: NowPlayingInfo?) {
        guard info != nowPlaying else { return }
        nowPlaying = info
        broadcast.send(info)
    }

    /// Loads the helper into perl and calls its entry point, which never returns.
    static let script = """
    use strict; use warnings; use DynaLoader;
    my $path = shift @ARGV or die "no helper path\\n";
    my $lib = DynaLoader::dl_load_file($path, 0) or die "can't load the helper: " . DynaLoader::dl_error() . "\\n";
    my $entry = DynaLoader::dl_find_symbol($lib, "kkit_mediaremote_stream") or die "no entry point: " . DynaLoader::dl_error() . "\\n";
    my $stream = DynaLoader::dl_install_xsub("main::kkit_mediaremote_stream", $entry);
    $stream->();
    """
}

/// One line from the helper.
enum NowPlayingAdapterMessage: Sendable, Equatable {
    case ready
    case unavailable(String)
    case nothingPlaying
    /// `artworkUnchanged`: keep the artwork from the last report.
    case info(NowPlayingInfo, artworkUnchanged: Bool)

    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "unavailable":
            self = .unavailable(object["reason"] as? String ?? String(localized: "Now Playing isn't available on this Mac."))
        case "none":
            self = .nothingPlaying
        case "info":
            guard let title = object["title"] as? String, !title.isEmpty else {
                self = .nothingPlaying
                return
            }
            func number(_ key: String) -> Double? {
                (object[key] as? NSNumber)?.doubleValue
            }
            let rate = number("rate")
            let playing = (object["playing"] as? Bool) ?? ((rate ?? 0) > 0)
            let duration = number("duration").flatMap { $0 > 0 ? $0 : nil }
            let info = NowPlayingInfo(
                title: title,
                artist: object["artist"] as? String,
                album: object["album"] as? String,
                duration: duration,
                elapsed: number("elapsed"),
                timestamp: number("timestamp").map { Date(timeIntervalSince1970: $0) } ?? Date(),
                playbackRate: rate ?? (playing ? 1 : 0),
                isPlaying: playing,
                appBundleID: object["bundleID"] as? String,
                appPID: (object["pid"] as? NSNumber).map { Int32(truncatingIfNeeded: $0.intValue) },
                artwork: (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
            )
            self = .info(info, artworkUnchanged: (object["artworkUnchanged"] as? Bool) ?? false)
        default:
            return nil
        }
    }
}

/// Splits the helper's output into lines and parses them, off the main thread.
final class NowPlayingLineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onMessage: @Sendable (NowPlayingAdapterMessage) -> Void

    init(onMessage: @escaping @Sendable (NowPlayingAdapterMessage) -> Void) {
        self.onMessage = onMessage
    }

    func append(_ data: Data) {
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines where !line.isEmpty {
            if let message = NowPlayingAdapterMessage(line: Data(line)) {
                onMessage(message)
            }
        }
    }
}
