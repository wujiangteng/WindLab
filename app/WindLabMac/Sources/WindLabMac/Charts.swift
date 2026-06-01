import SwiftUI

extension Color {
    static func chartColor(_ name: String) -> Color {
        if name.hasPrefix("#"), let rgb = Int(name.dropFirst(), radix: 16) {
            return Color(
                red: Double((rgb >> 16) & 0xff) / 255.0,
                green: Double((rgb >> 8) & 0xff) / 255.0,
                blue: Double(rgb & 0xff) / 255.0
            )
        }
        return switch name {
        case "measured": .green
        case "power": Color(red: 0.37, green: 0.31, blue: 0.50)
        case "log": Color(red: 0.82, green: 0.39, blue: 0.26)
        case "secondary": Color(red: 0.55, green: 0.70, blue: 1.0)
        case "accent": Color(red: 0.65, green: 0.28, blue: 0.18)
        case "brown": Color(red: 0.50, green: 0.26, blue: 0.12)
        case "violet": Color(red: 0.26, green: 0.08, blue: 0.34)
        case "yellow": Color(red: 0.95, green: 0.72, blue: 0.05)
        case "green2": Color(red: 0.35, green: 0.78, blue: 0.12)
        case "red": Color(red: 0.72, green: 0.18, blue: 0.16)
        case "purple": Color(red: 0.45, green: 0.18, blue: 0.95)
        case "orange": Color(red: 0.95, green: 0.42, blue: 0.08)
        case "blue2": Color(red: 0.05, green: 0.28, blue: 0.68)
        case "blue3": Color(red: 0.08, green: 0.38, blue: 0.82)
        case "blue4": Color(red: 0.12, green: 0.48, blue: 0.92)
        case "blue5": Color(red: 0.18, green: 0.56, blue: 0.98)
        case "blue6": Color(red: 0.30, green: 0.62, blue: 1.0)
        case "blue7": Color(red: 0.42, green: 0.68, blue: 1.0)
        case "blue8": Color(red: 0.58, green: 0.76, blue: 1.0)
        default: Color(red: 0.02, green: 0.22, blue: 0.45)
        }
    }
}

struct CartesianLineChart: View {
    let series: [NamedSeries]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let xTicks: [Double]
    let yTicks: [Double]
    var xLabels: [String]? = nil
    let xLabel: String
    let yLabel: String
    let markerSeriesName: String?
    var markerMode: MarkerMode = .selected

