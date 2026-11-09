import KKitCore
import KKitUI
import SwiftUI

/// The full-screen cover while Clean Mode is on. Every display gets one; the main one
/// has the countdown and the Unlock button.
struct CleanModeOverlayView: View {
    let controller: CleanModeController
    let showsDetails: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            if showsDetails {
                VStack(spacing: KKSpacing.l) {
                    Image(systemName: controller.kind == .everything ? "lock.fill" : "keyboard")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Text(Self.format(controller.remaining))
                        .font(.system(size: 44, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel(Text("Unlocks in \(Int(controller.remaining.rounded(.up))) seconds"))
                    if controller.kind == .keyboard {
                        Button {
                            controller.unlock()
                        } label: {
                            Text("Unlock")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, KKSpacing.xl)
                                .padding(.vertical, KKSpacing.s)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Text("The power button and Touch ID still work.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, KKSpacing.m)
                }
                .padding(KKSpacing.xl)
            }
        }
        .ignoresSafeArea()
    }

    private var title: String {
        controller.kind == .everything
            ? String(localized: "Everything locked — clean away")
            : String(localized: "Keyboard locked — clean away")
    }

    private var detail: String {
        controller.kind == .everything
            ? String(localized: "The keyboard, trackpad and mouse come back when the countdown ends.")
            : String(localized: "Click Unlock when you're done, or wait for the countdown.")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// Settings › Clean Mode.
struct CleanModeSettingsView: View {
    let controller: CleanModeController
    let inputStatus: @MainActor () -> InputTapStatusSummary
    let requestAccess: @MainActor () -> Void

    @Setting(CleanModeSettings.defaultKind) private var defaultKind
    @Setting(CleanModeSettings.countdown) private var countdown
    @State private var error: String?

    var body: some View {
        Group {
            if inputStatus() != .running {
                KKSection {
                    HStack {
                        Label(String(localized: "Clean Mode needs Accessibility to block keys."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "Allow…")) { requestAccess() }
                    }
                }
            }
            KKSection(
                String(localized: "Clean Mode"),
                footer: String(localized: "Locks keys (including media and brightness keys) so you can wipe the keyboard. It always unlocks by itself after 2 minutes.")
            ) {
                Picker(String(localized: "Lock"), selection: $defaultKind) {
                    ForEach(CleanModeKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker(String(localized: "Unlock after"), selection: $countdown) {
                    ForEach(CleanModeSettings.countdownChoices, id: \.self) { seconds in
                        Text("\(seconds) s").tag(seconds)
                    }
                }
                HStack {
                    Spacer()
                    Button(String(localized: "Start Clean Mode")) {
                        do {
                            try controller.lock()
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Whether the tap can block keys, for the settings banner.
enum InputTapStatusSummary: Equatable {
    case running
    case unavailable
}
