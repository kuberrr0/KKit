import SwiftUI

/// A toggle tile for the menu bar popover grid: symbol, title and a short state.
public struct KKTile: View {
    let title: String
    let symbol: String
    let detail: String?
    let isOn: Bool
    let action: () -> Void

    public init(_ title: String, symbol: String, detail: String? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KKSpacing.xs) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                Spacer(minLength: 0)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(KKSpacing.s)
            .frame(maxWidth: .infinity, minHeight: KKMetrics.tileHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
            )
            .contentShape(RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? (isOn ? String(localized: "On") : String(localized: "Off")))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
struct KKTile_Previews: PreviewProvider {
    static var previews: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
            KKTile("Awake", symbol: "cup.and.saucer", detail: "1h 20m", isOn: true) {}
            KKTile("Night", symbol: "moon.stars", detail: "70%", isOn: false) {}
        }
        .padding()
        .frame(width: 340)
    }
}
#endif
