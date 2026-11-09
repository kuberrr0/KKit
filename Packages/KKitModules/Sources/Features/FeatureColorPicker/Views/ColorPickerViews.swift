import KKitServicesAPI
import KKitUI
import SwiftUI

/// The left ear while a picked colour shows in the compact Island.
struct PickedSwatch: View {
    let color: RGBAColor

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

/// The Colours page in the expanded Island: the last colour in every format (click one
/// to copy it), Pick, and the recent colours.
struct ColorIslandPage: View {
    let controller: ColorPickerController

    @State private var copied: ColorFormat?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KKSpacing.xs), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            if let color = controller.current {
                HStack(alignment: .top, spacing: KKSpacing.m) {
                    RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                        .fill(color.swiftUIColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                                .strokeBorder(.white.opacity(0.25))
                        )
                        .frame(width: 68, height: 68)
                        .accessibilityLabel(Text(color.hex))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: KKSpacing.xs) {
                        ForEach(ColorFormat.allCases) { format in
                            formatButton(format, color: color)
                        }
                    }
                }
            } else {
                Text("Pick a colour anywhere on screen. It's copied straight away and kept here.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            }
            HStack(spacing: KKSpacing.s) {
                Button {
                    Task { await controller.pick() }
                } label: {
                    Label(String(localized: "Pick"), systemImage: "eyedropper")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controller.isPicking)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KKSpacing.xs) {
                        ForEach(controller.history.dropFirst(), id: \.hex) { color in
                            Button {
                                controller.copy(color, announce: false)
                                flash(controller.settings[ColorPickerSettings.format])
                            } label: {
                                KKSwatch(color.swiftUIColor, size: 18)
                            }
                            .buttonStyle(.plain)
                            .help(color.hex)
                            .contextMenu {
                                Button(String(localized: "Remove")) { controller.remove(color) }
                            }
                            .accessibilityLabel(Text(color.hex))
                        }
                    }
                }
            }
        }
    }

    private func formatButton(_ format: ColorFormat, color: RGBAColor) -> some View {
        let text = controller.string(color, format: format)
        return Button {
            controller.copy(color, format: format, announce: false)
            flash(format)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(copied == format ? String(localized: "Copied") : format.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(copied == format ? Color.accentColor : .white.opacity(0.6))
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KKSpacing.s)
            .padding(.vertical, KKSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: KKRadius.control))
        .help(text)
        .accessibilityLabel(Text("Copy as \(format.title): \(text)"))
    }

    private func flash(_ format: ColorFormat) {
        copied = format
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == format {
                copied = nil
            }
        }
    }
}

/// The Floating Bar preview pane (Tab) for a colour.
struct ColorPreview: View {
    let color: RGBAColor
    let controller: ColorPickerController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                .fill(color.swiftUIColor)
                .overlay(
                    RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15))
                )
                .frame(height: 96)
            ForEach(ColorFormat.allCases) { format in
                VStack(alignment: .leading, spacing: 1) {
                    Text(format.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.string(color, format: format))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ColorPickerSettingsView: View {
    let controller: ColorPickerController

    @Setting(ColorPickerSettings.format) private var format
    @Setting(ColorPickerSettings.lowercaseHex) private var lowercaseHex
    @Setting(ColorPickerSettings.showInIsland) private var showInIsland
    @Setting(ColorPickerSettings.showIslandPage) private var showIslandPage

    /// Shown as the example before anything has been picked.
    private static let sample = RGBAColor(red: 1, green: 136.0 / 255, blue: 0)

    private let swatchColumns = Array(repeating: GridItem(.fixed(22), spacing: KKSpacing.xs), count: 12)

    var body: some View {
        Group {
            KKSection(
                footer: String(localized: "Use the Pick Colour shortcut (⌃⌥P unless you change it in Shortcuts) or type “pick colour” in the Floating Bar. The loupe doesn't need Screen Recording. Type a colour such as #FF8800 or rgb(255 136 0) in the Floating Bar to convert it, or # on its own for your recent colours.")
            ) {
                KKRow(String(localized: "Pick a colour from the screen"), symbol: "eyedropper") {
                    Button(String(localized: "Pick Colour")) {
                        Task { await controller.pick() }
                    }
                    .disabled(controller.isPicking)
                }
                Picker(String(localized: "Copy as"), selection: $format) {
                    ForEach(ColorFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Toggle(String(localized: "Lowercase HEX"), isOn: $lowercaseHex)
                LabeledContent(
                    String(localized: "Example"),
                    value: ColorFormatter.string(controller.current ?? Self.sample, as: format, lowercaseHex: lowercaseHex)
                )
                .textSelection(.enabled)
            }
            KKSection(String(localized: "Island")) {
                Toggle(String(localized: "Show the picked colour in the Island"), isOn: $showInIsland)
                Toggle(String(localized: "Colours page in the expanded Island"), isOn: $showIslandPage)
            }
            KKSection(
                String(localized: "Recent Colours"),
                footer: controller.history.isEmpty ? nil : String(localized: "Click a colour to copy it again. Right-click to remove it.")
            ) {
                if controller.history.isEmpty {
                    Text("Colours you pick show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: KKSpacing.xs) {
                        ForEach(controller.history, id: \.hex) { color in
                            Button {
                                controller.copy(color)
                            } label: {
                                KKSwatch(color.swiftUIColor, size: 20)
                            }
                            .buttonStyle(.plain)
                            .help(color.hex)
                            .contextMenu {
                                Button(String(localized: "Remove")) { controller.remove(color) }
                            }
                            .accessibilityLabel(Text(color.hex))
                        }
                    }
                    HStack {
                        Spacer()
                        Button(String(localized: "Clear")) { controller.clearHistory() }
                    }
                }
            }
        }
    }
}
