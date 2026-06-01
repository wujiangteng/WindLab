import SwiftUI

struct DistributionAnalysisView: View {
    let data: TimeSeriesData
    let fileURL: URL?
    let close: () -> Void

    @State private var sensorID = ""
    @State private var usesCustomBinWidth = false
    @State private var usesCustomBinStart = false
    @State private var usesHalfFirstBin = false
    @State private var binWidth = "0.5"
    @State private var binStart = "0"
    @State private var filterMode = "none"
    @State private var selectedYear = "-"
    @State private var selectedMonth = "-"
    @State private var rangeStart = ""
    @State private var rangeEnd = ""
    @State private var filterColumn = "-"
    @State private var filterMin = "0"
    @State private var filterMax = "50"
    @State private var analysis = DistributionAnalysisData.empty
    @State private var visibleSeries: Set<String> = ["Maximum likelihood", "Least squares", "WAsP", "Actual data"]
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Wind Speed Distribution Analysis")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color(.windowBackgroundColor))

            HStack(spacing: 0) {
                leftControls
                    .frame(width: 330)
                Divider()
                VStack(spacing: 14) {
                    DistributionResultTable(rows: analysis.rows, thresholdLabel: analysis.thresholdLabel)
                        .frame(height: 150)
                    HStack(spacing: 8) {
                        DistributionChart(data: analysis, visibleSeries: visibleSeries)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        DistributionLegend(curves: analysis.curves, visibleSeries: $visibleSeries)
                            .frame(width: 168)
                    }
                }
                .padding(10)
            }

