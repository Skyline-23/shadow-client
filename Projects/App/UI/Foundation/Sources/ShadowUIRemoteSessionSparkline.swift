import SwiftUI

public struct ShadowUIDiagnosticsSparkline: View {
    public let samples: [Double]
    public let color: Color

    public init(samples: [Double], color: Color) {
        self.samples = samples
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let graphPath = sparklinePath(for: size)

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.24))

                if !graphPath.isEmpty {
                    graphPath
                        .stroke(color.opacity(0.92), lineWidth: 1.6)
                }
            }
        }
    }

    private func sparklinePath(for size: CGSize) -> Path {
        guard samples.count >= 2 else {
            return Path()
        }

        let maximum = samples.max() ?? 0
        let minimum = samples.min() ?? 0
        let range = max(maximum - minimum, 1)
        let stepX = size.width / CGFloat(max(samples.count - 1, 1))

        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (sample - minimum) / range
            let y = size.height - (CGFloat(normalized) * size.height)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

public struct ShadowUIRemoteSessionSparklineRow: View {
    private let title: String
    private let latestValue: String
    private let samples: [Double]
    private let color: Color

    public init(title: String, latestValue: String, samples: [Double], color: Color) {
        self.title = title
        self.latestValue = latestValue
        self.samples = samples
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 6)
                Text(latestValue)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color.opacity(0.9))
            }

            ShadowUIDiagnosticsSparkline(samples: samples, color: color)
                .frame(height: 20)
        }
    }
}
