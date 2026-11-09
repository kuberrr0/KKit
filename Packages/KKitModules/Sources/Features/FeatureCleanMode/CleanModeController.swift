import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import Observation
import SwiftUI

/// What Clean Mode locks.
enum CleanModeKind: String, Codable, CaseIterable, Sendable {
    /// The keyboard; the mouse still works, to click Unlock.
    case keyboard
    /// Keyboard, trackpad and mouse; only the countdown unlocks.
    case everything

    var title: String {
        switch self {
        case .keyboard: String(localized: "Keyboard only")
        case .everything: String(localized: "Keyboard, trackpad and mouse")
        }
    }
}

enum CleanModeSettings {
    static let defaultKind = SettingKey("defaultKind", default: CleanModeKind.keyboard)
    /// Seconds until it unlocks by itself: 30, 60, 90 or 120.
    static let countdown = SettingKey("countdown", default: 60)

    static let countdownChoices = [30, 60, 90, 120]
}

enum CleanModeError: LocalizedError {
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            String(localized: "Clean Mode needs Accessibility to block keys. Allow it in Settings › Clean Mode.")
        }
    }
}

/// Locks input through the shared tap at `.safety` priority, so nothing else sees a key
/// while it's on. DESIGN.md §3.18.
@MainActor
@Observable
final class CleanModeController {
    /// The safety net: Clean Mode never lasts longer than this.
    static let maximumDuration: TimeInterval = 120

    private(set) var kind: CleanModeKind?
    private(set) var remaining: TimeInterval = 0
    var isLocked: Bool { kind != nil }

    private let input: FeatureInput
    private let overlays: any OverlayService
    private let settings: FeatureSettings
    private let detachesCursor: Bool
    @ObservationIgnored private var token: InputHandlerToken?
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var panels: [any OverlayHandle] = []
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// `detachesCursor` freezes the pointer in "everything" mode; tests turn it off.
    init(input: FeatureInput, overlays: any OverlayService, settings: FeatureSettings, detachesCursor: Bool = true) {
        self.input = input
        self.overlays = overlays
        self.settings = settings
        self.detachesCursor = detachesCursor
    }

    var countdown: TimeInterval {
        let seconds = TimeInterval(settings[CleanModeSettings.countdown])
        return min(max(seconds, 5), Self.maximumDuration)
    }

    func lock(_ kind: CleanModeKind? = nil, now: Date = Date()) throws {
        guard input.status == .running else { throw CleanModeError.inputUnavailable }
        let kind = kind ?? settings[CleanModeSettings.defaultKind]
        if isLocked {
            unlock()
        }
        self.kind = kind
        deadline = now.addingTimeInterval(countdown)
        remaining = countdown
        var interests = InputEventType.keyboard
        if kind == .everything {
            interests.formUnion(InputEventType.mouseButtons)
        }
        let token = input.add(priority: .safety, interests: interests) { [weak self] event in
            self?.decide(event) ?? .pass
        }
        self.token = token
        if kind == .everything {
            input.arm(InputEventType.mouseMotion, for: token)
            if detachesCursor {
                CGAssociateMouseAndMouseCursorPosition(0)
            }
        }
        showOverlays()
        startTimer()
    }

    func unlock() {
        timer?.cancel()
        timer = nil
        if let token {
            input.remove(token)
        }
        token = nil
        if kind == .everything, detachesCursor {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        kind = nil
        deadline = nil
        remaining = 0
        panels.forEach { $0.close() }
        panels = []
    }

    /// Counts down; unlocks once the time is up.
    func tick(now: Date = Date()) {
        guard let deadline else { return }
        remaining = max(deadline.timeIntervalSince(now), 0)
        if remaining <= 0 {
            unlock()
        }
    }

    // MARK: Private

    private func decide(_ event: InputEvent) -> InputDecision {
        guard let kind else { return .pass }
        switch event.type {
        case .keyUp:
            // Releasing a key types nothing, and letting it through stops apps
            // thinking the keys of the shortcut that started Clean Mode are still down.
            return .pass
        case .flagsChanged:
            // Same for letting go of every modifier.
            return event.modifiers.isEmpty && !event.isFunctionDown ? .pass : .consume
        case .keyDown, .systemDefined:
            return .consume
        default:
            return kind == .everything ? .consume : .pass
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.tick()
                if !self.isLocked { return }
            }
        }
    }

    private func showOverlays() {
        panels.forEach { $0.close() }
        panels = overlays.screens.map { screen in
            let configuration = OverlayConfiguration(
                level: .screenSaver,
                screen: .display(screen.id),
                placement: .fullScreen,
                acceptsKeyFocus: false,
                ignoresMouseEvents: false,
                hasShadow: false
            )
            let panel = overlays.makePanel(
                configuration,
                content: AnyView(CleanModeOverlayView(controller: self, showsDetails: screen.isMain))
            )
            panel.show()
            return panel
        }
    }
}
