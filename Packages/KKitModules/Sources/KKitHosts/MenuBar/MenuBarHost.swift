import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The KKit status item and its popover: header, then the Quick Toggles grid filled
/// from every running feature's `quickToggles`. Volume, brightness and stats rows join
/// it as those features arrive.
@MainActor
public final class MenuBarHost: NSObject {
    private let dependencies: HostDependencies
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

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
            dismiss: { [weak self] in self?.closePopover() }
        ))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    public var isPopoverShown: Bool { popover.isShown }

    public func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
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
}

struct MenuBarContentView: View {
    let dependencies: HostDependencies
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KKSpacing.s), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            header
            toggles
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

    static func detail(for state: CommandState) -> String? {
        switch state {
        case .on: String(localized: "On")
        case .off: String(localized: "Off")
        case .value(let text): text
        }
    }
}
