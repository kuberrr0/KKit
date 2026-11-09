import SwiftUI

/// The form every Settings page uses, so all panes look alike.
public struct KKForm<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
    }
}

/// A titled section in a `KKForm`, with an optional footer note.
public struct KKSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        Section {
            content
        } header: {
            if let title {
                Text(title)
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A small coloured status label: "Granted", "Not allowed", "Failed".
public struct KKStatusBadge: View {
    public enum Tone: Sendable {
        case positive, warning, negative, neutral
    }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, KKSpacing.s)
            .padding(.vertical, KKSpacing.xxs)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .positive: .green
        case .warning: .orange
        case .negative: .red
        case .neutral: .secondary
        }
    }
}

#if DEBUG
struct KKForm_Previews: PreviewProvider {
    static var previews: some View {
        KKForm {
            KKSection("General", footer: "Shown in the menu bar.") {
                Toggle("Launch at login", isOn: .constant(true))
                KKRow("Accessibility", symbol: "accessibility") { KKStatusBadge("Granted", tone: .positive) }
            }
        }
        .frame(width: 420, height: 240)
    }
}
#endif
