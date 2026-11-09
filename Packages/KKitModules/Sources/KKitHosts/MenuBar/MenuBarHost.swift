import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation
import SwiftUI

/// Bumped each time the popover opens, so tiles that read system state (dark mode,
/// Wi-Fi) re-read it.
@MainActor
@Observable
final class MenuBarSession {
    var openCount = 0
}

/// The KKit status item and its popover: header, the Quick Toggles grid filled from
/// every running feature's `quickToggles`, then the features' `menuBarSections`
/// (volume, Night Shift, stats). It also owns the features' standalone status items
/// (`menuBarItems`).
@MainActor
public final class MenuBarHost: NSObject {
    private let dependencies: HostDependencies
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let session = MenuBarSession()
    private var featureItems: [String: FeatureStatusItem] = [:]

    public init(dependencies: HostDependencies) {
        self.dependencies = dependencies
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            // "MenuBarIcon" is the template PDF in the app's asset catalog
            // (Design/Icons/build-icons.js). The symbol is a fallback if it's missing.
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
            image?.isTemplate = true
            image?.accessibilityDescription = "KKit"
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let controller = NSHostingController(rootView: MenuBarContentView(
            dependencies: dependencies,
            session: session,
            dismiss: { [weak self] in self?.closePopover() }
        ))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        syncFeatureItems()
    }

    public var isPopoverShown: Bool { popover.isShown }

    public func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        session.openCount += 1
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    public func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    // MARK: Feature status items

    /// Creates and removes the features' status items to match what's running and
    /// visible, and runs again whenever anything it read changes.
    private func syncFeatureItems() {
        let features = dependencies.features
        let wanted: [KeyedMenuBarItem] = withObservationTracking {
            var result: [KeyedMenuBarItem] = []
            for feature in features.runningFeatures {
                let owner = type(of: feature).manifest.id
                for item in feature.menuBarItems where item.isVisible() {
                    result.append(KeyedMenuBarItem(id: "\(owner.rawValue).\(item.id)", item: item))
                }
            }
            return result
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.syncFeatureItems() }
        }

        let wantedKeys = Set(wanted.map(\.id))
        for (key, item) in featureItems where !wantedKeys.contains(key) {
            item.remove()
            featureItems[key] = nil
        }
        for entry in wanted where featureItems[entry.id] == nil {
            featureItems[entry.id] = FeatureStatusItem(item: entry.item, autosaveName: "kkit.\(entry.id)")
        }
    }
}

struct KeyedMenuBarItem: Identifiable {
    let id: String
    let item: MenuBarItem
}

struct KeyedMenuBarSection: Identifiable {
    let id: String
    let section: MenuBarSection
}

/// One feature-contributed status item: a SwiftUI label in the menu bar and an
/// optional popover.
@MainActor
final class FeatureStatusItem: NSObject {
    private let statusItem: NSStatusItem
    private let hostingView: PassthroughHostingView<StatusItemLabel>
    private var popover: NSPopover?

    init(item: MenuBarItem, autosaveName: String) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = autosaveName
        hostingView = PassthroughHostingView(rootView: StatusItemLabel(content: AnyView(EmptyView()), onWidth: { _ in }))
        super.init()

        hostingView.rootView = StatusItemLabel(content: item.makeLabel()) { [weak self] width in
            self?.statusItem.length = max(ceil(width), 8)
        }
        if let button = statusItem.button {
            button.setAccessibilityLabel(item.title)
            button.toolTip = item.title
            hostingView.frame = button.bounds
            hostingView.autoresizingMask = [.width, .height]
            button.addSubview(hostingView)
            if let makePopover = item.makePopover {
                let popover = NSPopover()
                popover.behavior = .transient
                popover.animates = true
                let controller = NSHostingController(rootView: makePopover())
                controller.sizingOptions = [.preferredContentSize]
                popover.contentViewController = controller
                self.popover = popover
                button.target = self
                button.action = #selector(clicked(_:))
            }
        }
    }

    func remove() {
        popover?.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func clicked(_ sender: Any?) {
        guard let popover, let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// A feature's menu bar label, measured so the status item fits it.
struct StatusItemLabel: View {
    let content: AnyView
    let onWidth: @MainActor (CGFloat) -> Void

    var body: some View {
        content
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .fixedSize()
            .padding(.horizontal, KKSpacing.xs)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onWidth(proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in onWidth(width) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A hosting view that lets clicks through to the status item button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct MenuBarContentView: View {
    let dependencies: HostDependencies
    let session: MenuBarSession
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KKSpacing.s), count: 4)

    var body: some View {
        // Re-read live tile states each time the popover opens.
        let _ = session.openCount
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            header
            toggles
            sections
        }
        .padding(KKSpacing.m)
        .frame(width: KKMetrics.menuBarPopoverWidth)
    }

    private var header: some View {
        HStack(spacing: KKSpacing.s) {
            Text("KKit")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
                dependencies.run(AppCommandID.openSettings, source: .menuBar)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(Text("Settings"))
            .accessibilityLabel(Text("Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(Text("Quit KKit"))
            .accessibilityLabel(Text("Quit KKit"))
        }
    }

    @ViewBuilder
    private var toggles: some View {
        let items = dependencies.features.runningFeatures.flatMap { $0.quickToggles }
        if items.isEmpty {
            VStack(spacing: KKSpacing.xs) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No quick toggles yet")
                    .font(.callout.weight(.medium))
                Text("Turn on features in Settings to add tiles here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KKSpacing.l)
        } else {
            LazyVGrid(columns: columns, spacing: KKSpacing.s) {
                ForEach(items) { toggle in
                    let state = toggle.state
                    KKTile(toggle.title, symbol: toggle.symbol, detail: Self.detail(for: state), isOn: state.isOn) {
                        dependencies.run(toggle.id, source: .menuBar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        ForEach(keyedSections) { item in
            Divider()
            item.section.makeView()
        }
    }

    private var keyedSections: [KeyedMenuBarSection] {
        var result: [KeyedMenuBarSection] = []
        for feature in dependencies.features.runningFeatures {
            let owner = type(of: feature).manifest.id
            for section in feature.menuBarSections {
                result.append(KeyedMenuBarSection(id: "\(owner.rawValue).\(section.id)", section: section))
            }
        }
        return result.sorted { $0.section.order < $1.section.order }
    }

    static func detail(for state: CommandState) -> String? {
        switch state {
        case .on: String(localized: "On")
        case .off: String(localized: "Off")
        case .value(let text): text
        }
    }
}
