import AppKit
import KKitServicesAPI
import KKitUI
import SwiftUI

/// What the Island page's buttons do.
@MainActor
struct NowPlayingActions {
    var send: @MainActor (NowPlayingCommand) -> Void
    var seek: @MainActor (Double) -> Void
    var openApp: @MainActor () -> Void
}

/// The track's artwork, or the app's icon, or a note.
struct NowPlayingArtwork: View {
    let model: NowPlayingModel
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
                    .background(Color.white.opacity(0.08))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Left ear: a small artwork.
struct NowPlayingCompactLeading: View {
    let model: NowPlayingModel

    var body: some View {
        NowPlayingArtwork(model: model, size: 20, cornerRadius: 5)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        guard let info = model.info else { return String(localized: "Now Playing") }
        if let artist = info.artist {
            return String(localized: "Playing \(info.title) by \(artist)")
        }
        return String(localized: "Playing \(info.title)")
    }
}

/// Right ear: moving level bars while it plays.
struct NowPlayingCompactTrailing: View {
    let model: NowPlayingModel

    var body: some View {
        PlayingBars(isPlaying: model.info?.isPlaying == true)
            .frame(width: 18, height: 14)
            .accessibilityHidden(true)
    }
}

/// Four bars that bounce while playing and rest while paused. Still with Reduce Motion.
struct PlayingBars: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let phases: [Double] = [0, 1.7, 0.9, 2.6]
    private static let speeds: [Double] = [7.3, 9.1, 6.2, 8.4]

    var body: some View {
        let animate = isPlaying && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animate)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: proxy.size.width * 0.12) {
                    ForEach(Self.phases.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(height: proxy.size.height * CGFloat(barHeight(index, time: time, animate: animate)))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
        }
    }

    private func barHeight(_ index: Int, time: Double, animate: Bool) -> Double {
        guard animate else { return isPlaying ? [0.6, 0.9, 0.5, 0.75][index] : 0.25 }
        let wave = sin(time * Self.speeds[index] + Self.phases[index]) * 0.5 + 0.5
        return 0.25 + 0.75 * wave
    }
}

/// The Island page: artwork, title, artist, a scrubber and the transport buttons.
struct NowPlayingPageView: View {
    let model: NowPlayingModel
    let actions: NowPlayingActions

    var body: some View {
        if let info = model.info {
            HStack(alignment: .center, spacing: KKSpacing.m) {
                Button {
                    actions.openApp()
                } label: {
                    NowPlayingArtwork(model: model, size: 96, cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .help(model.appName.map { String(localized: "Open \($0)") } ?? "")

                VStack(alignment: .leading, spacing: KKSpacing.xs) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = info.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let appName = model.appName {
                        HStack(spacing: KKSpacing.xs) {
                            if let icon = model.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                            }
                            Text(appName)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    NowPlayingScrubber(info: info, seek: actions.seek)
                    NowPlayingControls(isPlaying: info.isPlaying, send: actions.send)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Text("Nothing is playing.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Previous, play/pause, next.
struct NowPlayingControls: View {
    let isPlaying: Bool
    let send: @MainActor (NowPlayingCommand) -> Void

    var body: some View {
        HStack(spacing: KKSpacing.xl) {
            button("backward.fill", size: 15, label: String(localized: "Previous Track")) {
                send(.previousTrack)
            }
            button(isPlaying ? "pause.fill" : "play.fill", size: 20, label: isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                send(.togglePlayPause)
            }
            button("forward.fill", size: 15, label: String(localized: "Next Track")) {
                send(.nextTrack)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, size: CGFloat, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}

/// Elapsed time, a bar you can click or drag to seek, and the duration. Ticks once a
/// second, only while it's on screen and playing.
struct NowPlayingScrubber: View {
    let info: NowPlayingInfo
    let seek: @MainActor (Double) -> Void

    /// 0…1 while dragging.
    @State private var dragFraction: Double?

    var body: some View {
        if let duration = info.duration {
            TimelineView(.periodic(from: .now, by: info.isPlaying ? 1 : 3600)) { timeline in
                let position = dragFraction.map { $0 * duration } ?? info.position(at: timeline.date) ?? 0
                HStack(spacing: KKSpacing.s) {
                    Text(NowPlayingFormat.time(position))
                        .frame(width: 38, alignment: .trailing)
                    bar(duration: duration, fraction: NowPlayingFormat.progress(position: position, duration: duration) ?? 0)
                    Text(NowPlayingFormat.time(duration))
                        .frame(width: 38, alignment: .leading)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            HStack(spacing: KKSpacing.xs) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Live")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(height: 12)
        }
    }

    private func bar(duration: Double, fraction: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white.opacity(dragFraction == nil ? 0.85 : 1))
                    .frame(width: width * CGFloat(fraction))
            }
            .frame(height: dragFraction == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(Double(value.location.x / width), 0), 1)
                    }
                    .onEnded { value in
                        let fraction = min(max(Double(value.location.x / width), 0), 1)
                        dragFraction = nil
                        seek(fraction * duration)
                    }
            )
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(Text("Position"))
        .accessibilityValue(Text(NowPlayingFormat.time(fraction * duration)))
        .accessibilityAdjustableAction { direction in
            let current = fraction * duration
            switch direction {
            case .increment: seek(min(current + 15, duration))
            case .decrement: seek(max(current - 15, 0))
            @unknown default: break
            }
        }
    }
}

/// Settings › Now Playing.
struct NowPlayingSettingsView: View {
    let model: NowPlayingModel

    @Setting(NowPlayingSettings.showCompact) private var showCompact
    @Setting(NowPlayingSettings.clickArtworkOpensApp) private var clickArtworkOpensApp

    var body: some View {
        Group {
            KKSection(
                String(localized: "Island"),
                footer: String(localized: "Works with any app that shows in Control Center's Now Playing: Music, Spotify, Podcasts, and videos in Safari or Chrome.")
            ) {
                Toggle(String(localized: "Show the artwork beside the notch while playing"), isOn: $showCompact)
                Toggle(String(localized: "Click the artwork to open the app"), isOn: $clickArtworkOpensApp)
            }
            KKSection(String(localized: "Status")) {
                switch model.availability {
                case .unknown:
                    Text("Starting…")
                        .foregroundStyle(.secondary)
                case .available:
                    if let info = model.info {
                        LabeledContent(String(localized: "Playing"), value: [info.title, model.appName].compactMap { $0 }.joined(separator: " · "))
                    } else {
                        Text("Nothing is playing.")
                            .foregroundStyle(.secondary)
                    }
                case .unavailable(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
