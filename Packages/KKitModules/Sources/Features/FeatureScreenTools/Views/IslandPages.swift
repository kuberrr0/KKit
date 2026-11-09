import AppKit
import KKitServicesAPI
import KKitUI
import SwiftUI

/// A small icon-over-label button for the dark Island.
struct IslandActionButton: View {
    let title: String
    let symbol: String
    let action: @MainActor () -> Void

    init(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: KKSpacing.xxs) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 18)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 48)
            .padding(.vertical, KKSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: KKRadius.control))
    }
}

/// The screenshot that just landed in the Island, with what you can do with it.
struct ScreenshotPage: View {
    let controller: ScreenToolsController

    var body: some View {
        if let shot = controller.latest {
            HStack(alignment: .top, spacing: KKSpacing.m) {
                Image(decorative: shot.capture.image, scale: shot.capture.scale)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 96)
                    .clipShape(RoundedRectangle(cornerRadius: KKRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: KKRadius.control).strokeBorder(.white.opacity(0.2)))
                    .onDrag { NSItemProvider(contentsOf: shot.fileURL) ?? NSItemProvider() }
                    .help(String(localized: "Drag it into any app"))
                VStack(alignment: .leading, spacing: KKSpacing.s) {
                    VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                        Text(shot.isSaved ? shot.fileURL.lastPathComponent : String(localized: "Not saved"))
                            .font(.callout)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(shot.capture.image.width) × \(shot.capture.image.height)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    HStack(spacing: KKSpacing.xs) {
                        IslandActionButton(String(localized: "Copy"), symbol: "doc.on.doc") {
                            Task { await controller.copy(shot) }
                        }
                        if shot.isSaved {
                            IslandActionButton(String(localized: "Show"), symbol: "folder") {
                                controller.reveal(shot.fileURL)
                            }
                        } else {
                            IslandActionButton(String(localized: "Save"), symbol: "square.and.arrow.down") {
                                Task { await controller.save(shot) }
                            }
                        }
                        IslandActionButton(String(localized: "Mark Up"), symbol: "pencil.tip.crop.circle") {
                            controller.edit(shot)
                        }
                        IslandActionButton(String(localized: "Pin"), symbol: "pin") {
                            controller.pin(shot)
                        }
                        IslandActionButton(String(localized: "Text"), symbol: "text.viewfinder") {
                            Task { await controller.recognizeText(in: shot) }
                        }
                        if controller.canShelve {
                            IslandActionButton(String(localized: "Shelf"), symbol: "tray.and.arrow.down") {
                                Task { await controller.shelve([.file(shot.fileURL)]) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("No screenshot")
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Text read from the screen. It's already copied.
struct RecognizedTextPage: View {
    let controller: ScreenToolsController

    var body: some View {
        let text = controller.recognizedText ?? ""
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
            HStack(spacing: KKSpacing.xs) {
                IslandActionButton(String(localized: "Copy"), symbol: "doc.on.doc") {
                    controller.context.pasteboard.copy(text)
                }
                IslandActionButton(String(localized: "Translate"), symbol: "translate") {
                    controller.showTranslation(of: text, near: nil)
                }
                if controller.canSendToNote {
                    IslandActionButton(String(localized: "Note"), symbol: "square.and.pencil") {
                        controller.sendToNote(text)
                    }
                }
                if controller.canShelve {
                    IslandActionButton(String(localized: "Shelf"), symbol: "tray.and.arrow.down") {
                        Task { await controller.shelve([.text(text)]) }
                    }
                }
                Spacer()
                Text("Copied \(ImageAnalyzer.wordCount(text)) words")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// What a QR code or barcode said. The first one is copied.
struct ScannedCodesPage: View {
    let controller: ScreenToolsController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            ForEach(controller.scannedCodes.prefix(4), id: \.self) { code in
                HStack(spacing: KKSpacing.s) {
                    Image(systemName: ScreenToolsController.link(in: code) == nil ? "text.quote" : "link")
                        .foregroundStyle(.white.opacity(0.6))
                    Text(code)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: KKSpacing.s)
                    if let url = ScreenToolsController.link(in: code) {
                        Button(String(localized: "Open")) {
                            controller.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button(String(localized: "Copy")) {
                        controller.context.pasteboard.copy(code)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if controller.scannedCodes.count > 4 {
                Text("\(controller.scannedCodes.count - 4) more copied")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// The red dot in the compact Island while recording.
struct RecordingDot: View {
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 9, height: 9)
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel(Text("Recording"))
    }
}

/// "1:05", updated every second while it's on screen.
struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(KKFormat.clock(max(context.date.timeIntervalSince(since), 0)))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

struct RecordingPage: View {
    let controller: ScreenToolsController
    let startedAt: Date

    var body: some View {
        HStack(spacing: KKSpacing.m) {
            RecordingDot()
            VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                Text("Recording")
                    .font(.headline)
                    .foregroundStyle(.white)
                ElapsedTime(since: startedAt)
                    .font(.callout)
            }
            Spacer()
            Button {
                Task { await controller.stopRecording() }
            } label: {
                Label(String(localized: "Stop"), systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

struct RecordingSavedPage: View {
    let controller: ScreenToolsController

    var body: some View {
        if let url = controller.lastRecordingURL {
            HStack(spacing: KKSpacing.m) {
                KKThumbnail(url: url, maxPixelSize: 200)
                    .frame(width: 90, height: 60)
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                VStack(alignment: .leading, spacing: KKSpacing.s) {
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: KKSpacing.xs) {
                        IslandActionButton(String(localized: "Play"), symbol: "play.fill") {
                            NSWorkspace.shared.open(url)
                        }
                        IslandActionButton(String(localized: "Show"), symbol: "folder") {
                            controller.reveal(url)
                        }
                        IslandActionButton(String(localized: "Copy"), symbol: "doc.on.doc") {
                            controller.context.pasteboard.write(PasteboardContents(fileURLs: [url], types: ["public.file-url"]))
                        }
                        if controller.canShelve {
                            IslandActionButton(String(localized: "Shelf"), symbol: "tray.and.arrow.down") {
                                Task { await controller.shelve([.file(url)]) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A screenshot pinned above other windows. Drag it to move it; double-click or ✕ closes it.
struct PinnedScreenshotView: View {
    let image: CapturedImage
    let copy: @MainActor () -> Void
    let close: @MainActor () -> Void

    @State private var hovering = false
    @State private var opacity = 1.0

    var body: some View {
        Image(decorative: image.image, scale: image.scale)
            .resizable()
            .interpolation(.high)
            .opacity(opacity)
            .overlay(alignment: .topLeading) {
                if hovering {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(KKSpacing.xs)
                    .accessibilityLabel(Text("Close"))
                }
            }
            .overlay(Rectangle().strokeBorder(.white.opacity(hovering ? 0.5 : 0), lineWidth: 1))
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { close() }
            .contextMenu {
                Button(String(localized: "Copy"), action: copy)
                Picker(String(localized: "Opacity"), selection: $opacity) {
                    Text("100%").tag(1.0)
                    Text("75%").tag(0.75)
                    Text("50%").tag(0.5)
                    Text("25%").tag(0.25)
                }
                Divider()
                Button(String(localized: "Close"), action: close)
            }
    }
}
