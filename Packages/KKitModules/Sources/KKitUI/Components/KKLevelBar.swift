import SwiftUI

/// A thin horizontal level, as in the volume HUD.
public struct KKLevelBar: View {
    let value: Double
    let tint: Color

    public init(value: Double, tint: Color = .white) {
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((min(max(value, 0), 1) * 100).rounded())) percent"))
    }
}

/// A small circular progress ring (timer ears, Pomodoro).
public struct KKProgressRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    public init(progress: Double, tint: Color = .accentColor, lineWidth: CGFloat = 2.5) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent"))
    }
}

/// A tiny line chart of recent values (0…1), for menu bar items and the stats strip.
public struct KKSparkline: View {
    let values: [Double]
    let tint: Color

    public init(_ values: [Double], tint: Color = .accentColor) {
        self.values = values
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(tint.opacity(0.25))
                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(min(max(value, 0), 1)) * size.height
            )
        }
    }
}

#if DEBUG
struct KKLevelBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            KKLevelBar(value: 0.62).frame(width: 80, height: 5)
            KKProgressRing(progress: 0.4).frame(width: 18, height: 18)
            KKSparkline([0.1, 0.3, 0.2, 0.6, 0.4, 0.8]).frame(width: 60, height: 16)
        }
        .padding()
        .background(.black)
    }
}
#endif
