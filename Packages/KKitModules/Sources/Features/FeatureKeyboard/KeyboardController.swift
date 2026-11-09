import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation
import SwiftUI

/// The Hyper key, key bindings, leader sequences and the cheat sheet, on the shared
/// input tap. DESIGN.md §3.9.
@MainActor
@Observable
final class KeyboardController {
    /// Keys typed so far in a leader sequence; `nil` when no sequence is in progress.
    private(set) var leaderTyped: String?
    private(set) var isCheatSheetVisible = false

    private let context: FeatureContext
    private let settings: FeatureSettings
    @ObservationIgnored private var machine = HyperKeyMachine(keyCode: CapsLockRemap.f18.keyCode)
    @ObservationIgnored private var token: InputHandlerToken?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var cheatSheetTask: Task<Void, Never>?
    @ObservationIgnored private var leaderTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var leaderPanel: (any OverlayHandle)?
    @ObservationIgnored private var cheatSheetPanel: (any OverlayHandle)?
    /// Key-ups to swallow because their key-down ran something.
    @ObservationIgnored private var swallowedKeyUps: Set<Int> = []
    // Settings, cached because the tap reads them on every key.
    @ObservationIgnored private var hyperEnabled = false
    @ObservationIgnored private var bindings: [Shortcut: KeyBinding] = [:]
    @ObservationIgnored private var leaderKey: Shortcut?
    @ObservationIgnored private var leaderEnabled = true
    @ObservationIgnored private var sequences: [LeaderSequence] = []

    init(context: FeatureContext) {
        self.context = context
        self.settings = context.settings
    }

    private var runner: KeyActionRunner {
        let island = context.island
        return KeyActionRunner(
            commandRunner: context.commandRunner,
            input: context.input,
            log: context.log
        ) { message in
            island.showHUD(IslandHUD(id: "keyboard.error", symbol: "keyboard.badge.exclamationmark", title: message, tint: .warning, duration: 3))
        }
    }

    var inputStatus: InputTapStatus { context.input.status }

    // MARK: Lifecycle

