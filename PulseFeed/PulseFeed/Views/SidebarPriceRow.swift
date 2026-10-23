import SwiftUI

struct SidebarPriceRow: View {
    let symbol: String
    let price: PriceUpdate
    let sparkline: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(PriceFormatting.price(price.price, symbol: symbol))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            HStack {
                if sparkline.count >= 2 {
                    SparklineView(data: sparkline, color: changeColor)
                        .frame(height: 24)
                }

                Spacer()

                if let change = price.change24h {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8))
                        Text(String(format: "%.1f%%", abs(change)))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(changeColor)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var changeColor: Color {
        if let change = price.change24h {
            return change >= 0 ? .green : .red
        }
        return .secondary
    }

}

struct SparklineView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if let minVal = data.min(), let maxVal = data.max(), maxVal > minVal {
                let range = maxVal - minVal

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = width * CGFloat(index) / CGFloat(data.count - 1)
                        let y = height - (height * CGFloat(value - minVal) / CGFloat(range))

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = width * CGFloat(index) / CGFloat(data.count - 1)
                        let y = height - (height * CGFloat(value - minVal) / CGFloat(range))

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}
