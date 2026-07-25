import SwiftUI

struct DashboardSparkline: View {
    let values: [Double]
    var fixedMaximum: Double?
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maximum = max(fixedMaximum ?? values.max() ?? 1, 0.000_001)
            let step = size.width / Double(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: Double(index) * step,
                    y: size.height * (1 - min(max(value / maximum, 0), 1))
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(
                path,
                with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}
