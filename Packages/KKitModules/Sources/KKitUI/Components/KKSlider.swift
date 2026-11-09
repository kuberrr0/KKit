import SwiftUI

/// A labelled slider with a symbol and a percentage readout, as in the menu bar
/// popover (volume, brightness).
public struct KKSlider: View {
    let symbol: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    public init(
        _ label: String,
        symbol: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        format: @escaping (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    ) {
        self.label = label
        self.symbol = symbol
        self._value = value
        self.range = range
        self.format = format
    }

    public var body: some View {
        HStack(spacing: KKSpacing.s) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)
                .accessibilityHidden(true)
            Slider(value: $value, in: range)
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(format(value))
            Text(format(value))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
struct KKSlider_Previews: PreviewProvider {
    static var previews: some View {
        KKSlider("Volume", symbol: "speaker.wave.2", value: .constant(0.62))
            .padding()
            .frame(width: 340)
    }
}
#endif