    func start() {
        token = context.input.add(priority: .high, interests: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event) ?? .pass
        }
        watch(KeyboardSettings.hyperEnabled) { controller, enabled in
            controller.hyperEnabled = enabled
            controller.machine.reset()
            Task { await controller.context.input.service.setCapsLockRemap(enabled ? .f18 : nil) }
        }
        watch(KeyboardSettings.bindings) { controller, bindings in
            controller.bindings = Dictionary(
                bindings.compactMap { binding in binding.trigger.map { ($0, binding) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
        watch(KeyboardSettings.leaderKey) { controller, key in controller.leaderKey = key }
        watch(KeyboardSettings.leaderEnabled) { controller, enabled in controller.leaderEnabled = enabled }
        watch(KeyboardSettings.sequences) { controller, sequences in controller.sequences = sequences }
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        if let token {
            context.input.remove(token)
        }
        token = nil
        endLeader()
        hideCheatSheet()
        leaderPanel?.close()
        leaderPanel = nil
        cheatSheetPanel?.close()
        cheatSheetPanel = nil
        machine.reset()
        // Give Caps Lock back.
        await context.input.service.setCapsLockRemap(nil)
    }

    private func watch<Value: Codable & Sendable>(
        _ key: SettingKey<Value>,
        _ apply: @escaping @MainActor (KeyboardController, Value) -> Void
    ) {
        let stream = settings.changes(of: key)
        // The first value arrives straight away, so apply it now too.
        apply(self, settings[key])
        tasks.append(Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                apply(self, value)
            }
        })
    }

    // MARK: The tap handler (must be quick)

    func handle(_ event: InputEvent) -> InputDecision {
        let keyCode = event.keyCode
        let isDown = event.type == .keyDown

        if hyperEnabled {
            switch machine.handle(keyCode: keyCode, isDown: isDown, isRepeat: event.isAutoRepeat, at: Date()) {
            case .pressed:
                if leaderTyped == nil {
                    scheduleCheatSheet()
                }
                return .consume
            case .released(let tapped):
                cancelCheatSheet()
                if tapped, leaderTyped == nil, settings[KeyboardSettings.capsLockTap] == .escape {
                    context.input.tapKey(Shortcut.Key.escape)
                }
                return .consume
            case .swallow:
                return .consume
            case .addHyper:
                cancelCheatSheet()
                event.cgEvent.flags = event.cgEvent.flags.union(InputEvent.flags(from: .hyper))
            case .passThrough:
                break
            }
        }

        guard isDown else {
            return swallowedKeyUps.remove(keyCode) != nil ? .consume : .pass
        }
        if leaderTyped != nil {
            swallowedKeyUps.insert(keyCode)
            if !event.isAutoRepeat {
                leaderKeyDown(event)
            }
            return .consume
        }
        // Recording a key in KKit's own Settings: let the recorder have it.
        guard NSApp?.isActive != true else { return .pass }

        let trigger = Shortcut(keyCode: keyCode, modifiers: event.modifiers)
        if leaderEnabled, let leaderKey, trigger == leaderKey {
            swallowedKeyUps.insert(keyCode)
            if !event.isAutoRepeat {
                beginLeader()
            }
            return .consume
        }
        if let binding = bindings[trigger] {
            swallowedKeyUps.insert(keyCode)
            if !event.isAutoRepeat {
                let runner = runner
                // Run after the tap returns, so opening apps never delays input.
                Task { @MainActor in runner.run(binding.action, secondPress: binding.secondPress) }
            }
            return .consume
        }
        return .pass
    }

    // MARK: Leader sequences

    func beginLeader() {
        guard !sequences.isEmpty else {
            NSSound.beep()
            return
        }
        hideCheatSheet()
        leaderTyped = ""
        showLeaderPanel()
        restartLeaderTimeout(exact: nil)
    }

    func endLeader() {
        leaderTimeoutTask?.cancel()
        leaderTimeoutTask = nil
        leaderTyped = nil
        leaderPanel?.hide()
    }

    private func leaderKeyDown(_ event: InputEvent) {
        if event.keyCode == Shortcut.Key.escape {
            endLeader()
            return
        }
        guard let character = Self.character(for: event) else { return }
        let typed = (leaderTyped ?? "") + character
        switch LeaderMatcher.step(typed, sequences: sequences) {
        case .run(let sequence):
            endLeader()
            let runner = runner
            Task { @MainActor in runner.run(sequence.action) }
        case .waiting(let exact, _):
            leaderTyped = typed
            showLeaderPanel()
            restartLeaderTimeout(exact: exact)
        case .noMatch:
            NSSound.beep()
            endLeader()
        }
    }

    private func restartLeaderTimeout(exact: LeaderSequence?) {
        leaderTimeoutTask?.cancel()
        let timeout = min(max(settings[KeyboardSettings.leaderTimeout], 0.5), 10)
        leaderTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            self.endLeader()
            if let exact {
                self.runner.run(exact.action)
            }
        }
    }

    /// The character a key types, ignoring ⌃⌥⇧⌘ (the leader key often has Hyper held).
    private static func character(for event: InputEvent) -> String? {
        if let characters = NSEvent(cgEvent: event.cgEvent)?.charactersIgnoringModifiers?.lowercased(),
           let first = characters.first, !first.isWhitespace, !(first.unicodeScalars.first?.properties.generalCategory == .control) {
            return String(first)
        }
        let name = KKKeyNames.name(forKeyCode: event.keyCode)
        return name.count == 1 ? name.lowercased() : nil
    }

    private func showLeaderPanel() {
        let view = AnyView(LeaderView(controller: self))
        if let leaderPanel {
            leaderPanel.setContent(view)
        } else {
            leaderPanel = context.overlays.makePanel(
                OverlayConfiguration(
                    level: .screenSaver,
                    screen: .withCursor,
                    placement: .topCenter(size: CGSize(width: 420, height: 260), offset: 80),
                    ignoresMouseEvents: true,
                    hasShadow: false
                ),
                content: view
            )
        }
        leaderPanel?.show()
    }