    var body: some View {
        GeometryReader { geometry in
            let legendWidth = min(max(geometry.size.width * 0.22, 120), 230)
            let leftInset: CGFloat = 42
            let bottomInset: CGFloat = 48
            let topInset: CGFloat = 10
            let rightInset: CGFloat = 12
            let plotSize = CGSize(
                width: max(geometry.size.width - legendWidth - leftInset - rightInset, 10),
                height: max(geometry.size.height - topInset - bottomInset, 10)
            )
            let origin = CGPoint(x: leftInset, y: topInset)

            ZStack(alignment: .topLeading) {
                ChartGrid(
                    xTicks: xTicks,
                    yTicks: yTicks,
                    xRange: xRange,
                    yRange: yRange,
                    origin: origin,
                    size: plotSize
                )
                ChartSeriesLayer(
                    series: series,
                    xRange: xRange,
                    yRange: yRange,
                    origin: origin,
                    size: plotSize,
                    markerSeriesName: markerSeriesName,
                    markerMode: markerMode
                )
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: plotSize.width, height: plotSize.height)
                    .position(x: origin.x + plotSize.width / 2, y: origin.y + plotSize.height / 2)

                tickLabels(origin: origin, size: plotSize)
                axisLabels(origin: origin, size: plotSize)

                LegendView(series: series)
                    .frame(width: legendWidth - 8, height: plotSize.height, alignment: .topLeading)
                    .position(x: geometry.size.width - legendWidth / 2 + 4, y: origin.y + plotSize.height / 2)
            }
            .clipped()
        }
        .frame(minHeight: 240)
    }

    private func tickLabels(origin: CGPoint, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(yTicks, id: \.self) { tick in
                Text(formatTick(tick))
                    .font(.system(size: 10))
                    .position(x: origin.x - 18, y: yPosition(tick, origin: origin, size: size))
            }

            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, tick in
                Text(xLabels?[safe: index] ?? formatTick(tick))
                    .font(.system(size: 10))
                    .position(x: xTickLabelPosition(tick, index: index, origin: origin, size: size), y: origin.y + size.height + 17)
            }
        }
    }

    private func axisLabels(origin: CGPoint, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Text(xLabel)
                .font(.system(size: 10))
                .position(x: origin.x + size.width / 2, y: origin.y + size.height + 30)

            Text(yLabel)
                .font(.system(size: 10))
                .rotationEffect(.degrees(-90))
                .position(x: 9, y: origin.y + size.height / 2)
        }
    }

    private func xPosition(_ value: Double, origin: CGPoint, size: CGSize) -> CGFloat {
        let fraction = (value - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
        return origin.x + CGFloat(fraction) * size.width
    }

    private func xTickLabelPosition(_ value: Double, index: Int, origin: CGPoint, size: CGSize) -> CGFloat {
        let raw = xPosition(value, origin: origin, size: size)
        if index == 0 {
            return max(raw, origin.x + 7)
        }
        if index == xTicks.count - 1 {
            return min(raw, origin.x + size.width - 8)
        }
        return min(max(raw, origin.x + 7), origin.x + size.width - 8)
    }

    private func yPosition(_ value: Double, origin: CGPoint, size: CGSize) -> CGFloat {
        let fraction = (value - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
        return origin.y + size.height - CGFloat(fraction) * size.height
    }

    private func formatTick(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum MarkerMode {
    case selected
    case all
    case none
}

struct ChartGrid: View {
    let xTicks: [Double]
    let yTicks: [Double]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let origin: CGPoint
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for index in 0...10 {
                    let x = origin.x + size.width * CGFloat(index) / 10
                    path.move(to: CGPoint(x: x, y: origin.y))
                    path.addLine(to: CGPoint(x: x, y: origin.y + size.height))
                }
                for index in 0...10 {
                    let y = origin.y + size.height * CGFloat(index) / 10
                    path.move(to: CGPoint(x: origin.x, y: y))
                    path.addLine(to: CGPoint(x: origin.x + size.width, y: y))
                }
            }
            .stroke(Color(red: 0.92, green: 0.92, blue: 0.92), lineWidth: 0.7)

            Path { path in
                for tick in xTicks {
                    let x = xPosition(tick)
                    path.move(to: CGPoint(x: x, y: origin.y))
                    path.addLine(to: CGPoint(x: x, y: origin.y + size.height))
                }
                for tick in yTicks {
                    let y = yPosition(tick)
                    path.move(to: CGPoint(x: origin.x, y: y))
                    path.addLine(to: CGPoint(x: origin.x + size.width, y: y))
                }
            }
            .stroke(Color(red: 0.80, green: 0.80, blue: 0.80), lineWidth: 1)
        }
    }

    private func xPosition(_ value: Double) -> CGFloat {
        let fraction = (value - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
        return origin.x + CGFloat(fraction) * size.width
    }

    private func yPosition(_ value: Double) -> CGFloat {
        let fraction = (value - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
        return origin.y + size.height - CGFloat(fraction) * size.height
    }
}

struct ChartSeriesLayer: View {
    let series: [NamedSeries]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let origin: CGPoint
    let size: CGSize
    let markerSeriesName: String?
    let markerMode: MarkerMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(series) { item in
                Path { path in
                    for (index, point) in item.points.enumerated() {
                        let mapped = map(point)
                        if index == 0 {
                            path.move(to: mapped)
                        } else {
                            path.addLine(to: mapped)
                        }
                    }
                }
                .stroke(Color.chartColor(item.colorName), lineWidth: item.name == "Measured data" ? 2.2 : 1.8)

                if shouldDrawMarkers(for: item) {
                    ForEach(item.points) { point in
                        Circle()
                            .fill(Color.white)
                            .overlay {
                                Circle()
                                    .stroke(Color.chartColor(item.colorName), lineWidth: 1.5)
                            }
                            .frame(width: 6, height: 6)
                            .position(map(point))
                    }
                }
            }
        }
    }

    private func shouldDrawMarkers(for item: NamedSeries) -> Bool {
        switch markerMode {
        case .all:
            return true
        case .none:
            return false
        case .selected:
            return markerSeriesName == item.name
        }
    }

    private func map(_ point: SeriesPoint) -> CGPoint {
        let xFraction = (point.x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
        let yFraction = (point.y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
        return CGPoint(
            x: origin.x + CGFloat(xFraction) * size.width,
            y: origin.y + size.height - CGFloat(yFraction) * size.height
        )
    }
}

struct LegendView: View {
    let series: [NamedSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(series) { item in
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.chartColor(item.colorName))
                        .frame(width: 18, height: 3)
                    Text(item.name)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 11)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }
}

struct WindRoseChart: View {
    let series: [NamedPolarSeries]
    var showsLegend = true

    var body: some View {
        GeometryReader { geometry in
            let legendWidth = showsLegend ? min(max(geometry.size.width * 0.22, 110), 190) : 0
            let drawingWidth = max(geometry.size.width - legendWidth, 100)
            let size = min(drawingWidth, geometry.size.height - 8)
            let center = CGPoint(x: drawingWidth / 2, y: geometry.size.height / 2 + 2)
            let radius = size * 0.39
            let axisMax = roseAxisMax

            ZStack {
                RoseGrid(center: center, radius: radius, axisMax: axisMax)
                ForEach(series) { item in
                    RoseSeries(item: item, center: center, radius: radius, axisMax: axisMax)
                }

                ForEach([0, 22.5, 45, 67.5, 90, 112.5, 135, 157.5, 180, 202.5, 225, 247.5, 270, 292.5, 315, 337.5], id: \.self) { degree in
                    Text(degreeLabel(degree))
                        .font(.system(size: 10))
                        .position(labelPosition(degree: degree, center: center, radius: radius + 18))
                }

                if showsLegend {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(series) { item in
                            HStack(spacing: 6) {
                                Rectangle()
                                    .fill(Color.chartColor(item.colorName))
                                    .frame(width: 20, height: 3)
                                Text(item.name)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 11)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: legendWidth - 10, height: radius * 2, alignment: .topLeading)
                    .position(x: geometry.size.width - legendWidth / 2, y: center.y)
                }
            }
            .clipped()
        }
        .frame(minHeight: 240)
    }

    private var roseAxisMax: Double {
        let maxValue = series.flatMap(\.points).map(\.radius).max() ?? 0.25
        guard maxValue > 0 else { return 0.25 }
        if maxValue <= 1 {
            return max(0.05, ceil(maxValue / 0.05) * 0.05)
        }
        let magnitude = pow(10.0, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let nice: Double
        if normalized <= 2 {
            nice = 2
        } else if normalized <= 5 {
            nice = 5
        } else {
            nice = 10
        }
        return nice * magnitude
    }

    private func labelPosition(degree: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        polarPosition(degree: degree, scalar: 1, center: center, radius: radius)
    }

    private func polarPosition(degree: Double, scalar: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (degree - 90) * .pi / 180
        return CGPoint(
            x: center.x + cos(angle) * radius * CGFloat(scalar),
            y: center.y + sin(angle) * radius * CGFloat(scalar)
        )
    }

    private func degreeLabel(_ degree: Double) -> String {
        degree.rounded() == degree ? "\(Int(degree))°" : "\(degree)°"
    }
}

struct RoseGrid: View {
    let center: CGPoint
    let radius: CGFloat
    let axisMax: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(axisTicks, id: \.self) { value in
                let currentRadius = mappedRadius(for: value)
                Circle()
                    .stroke(Color(red: 0.82, green: 0.82, blue: 0.82), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    .frame(width: currentRadius * 2, height: currentRadius * 2)
                    .position(center)
            }

            Path { path in
                for degree in stride(from: 0.0, through: 337.5, by: 22.5) {
                    path.move(to: center)
                    path.addLine(to: polarPosition(degree: degree, scalar: 1, center: center, radius: radius))
                }
            }
            .stroke(Color(red: 0.86, green: 0.86, blue: 0.86), style: StrokeStyle(lineWidth: 0.8, dash: [4, 5]))

            let innerRadius = radius * 0.25
            Circle()
                .fill(Color.white)
                .overlay {
                    Circle()
                        .stroke(Color.black, lineWidth: 1)
                }
                .frame(width: innerRadius * 2, height: innerRadius * 2)
                .position(center)

            Text("0 %")
                .font(.system(size: 10))
                .position(polarPosition(degree: 165, distance: radius * 0.25))
            ForEach(axisTicks, id: \.self) { value in
                Text(axisLabel(value))
                    .font(.system(size: 10))
                    .position(polarPosition(degree: 166, distance: mappedRadius(for: value)))
            }
        }
    }

    private var axisTicks: [Double] {
        [axisMax / 3, axisMax * 2 / 3, axisMax]
    }

    private func mappedRadius(for value: Double) -> CGFloat {
        let innerFraction = 0.25
        let normalized = min(max(value, 0), axisMax) / axisMax
        return radius * (innerFraction + (1 - innerFraction) * normalized)
    }

    private func axisLabel(_ value: Double) -> String {
        if axisMax <= 1 {
            return "\(Int(round(value * 100))) %"
        }
        return value >= 1000 ? String(format: "%.0f", value) : String(format: "%.0f", value)
    }

    private func polarPosition(degree: Double, distance: CGFloat) -> CGPoint {
        let angle = (degree - 90) * .pi / 180
        return CGPoint(
            x: center.x + cos(angle) * distance,
            y: center.y + sin(angle) * distance
        )
    }

    private func polarPosition(degree: Double, scalar: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (degree - 90) * .pi / 180
        return CGPoint(
            x: center.x + cos(angle) * radius * CGFloat(scalar),
            y: center.y + sin(angle) * radius * CGFloat(scalar)
        )
    }
}

struct RoseSeries: View {
    let item: NamedPolarSeries
    let center: CGPoint
    let radius: CGFloat
    let axisMax: Double

    var body: some View {
        Path { path in
            for (index, point) in item.points.enumerated() {
                let mapped = polarPosition(degree: point.degrees, scalar: point.radius)
                if index == 0 {
                    path.move(to: mapped)
                } else {
                    path.addLine(to: mapped)
                }
            }
            if let first = item.points.first {
                path.addLine(to: polarPosition(degree: first.degrees, scalar: first.radius))
            }
        }
        .stroke(Color.chartColor(item.colorName), lineWidth: 2.2)
    }

    private func polarPosition(degree: Double, scalar: Double) -> CGPoint {
        let angle = (degree - 90) * .pi / 180
        let innerFraction = 0.25
        let normalized = min(max(scalar, 0), axisMax) / axisMax
        let mappedRadius = radius * (innerFraction + (1 - innerFraction) * normalized)
        return CGPoint(
            x: center.x + cos(angle) * mappedRadius,
            y: center.y + sin(angle) * mappedRadius
        )
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