            HStack {
                Button("Help") {}
                    .frame(width: 72)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                if let loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                Button("Close", action: close)
                    .frame(width: 72)
            }
            .padding(8)
        }
        .frame(width: 990, height: 690)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            resetDefaults()
            loadAnalysis()
        }
        .onChange(of: sensorID) { _, _ in loadAnalysis() }
        .onChange(of: usesCustomBinWidth) { _, _ in loadAnalysis() }
        .onChange(of: usesCustomBinStart) { _, _ in loadAnalysis() }
        .onChange(of: binWidth) { _, _ in loadAnalysis() }
        .onChange(of: binStart) { _, _ in loadAnalysis() }
        .onChange(of: filterMode) { _, _ in loadAnalysis() }
        .onChange(of: selectedYear) { _, _ in loadAnalysis() }
        .onChange(of: selectedMonth) { _, _ in loadAnalysis() }
        .onChange(of: rangeStart) { _, _ in loadAnalysis() }
        .onChange(of: rangeEnd) { _, _ in loadAnalysis() }
        .onChange(of: filterColumn) { _, _ in loadAnalysis() }
        .onChange(of: filterMin) { _, _ in loadAnalysis() }
        .onChange(of: filterMax) { _, _ in loadAnalysis() }
    }

    private var leftControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Wind speed sensor")
                    .frame(width: 104, alignment: .leading)
                Picker("", selection: $sensorID) {
                    ForEach(speedChannels) { channel in
                        Text(channel.name).tag(channel.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            DistributionBinSettings(
                usesCustomBinWidth: $usesCustomBinWidth,
                usesCustomBinStart: $usesCustomBinStart,
                usesHalfFirstBin: $usesHalfFirstBin,
                binWidth: $binWidth,
                binStart: $binStart
            )
            Spacer(minLength: 20)
            HistogramFilterPanel(
                years: data.years,
                selectedYear: $selectedYear,
                selectedMonth: $selectedMonth,
                rangeStart: $rangeStart,
                rangeEnd: $rangeEnd,
                filterMode: $filterMode,
                filterColumn: $filterColumn,
                filterMin: $filterMin,
                filterMax: $filterMax,
                channels: data.channels,
                minDate: data.startDate,
                maxDate: data.endDate
            )
            .frame(height: 310)
        }
        .font(.system(size: 12))
        .padding(10)
    }

    private var speedChannels: [TimeSeriesChannel] {
        data.channels.filter { $0.unit == "m/s" }
    }

    private func resetDefaults() {
        if sensorID.isEmpty {
            sensorID = speedChannels.last?.id ?? speedChannels.first?.id ?? ""
        }
        if selectedYear == "-", let firstYear = data.years.first {
            selectedYear = String(firstYear)
        }
        if rangeStart.isEmpty { rangeStart = Self.formatDate(data.startDate) }
        if rangeEnd.isEmpty { rangeEnd = Self.formatDate(data.endDate) }
    }

    private func loadAnalysis() {
        guard let fileURL, !sensorID.isEmpty else { return }
        let widthValue = usesCustomBinWidth && Double(binWidth) != nil ? binWidth : "-"
        let startValue = usesCustomBinStart && Double(binStart) != nil ? binStart : "-"
        let filterValue = filterMode
        let yearValue = selectedYear
        let monthValue = selectedMonth
        let rangeStartValue = clampedDateString(rangeStart)
        let rangeEndValue = clampedDateString(rangeEnd)
        let filterColumnValue = filterValue == "column" ? filterColumn : "-"
        let filterMinValue = filterValue == "column" ? filterMin : "-"
        let filterMaxValue = filterValue == "column" ? filterMax : "-"
        let sensorValue = sensorID
        isLoading = true
        loadError = nil

        Task.detached {
            do {
                let decoded = try WindogParser.parseDistributionAnalysis(
                    fileURL: fileURL,
                    primaryID: sensorValue,
                    width: widthValue,
                    start: startValue,
                    filterMode: filterValue,
                    year: yearValue,
                    month: monthValue,
                    rangeStart: rangeStartValue,
                    rangeEnd: rangeEndValue,
                    filterColumn: filterColumnValue,
                    filterMin: filterMinValue,
                    filterMax: filterMaxValue
                )
                let parsed = DistributionAnalysisData(decoded: decoded)
                await MainActor.run {
                    analysis = parsed
                    visibleSeries = Set(parsed.curves.map(\.name))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func clampedDateString(_ value: String) -> String {
        guard let date = Self.parseDate(value) else { return "-" }
        return Self.formatDate(min(max(date, data.startDate), data.endDate))
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func formatDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
}

struct DistributionAnalysisData {
    let bars: [HistogramBar]
    let curves: [NamedSeries]
    let rows: [DistributionRow]
    let xLabel: String
    let yLabel: String
    let thresholdLabel: String

    static let empty = DistributionAnalysisData(bars: [], curves: [], rows: [], xLabel: "Wind Speed (m/s)", yLabel: "Frequency (%)", thresholdLabel: "-")

    init(decoded: DecodedDistributionAnalysis) {
        bars = decoded.bars.map { HistogramBar(x: $0.x, y: $0.y, width: $0.width) }
        curves = decoded.curves.map(NamedSeries.init(decoded:))
        rows = decoded.rows.map(DistributionRow.init(decoded:))
        xLabel = decoded.xLabel
        yLabel = decoded.yLabel
        thresholdLabel = decoded.thresholdLabel
    }

    init(bars: [HistogramBar], curves: [NamedSeries], rows: [DistributionRow], xLabel: String, yLabel: String, thresholdLabel: String) {
        self.bars = bars
        self.curves = curves
        self.rows = rows
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.thresholdLabel = thresholdLabel
    }
}

struct DistributionRow: Identifiable {
    let id = UUID()
    let algorithm: String
    let k: String
    let c: String
    let mean: String
    let proportionAbove: String
    let powerDensity: String
    let rSquared: String

    init(decoded: DecodedDistributionRow) {
        algorithm = decoded.algorithm
        k = decoded.k
        c = decoded.c
        mean = decoded.mean
        proportionAbove = decoded.proportionAbove
        powerDensity = decoded.powerDensity
        rSquared = decoded.rSquared
    }

    var isActualData: Bool {
        algorithm.starts(with: "Actual data")
    }

    var actualSampleText: String {
        guard isActualData,
              let start = algorithm.firstIndex(of: "("),
              let end = algorithm.lastIndex(of: ")"),
              start < end else {
            return ""
        }
        return String(algorithm[start...end])
    }
}

private struct DistributionBinSettings: View {
    @Binding var usesCustomBinWidth: Bool
    @Binding var usesCustomBinStart: Bool
    @Binding var usesHalfFirstBin: Bool
    @Binding var binWidth: String
    @Binding var binStart: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Bin settings")
                Rectangle().fill(Color(.separatorColor)).frame(height: 1)
            }
            HStack(spacing: 8) {
                CheckBox(isOn: $usesCustomBinWidth)
                Text("Width").frame(width: 58, alignment: .leading)
                TextField("", text: $binWidth).textFieldStyle(.roundedBorder).frame(width: 58).disabled(!usesCustomBinWidth)
                Text("m/s").foregroundStyle(.secondary)
                CheckBox(isOn: $usesHalfFirstBin)
                Text("Make first bin\nhalf this width").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                CheckBox(isOn: $usesCustomBinStart)
                Text("Start at").frame(width: 58, alignment: .leading)
                TextField("", text: $binStart).textFieldStyle(.roundedBorder).frame(width: 58).disabled(!usesCustomBinStart)
                Text("m/s").foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct DistributionResultTable: View {
    let rows: [DistributionRow]
    let thresholdLabel: String
    private let algorithmWidth: CGFloat = 150
    private let kWidth: CGFloat = 70
    private let cWidth: CGFloat = 78
    private let meanWidth: CGFloat = 76
    private let proportionWidth: CGFloat = 104
    private let powerWidth: CGFloat = 88
    private let rSquaredWidth: CGFloat = 76

    private var tableWidth: CGFloat {
        algorithmWidth + kWidth + cWidth + meanWidth + proportionWidth + powerWidth + rSquaredWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("Algorithm", width: algorithmWidth)
                header("Weibull\nk", width: kWidth)
                header("Weibull\nc\n(m/s)", width: cWidth)
                header("Mean\n(m/s)", width: meanWidth)
                header("Proportion\nAbove\n\(thresholdLabel)", width: proportionWidth)
                header("Power\nDensity\n(W/m2)", width: powerWidth)
                header("R\nSquared", width: rSquaredWidth)
            }
            ForEach(rows) { row in
                if row.isActualData {
                    HStack(spacing: 0) {
                        cell("Actual data", width: algorithmWidth, align: .leading, highlight: true)
                        cell(row.actualSampleText, width: kWidth + cWidth, align: .leading, highlight: true)
                        cell(row.mean, width: meanWidth, highlight: true)
                        cell(row.proportionAbove, width: proportionWidth, highlight: true)
                        cell(row.powerDensity, width: powerWidth, highlight: true)
                        cell(row.rSquared, width: rSquaredWidth, highlight: true)
                    }
                } else {
                    HStack(spacing: 0) {
                        cell(row.algorithm, width: algorithmWidth, align: .leading)
                        cell(row.k, width: kWidth)
                        cell(row.c, width: cWidth)
                        cell(row.mean, width: meanWidth)
                        cell(row.proportionAbove, width: proportionWidth)
                        cell(row.powerDensity, width: powerWidth)
                        cell(row.rSquared, width: rSquaredWidth)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: tableWidth, alignment: .top)
        .font(.system(size: 12, design: .monospaced))
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func header(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .frame(width: width, height: 44)
            .background(Color(.controlBackgroundColor))
            .border(Color(.separatorColor))
    }

    private func cell(_ text: String, width: CGFloat, align: Alignment = .trailing, highlight: Bool = false) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 4)
            .frame(width: width, height: 22, alignment: align)
            .background(highlight ? Color.green.opacity(0.10) : Color.white)
            .border(Color(.separatorColor))
    }
}

private struct DistributionChart: View {
    let data: DistributionAnalysisData
    let visibleSeries: Set<String>

    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 46
            let bottom: CGFloat = 54
            let top: CGFloat = 22
            let right: CGFloat = 16
            let size = CGSize(width: max(geometry.size.width - left - right, 10), height: max(geometry.size.height - top - bottom, 10))
            let origin = CGPoint(x: left, y: top)
            let xMax = max((data.bars.last?.x ?? 1) + (data.bars.last?.width ?? 0.5), 1)
            let curveValues = data.curves.filter { visibleSeries.contains($0.name) }.flatMap(\.points).map(\.y)
            let yMax = max((data.bars.map(\.y) + curveValues).max() ?? 1, 1)
            let xTicks = stride(from: 0.0, through: xMax, by: niceStep(xMax / 5)).map { $0 }
            let yTicks = stride(from: 0.0, through: yMax, by: niceStep(yMax / 5)).map { $0 }
            ZStack(alignment: .topLeading) {
                Text("Wind Speed Frequency Distribution")
                    .font(.system(size: 13, weight: .semibold))
                    .position(x: origin.x + size.width / 2, y: 8)
                ChartGrid(xTicks: xTicks, yTicks: yTicks, xRange: 0...xMax, yRange: 0...yMax, origin: origin, size: size)
                ForEach(data.bars) { bar in
                    let x0 = mapX(bar.x - bar.width / 2, xMax, origin, size)
                    let x1 = mapX(bar.x + bar.width / 2, xMax, origin, size)
                    let y = mapY(bar.y, yMax, origin, size)
                    Rectangle()
                        .fill(Color.green.opacity(0.25))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.6))
                        .frame(width: max(x1 - x0, 1), height: origin.y + size.height - y)
                        .position(x: (x0 + x1) / 2, y: y + (origin.y + size.height - y) / 2)
                }
                ForEach(data.curves.filter { visibleSeries.contains($0.name) && $0.name != "Actual data" }) { curve in
                    Path { path in
                        for (index, point) in curve.points.enumerated() {
                            let mapped = CGPoint(x: mapX(point.x, xMax, origin, size), y: mapY(point.y, yMax, origin, size))
                            index == 0 ? path.move(to: mapped) : path.addLine(to: mapped)
                        }
                    }
                    .stroke(Color.chartColor(curve.colorName), lineWidth: 2)
                }
                Rectangle().stroke(.black, lineWidth: 1).frame(width: size.width, height: size.height).position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                ForEach(yTicks, id: \.self) { tick in Text(formatTick(tick)).font(.system(size: 10)).position(x: origin.x - 18, y: mapY(tick, yMax, origin, size)) }
                ForEach(xTicks, id: \.self) { tick in Text(formatTick(tick)).font(.system(size: 10)).position(x: mapX(tick, xMax, origin, size), y: origin.y + size.height + 16) }
                Text(data.yLabel).font(.system(size: 10)).rotationEffect(.degrees(-90)).position(x: 10, y: origin.y + size.height / 2)
                Text(data.xLabel).font(.system(size: 10)).position(x: origin.x + size.width / 2, y: origin.y + size.height + 32)
            }
        }
        .frame(minHeight: 400)
    }

    private func mapX(_ value: Double, _ xMax: Double, _ origin: CGPoint, _ size: CGSize) -> CGFloat {
        origin.x + CGFloat(value / xMax) * size.width
    }

    private func mapY(_ value: Double, _ yMax: Double, _ origin: CGPoint, _ size: CGSize) -> CGFloat {
        origin.y + size.height - CGFloat(value / yMax) * size.height
    }

    private func niceStep(_ raw: Double) -> Double {
        let magnitude = pow(10, floor(log10(max(raw, 1e-9))))
        let scaled = raw / magnitude
        if scaled <= 2 { return 2 * magnitude }
        if scaled <= 5 { return 5 * magnitude }
        return 10 * magnitude
    }

    private func formatTick(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.0001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}

private struct DistributionLegend: View {
    let curves: [NamedSeries]
    @Binding var visibleSeries: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            ForEach(curves) { curve in
                HStack(spacing: 6) {
                    Rectangle().fill(curve.name == "Actual data" ? Color.green.opacity(0.35) : Color.chartColor(curve.colorName)).frame(width: 24, height: 4)
                    CheckBox(isOn: binding(curve.name))
                    Text(curve.name).font(.system(size: 12)).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func binding(_ name: String) -> Binding<Bool> {
        Binding {
            visibleSeries.contains(name)
        } set: { value in
            if value { visibleSeries.insert(name) } else { visibleSeries.remove(name) }
        }
    }
}
