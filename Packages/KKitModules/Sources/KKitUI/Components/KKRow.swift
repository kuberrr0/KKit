import SwiftUI

/// A list row: icon, title, optional subtitle, and a trailing accessory.
public struct KKRow<Accessory: View>: View {
    let symbol: String?
    let title: String
    let subtitle: String?
    let accessory: Accessory

    public init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: KKSpacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: KKSpacing.s)
            accessory
        }
        .padding(.vertical, KKSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

public extension KKRow where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.init(title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

#if DEBUG
struct KKRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            KKRow("Accessibility", subtitle: "Needed by Window Management", symbol: "accessibility") {
                Button("Open Settings") {}
            }
            KKRow("Launch at login", symbol: "power")
        }
        .padding()
        .frame(width: 360)
    }
}
#endif
