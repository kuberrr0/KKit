import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation
import SwiftUI

/// A page in the Settings window.
public enum SettingsPage: Hashable, Sendable {
    case general
    case permissions
    case shortcuts
    case island
    case floatingBar
    case feature(FeatureID)
}

@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPage? = .general
}

/// The Settings window: a sidebar built from feature manifests, plus the General,
/// Permissions and Shortcuts pages.
@MainActor
public final class SettingsHost: NSObject {
    private let dependencies: HostDependencies
    private let floatingBar: FloatingBarHost?
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    public init(dependencies: HostDependencies, floatingBar: FloatingBarHost? = nil) {
        self.dependencies = dependencies
        self.floatingBar = floatingBar
        super.init()
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    /// Opens the window (creating it the first time), optionally at `page`.
    public func show(_ page: SettingsPage? = nil) {
        if let page {
            navigation.selection = page
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.performClose(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsRootView(
            dependencies: dependencies,
            floatingBar: floatingBar,
            navigation: navigation
        ))
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "KKit Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 540))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.center()
        _ = window.setFrameAutosaveName("KKitSettings")
        return window
    }
}

struct SettingsRootView: View {
    let dependencies: HostDependencies
    let floatingBar: FloatingBarHost?
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        List(selection: $navigation.selection) {
            Section {
                Label(String(localized: "General"), systemImage: "gearshape")
                    .tag(SettingsPage.general)
                Label {
                    HStack {
                        Text("Permissions")
                        if !dependencies.features.missingPermissions.isEmpty {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel(Text("Missing permissions"))
                        }
                    }
                } icon: {
                    Image(systemName: "hand.raised")
                }
                .tag(SettingsPage.permissions)
                Label(String(localized: "Shortcuts"), systemImage: "keyboard")
                    .tag(SettingsPage.shortcuts)
                Label(String(localized: "Island"), systemImage: "capsule")
                    .tag(SettingsPage.island)
                if floatingBar != nil {
                    Label(String(localized: "Floating Bar"), systemImage: "magnifyingglass")
                        .tag(SettingsPage.floatingBar)
                }
            }

            Section(String(localized: "Features")) {
                if dependencies.features.manifests.isEmpty {
                    Text("No features installed yet")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(dependencies.features.manifests) { manifest in
                    FeatureSidebarRow(manifest: manifest, state: dependencies.features.state(of: manifest.id))
                        .tag(SettingsPage.feature(manifest.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general:
            GeneralSettingsView(dependencies: dependencies)
        case .permissions:
            PermissionsSettingsView(dependencies: dependencies)
        case .shortcuts:
            ShortcutsSettingsView(dependencies: dependencies)
        case .island:
            IslandSettingsView()
                .environment(\.featureSettings, FeatureSettings(featureID: IslandSettings.owner, store: dependencies.settings))
        case .floatingBar:
            if let floatingBar {
                FloatingBarSettingsView(dependencies: dependencies, host: floatingBar)
                    .environment(\.featureSettings, floatingBar.floatingBarSettings)
            }
        case .feature(let id):
            if let manifest = dependencies.features.manifest(for: id) {
                FeatureSettingsView(dependencies: dependencies, manifest: manifest)
                    .id(id)
            } else {
                Text("This feature is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FeatureSidebarRow: View {
    let manifest: FeatureManifest
    let state: FeatureState

    var body: some View {
        Label {
            HStack {
                Text(manifest.name)
                Spacer()
                switch state {
                case .waitingForPermissions, .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("Needs attention"))
                case .running:
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(Text("On"))
                default:
                    EmptyView()
                }
            }
        } icon: {
            KKFeatureIcon(manifest.symbol, size: 18)
        }
    }
}
