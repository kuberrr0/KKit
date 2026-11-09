import SwiftUI

/// A feature's SF Symbol on a rounded tinted square, as used in the Settings sidebar.
public struct KKFeatureIcon: View {
    let symbol: String
    let size: CGFloat
    let tint: Color

    public init(_ symbol: String, size: CGFloat = KKMetrics.featureIconSize, tint: Color = .accentColor) {
        self.symbol = symbol
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

#if DEBUG
struct KKFeatureIcon_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            KKFeatureIcon("moon.stars")
            KKFeatureIcon("speaker.wave.2", size: 32, tint: .pink)
        }
        .padding()
    }
}
#endif
