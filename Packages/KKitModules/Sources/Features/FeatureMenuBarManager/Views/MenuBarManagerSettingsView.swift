import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Settings › Menu Bar Manager.
struct MenuBarManagerSettingsView: View {
    let controller: MenuBarManagerController

    @Setting(MenuBarManagerSettings.revealOn) private var revealOn
    @Setting(MenuBarManagerSettings.openStyle) private var openStyle
    @Setting(MenuBarManagerSettings.autoHideDelay) private var autoHideDelay
    @Setting(MenuBarManagerSettings.showAllWithCommand) private var showAllWithCommand
    @Setting(MenuBarManagerSettings.alwaysHiddenSection) private var alwaysHiddenSection
    @Setting(MenuBarManagerSettings.showsIconImages) private var showsIconImages
    @State private var spacing: MenuBarIconSpacing = .system

    var body: some View {
        Group {
            KKSection(
                String(localized: "Showing hidden icons"),
                footer: String(localized: "To hide icons, hold ⌘ over the menu bar (or click the chevron first), then drag them left of the chevron. ⌥-click the chevron to show every icon.")
            ) {
                Picker(String(localized: "Show them by"), selection: $revealOn) {
                    ForEach(RevealTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                Picker(String(localized: "Show them in"), selection: $openStyle) {
                    ForEach(OpenStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker(String(localized: "Hide them again after"), selection: $autoHideDelay) {
                    ForEach(MenuBarManagerSettings.autoHideChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? String(localized: "Never") : "\(seconds) s").tag(seconds)
                    }
                }
                Toggle(String(localized: "Show every icon while ⌘ is held over the menu bar"), isOn: $showAllWithCommand)
                if showAllWithCommand, !controller.hasAccessibility {
                    permissionRow(
                        String(localized: "Holding ⌘ needs Accessibility."),
                        action: controller.requestAccessibility
                    )
                }
                Toggle(String(localized: "Add an Always Hidden section"), isOn: $alwaysHiddenSection)
            }

            KKSection(
                String(localized: "Icons"),
                footer: String(localized: "Drag icons between the lists, or use an icon's ⋯ menu. KKit moves them with a ⌘-drag of its own, so the pointer may jump for a moment.")
            ) {
                if !controller.hasAccessibility {
                    permissionRow(
                        String(localized: "Allow Accessibility to list and open menu bar icons."),
                        action: controller.requestAccessibility
                    )
                } else {
                    ForEach(sections, id: \.self) { section in
                        IconSectionList(controller: controller, section: section, sections: sections)
                    }
                    HStack {
                        if controller.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        if let error = controller.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button(String(localized: "Show All in Menu Bar")) { controller.showAll() }
                        Button(String(localized: "Refresh")) {
                            Task { await controller.refreshIcons() }
                        }
                    }
                }
            }

            KKSection(
                String(localized: "Drop-down bar"),
                footer: String(localized: "Without pictures, the drop-down bar shows each app's icon.")
            ) {
                Toggle(String(localized: "Show pictures of the icons"), isOn: $showsIconImages)
                if showsIconImages, !controller.canTakePictures {
                    permissionRow(
                        String(localized: "Pictures of icons need Screen Recording."),
                        action: controller.requestScreenRecording
                    )
                }
            }

            KKSection(
                String(localized: "Spacing"),
                footer: String(localized: "Apps use the new spacing the next time they open. Log out and back in to apply it everywhere.")
            ) {
                Picker(String(localized: "Space between icons"), selection: $spacing) {
                    ForEach(MenuBarIconSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.title).tag(spacing)
                    }
                }
                .onChange(of: spacing) { _, newValue in
                    if newValue != controller.service.iconSpacing {
                        controller.service.setIconSpacing(newValue)
                    }
                }
            }

            KKSection(
                String(localized: "Chevron and dividers"),
                footer: String(localized: "Puts the chevron and dividers back at the left end of the icons. Every icon is shown again until you hide some.")
            ) {
                if controller.service.dividersOutOfOrder {
                    Label(
                        String(localized: "The Always Hidden divider is right of the chevron, so sections can't be told apart."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button(String(localized: "Reset Chevron and Dividers")) {
                        controller.service.resetDividers()
                        Task { await controller.refreshIcons() }
                    }
                }
            }

            if Self.hasSystemMenuBarSettings {
                KKSection(
                    footer: String(localized: "macOS 26 can also take an app's icons out of the menu bar for good, in System Settings › Menu Bar.")
                ) {
                    HStack {
                        Spacer()
                        Button(String(localized: "Open Menu Bar Settings…")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .task {
            spacing = controller.service.iconSpacing
            await controller.refreshIcons()
        }
        .onChange(of: controller.hasAccessibility) { _, granted in
            if granted {
                Task { await controller.refreshIcons() }
            }
        }
    }

    private var sections: [MenuBarIconSection] {
        controller.service.hasAlwaysHiddenSection ? MenuBarIconSection.allCases : [.shown, .hidden]
    }

    private func permissionRow(_ text: String, action: @escaping @MainActor () -> Void) -> some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button(String(localized: "Allow…")) { action() }
        }
    }

    static var hasSystemMenuBarSettings: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }
}

/// One section's icons, left to right, as a drop target for icons from the others.
struct IconSectionList: View {
    let controller: MenuBarManagerController
    let section: MenuBarIconSection
    let sections: [MenuBarIconSection]
    @State private var isTargeted = false

    var body: some View {
        let icons = controller.icons(in: section)
        VStack(alignment: .leading, spacing: KKSpacing.xs) {
            Text(section.title)
                .font(.callout.weight(.semibold))
            if icons.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, KKSpacing.xs)
            } else {
                ForEach(icons) { icon in
                    row(icon)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KKSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: KKRadius.row)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            Task { await controller.move(id: id, to: section) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var emptyText: String {
        switch section {
        case .shown: String(localized: "No icons.")
        case .hidden: String(localized: "Nothing hidden. Drag icons here, or ⌘-drag them left of ‹ in the menu bar.")
        case .alwaysHidden: String(localized: "Nothing always hidden. Drag icons here to keep them out of the menu bar.")
        }
    }

    private func row(_ icon: MenuBarIcon) -> some View {
        HStack(spacing: KKSpacing.s) {
            MenuBarIconImage(icon: icon, image: controller.images[icon.id])
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(icon.displayName)
                if let detail = icon.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !icon.isOnScreen, icon.section == .shown {
                KKStatusBadge(String(localized: "Behind the notch"), tone: .warning)
            }
            if icon.canMove {
                Menu {
                    ForEach(sections.filter { $0 != section }, id: \.self) { target in
                        Button(String(localized: "Move to \(target.title)")) {
                            Task { await controller.move(icon, to: target) }
                        }
                    }
                    Divider()
                    Button(String(localized: "Open")) {
                        Task { try? await controller.open(icon) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Actions for \(icon.displayName)"))
            } else {
                Text("Fixed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text("macOS keeps this icon where it is."))
            }
        }
        .contentShape(Rectangle())
        .draggable(icon.id) {
            Label(icon.displayName, systemImage: "menubar.rectangle")
        }
    }
}
