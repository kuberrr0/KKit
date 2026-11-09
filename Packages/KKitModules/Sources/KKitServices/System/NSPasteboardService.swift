import AppKit
import ApplicationServices
import KKitServicesAPI

/// The general pasteboard. Polls `changeCount` every 0.4 s, and only while something
/// subscribes to `changes()` (macOS has no change notification).
@MainActor
public final class NSPasteboardService: PasteboardService {
    /// Marks KKit's own writes so Clipboard History can tell them apart.
    static let kkitMarker = NSPasteboard.PasteboardType("com.kv.kkit.marker")
    static let sourceMarker = NSPasteboard.PasteboardType("org.nspasteboard.source")

    private let pasteboard: NSPasteboard
    private let broadcast = Broadcast<PasteboardChange>()
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pollInterval: TimeInterval

    public init(pasteboard: NSPasteboard = .general, pollInterval: TimeInterval = 0.4) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
        broadcast.onFirstSubscriber = { [weak self] in self?.startPolling() }
        broadcast.onLastSubscriberGone = { [weak self] in self?.stopPolling() }
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func changes() -> AsyncStream<PasteboardChange> {
        lastChangeCount = pasteboard.changeCount
        return broadcast.stream(initial: makeChange())
    }

    public func read() -> PasteboardContents {
        Self.contents(of: pasteboard)
    }

    public func write(_ contents: PasteboardContents) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let rtf = contents.rtf {
            item.setData(rtf, forType: .rtf)
        }
        if let html = contents.html {
            item.setString(html, forType: .html)
        }
        if let image = contents.image {
            let type = contents.imageType.map { NSPasteboard.PasteboardType($0) } ?? .tiff
            item.setData(image, forType: type)
        }
        if let url = contents.url {
            item.setString(url.absoluteString, forType: .URL)
        }
        if let color = contents.color {
            let nsColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: true) {
                item.setData(data, forType: .color)
            }
        }
        if let string = contents.string ?? contents.url?.absoluteString ?? contents.color?.hex {
            item.setString(string, forType: .string)
        }
        item.setData(Data(), forType: Self.kkitMarker)
        var objects: [any NSPasteboardWriting] = []
        if contents.fileURLs.isEmpty {
            objects.append(item)
        } else {
            // Files go as one item each so Finder pastes all of them.
            objects.append(contentsOf: contents.fileURLs.map { $0 as NSURL })
            let marker = NSPasteboardItem()
            marker.setData(Data(), forType: Self.kkitMarker)
            if let string = contents.string {
                marker.setString(string, forType: .string)
            }
            objects.append(marker)
        }
        pasteboard.writeObjects(objects)
        // Don't report our own write as a change from another app.
        if broadcast.hasSubscribers {
            poll()
        }
    }

    public var canPaste: Bool { AXIsProcessTrusted() }

    public func paste() async throws {
        guard AXIsProcessTrusted() else { throw PasteError.needsAccessibility }
        // Let the Floating Bar or picker hand focus back to the app in front.
        try? await Task.sleep(for: .milliseconds(120))
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Polling

    private func startPolling() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = pollInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        broadcast.send(makeChange())
    }

    private func makeChange() -> PasteboardChange {
        let types = pasteboard.types ?? []
        let front = NSWorkspace.shared.frontmostApplication
        let marked = pasteboard.string(forType: Self.sourceMarker)
        let sourceID = (marked?.isEmpty == false ? marked : nil) ?? front?.bundleIdentifier
        let sourceName: String?
        if let marked, !marked.isEmpty, marked != front?.bundleIdentifier {
            sourceName = NSRunningApplication.runningApplications(withBundleIdentifier: marked).first?.localizedName
        } else {
            sourceName = front?.localizedName
        }
        return PasteboardChange(
            changeCount: pasteboard.changeCount,
            contents: Self.contents(of: pasteboard),
            sourceBundleID: sourceID,
            sourceAppName: sourceName,
            isFromKKit: types.contains(Self.kkitMarker)
        )
    }

    static func contents(of pasteboard: NSPasteboard) -> PasteboardContents {
        let types = pasteboard.types ?? []
        var contents = PasteboardContents(types: types.map(\.rawValue))
        // Concealed (password) copies are reported by type only; nothing is read.
        guard !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) else {
            return contents
        }
        contents.string = pasteboard.string(forType: .string)
        if types.contains(.rtf) {
            contents.rtf = pasteboard.data(forType: .rtf)
        }
        if types.contains(.html) {
            contents.html = pasteboard.string(forType: .html)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        contents.fileURLs = urls.filter(\.isFileURL)
        if let link = urls.first(where: { !$0.isFileURL }) {
            contents.url = link
        }
        if contents.fileURLs.isEmpty {
            if types.contains(.png), let data = pasteboard.data(forType: .png) {
                contents.image = data
                contents.imageType = NSPasteboard.PasteboardType.png.rawValue
            } else if types.contains(.tiff), let data = pasteboard.data(forType: .tiff) {
                contents.image = data
                contents.imageType = NSPasteboard.PasteboardType.tiff.rawValue
            }
        }
        if types.contains(.color), let color = NSColor(from: pasteboard)?.usingColorSpace(.sRGB) {
            contents.color = RGBAColor(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent),
                alpha: Double(color.alphaComponent)
            )
        }
        return contents
    }
}