    /// What the leader panel lists: the next key and the sequence's title.
    var leaderOptions: [(key: String, title: String)] {
        guard let typed = leaderTyped else { return [] }
        let candidates = typed.isEmpty ? sequences : sequences.filter { $0.normalizedKeys.hasPrefix(typed) }
        return LeaderMatcher.nextKeys(after: typed, candidates: candidates)
    }

    // MARK: Cheat sheet

    private func scheduleCheatSheet() {
        cheatSheetTask?.cancel()
        guard settings[KeyboardSettings.cheatSheetEnabled] else { return }
        let delay = min(max(settings[KeyboardSettings.cheatSheetDelay], 0.3), 5)
        cheatSheetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.machine.isHeld else { return }
            self.machine.markUsed()
            self.showCheatSheet()
        }
    }

    private func cancelCheatSheet() {
        cheatSheetTask?.cancel()
        cheatSheetTask = nil
        hideCheatSheet()
    }

    func toggleCheatSheet() {
        if isCheatSheetVisible {
            hideCheatSheet()
        } else {
            showCheatSheet()
            // Shown by command: hide it again after a while.
            cheatSheetTask?.cancel()
            cheatSheetTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.hideCheatSheet()
            }
        }
    }

    func showCheatSheet() {
        let entries = cheatSheetEntries()
        let rows = max(entries.count, 1)
        let height = min(CGFloat(rows) * 26 + 90, 640)
        let view = AnyView(CheatSheetView(entries: entries))
        let configuration = OverlayConfiguration(
            level: .screenSaver,
            screen: .withCursor,
            placement: .centered(size: CGSize(width: 520, height: height)),
            ignoresMouseEvents: true,
            hasShadow: true
        )
        if let cheatSheetPanel {
            cheatSheetPanel.setContent(view)
            cheatSheetPanel.setConfiguration(configuration)
        } else {
            cheatSheetPanel = context.overlays.makePanel(configuration, content: view)
        }
        cheatSheetPanel?.show()
        isCheatSheetVisible = true
    }

    func hideCheatSheet() {
        guard isCheatSheetVisible else { return }
        cheatSheetPanel?.hide()
        isCheatSheetVisible = false
    }

    /// Hyper bindings, the leader key, and KKit commands bound to Hyper.
    func cheatSheetEntries() -> [CheatSheetEntry] {
        let titles = Dictionary(
            context.commandRunner.commandList.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        var entries: [CheatSheetEntry] = settings[KeyboardSettings.bindings].compactMap { binding in
            guard let trigger = binding.trigger else { return nil }
            return CheatSheetEntry(
                keys: KKKeyNames.string(for: trigger),
                title: binding.action.summary { titles[$0] },
                symbol: binding.action.kind.symbol
            )
        }
        if settings[KeyboardSettings.leaderEnabled], let leaderKey = settings[KeyboardSettings.leaderKey],
           !settings[KeyboardSettings.sequences].isEmpty {
            entries.append(CheatSheetEntry(
                keys: KKKeyNames.string(for: leaderKey),
                title: String(localized: "Leader sequences"),
                symbol: "text.cursor"
            ))
        }
        let hotkeys = context.hotkeys
        for command in context.commandRunner.commandList {
            guard let shortcut = hotkeys.shortcut(for: command.id), shortcut.modifiers == .hyper else { continue }
            entries.append(CheatSheetEntry(keys: KKKeyNames.string(for: shortcut), title: command.title, symbol: command.symbol))
        }
        return entries.sorted { $0.keys.localizedStandardCompare($1.keys) == .orderedAscending }
    }
}

struct CheatSheetEntry: Hashable, Identifiable {
    var keys: String
    var title: String
    var symbol: String

    var id: String { keys + title }
}

extension KeyboardController {
    /// For the command picker in Settings.
    var commandList: [CommandSummary] { context.commandRunner.commandList }

    func requestAccessibility() {
        let permissions = context.permissions
        Task { await permissions.request(.accessibility) }
    }
}
