import AppKit
import KKitCore
import KKitUI
import ServiceManagement
import SwiftUI

/// Launch at login, using `SMAppService.mainApp`.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Applies the "Show in Dock" setting.
@MainActor
public enum DockIconPolicy {
    public static func apply(showDockIcon: Bool) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}

struct GeneralSettingsView: View {
    let dependencies: HostDependencies
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        KKForm {
            KKSection(String(localized: "Startup")) {
                Toggle(String(localized: "Launch KKit at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(String(localized: "Show KKit in the Dock"), isOn: showDockIcon)
            }

            KKSection(String(localized: "About")) {
                LabeledContent(String(localized: "Version"), value: Self.version)
                LabeledContent(String(localized: "Features"), value: "\(dependencies.features.runningFeatures.count) of \(dependencies.features.manifests.count) on")
            }
        }
    }

    private var showDockIcon: Binding<Bool> {
        let settings = dependencies.settings
        return Binding(
            get: { settings.value(for: AppSettingKeys.showDockIcon, default: false) },
            set: { newValue in
                settings.set(newValue, for: AppSettingKeys.showDockIcon)
                DockIconPolicy.apply(showDockIcon: newValue)
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
