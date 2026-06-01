import SwiftUI

struct HistogramBar: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let width: Double
}

struct HistogramData {
    let bars: [HistogramBar]
    let curve: [SeriesPoint]
    let xLabel: String
    let yLabel: String
    let weibull: String
}

struct HistogramView: View {
    let data: TimeSeriesData
    let fileURL: URL?

    @State private var display = "frequency"
    @State private var versus = "one data column"
    @State private var format = "chart"
    @State private var primaryID = ""
    @State private var usesCustomBinWidth = false
    @State private var usesCustomBinStart = false
    @State private var usesHalfFirstBin = false
    @State private var binWidth = "0.5"
    @State private var binStart = "0"
    @State private var histogram = HistogramData(bars: [], curve: [], xLabel: "", yLabel: "Frequency (%)", weibull: "-")
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var filterMode = "none"
    @State private var selectedYear = "-"
    @State private var selectedMonth = "-"
    @State private var rangeStart = ""
    @State private var rangeEnd = ""
    @State private var filterColumn = "-"
    @State private var filterMin = "0"
    @State private var filterMax = "50"

    private let displayOptions = ["frequency", "occurrences"]
    private let versusOptions = ["one data column", "data column and month", "data column and hour of day", "two data columns"]

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 360)
            Divider()
            PlotPanel(title: "Probability Distribution Function") {
                HistogramChart(data: histogram)
            }
            .padding(8)
            .overlay(alignment: .topLeading) {
                if isLoading {
                    ProgressView().controlSize(.small).padding(12)
                }
            }
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            resetDefaults()
            loadHistogram()
        }
        .onChange(of: data.channels) { _, _ in resetDefaults(); loadHistogram() }
        .onChange(of: display) { _, _ in loadHistogram() }
        .onChange(of: primaryID) { _, _ in loadHistogram() }
        .onChange(of: usesCustomBinWidth) { _, _ in loadHistogram() }
        .onChange(of: usesCustomBinStart) { _, _ in loadHistogram() }
        .onChange(of: binWidth) { _, _ in loadHistogram() }
        .onChange(of: binStart) { _, _ in loadHistogram() }
        .onChange(of: filterMode) { _, _ in loadHistogram() }
        .onChange(of: selectedYear) { _, _ in loadHistogram() }
        .onChange(of: selectedMonth) { _, _ in loadHistogram() }
        .onChange(of: rangeStart) { _, _ in loadHistogram() }
        .onChange(of: rangeEnd) { _, _ in loadHistogram() }
        .onChange(of: filterColumn) { _, _ in loadHistogram() }
        .onChange(of: filterMin) { _, _ in loadHistogram() }
        .onChange(of: filterMax) { _, _ in loadHistogram() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("Display")
                    .frame(width: 70, alignment: .leading)
                RadioButton(title: "frequency", isOn: display == "frequency") { display = "frequency" }
                    .frame(width: 92, alignment: .leading)
                RadioButton(title: "occurrences", isOn: display == "occurrences") { display = "occurrences" }
                    .frame(width: 108, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            HStack(spacing: 10) {
                Spacer().frame(width: 70)
                Text("Format")
                    .frame(width: 54, alignment: .leading)
                SmallIconButton(systemName: "chart.bar.xaxis", isSelected: format == "chart") { format = "chart" }
                SmallIconButton(systemName: "tablecells", isSelected: format == "table") { format = "table" }
                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                Text("versus")
                    .frame(width: 70, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(versusOptions, id: \.self) { option in
                        RadioButton(title: option, isOn: versus == option) { versus = option }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Primary bins")
                    .frame(width: 92, alignment: .leading)
                Picker("", selection: $primaryID) {
                    ForEach(speedChannels) { channel in
                        Text(channel.name).tag(channel.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    CheckBox(isOn: $usesCustomBinWidth)
                    Text("Width")
                        .frame(width: 58, alignment: .leading)
                    TextField("", text: $binWidth)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .disabled(!usesCustomBinWidth)
                        .opacity(usesCustomBinWidth ? 1 : 0.55)
                    Text("m/s").foregroundStyle(.secondary)
                    CheckBox(isOn: $usesHalfFirstBin)
                    Text("Make first bin\nhalf this width")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    CheckBox(isOn: $usesCustomBinStart)
                    Text("Start at")
                        .frame(width: 58, alignment: .leading)
                    TextField("", text: $binStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .disabled(!usesCustomBinStart)
                        .opacity(usesCustomBinStart ? 1 : 0.55)
                    Text("m/s").foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer(minLength: 18)

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
            .frame(height: 282)
            .padding(.bottom, 14)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .background(Color(.windowBackgroundColor))
    }

    private var speedChannels: [TimeSeriesChannel] {
        data.channels.filter { $0.unit == "m/s" }
    }

    private func resetDefaults() {
        if primaryID.isEmpty {
            primaryID = speedChannels.first?.id ?? ""
        }
        if selectedYear == "-", let firstYear = data.years.first {
            selectedYear = String(firstYear)
        }
        if rangeStart.isEmpty { rangeStart = Self.formatDate(data.startDate) }
        if rangeEnd.isEmpty { rangeEnd = Self.formatDate(data.endDate) }
    }

    private func loadHistogram() {
        guard let fileURL, !primaryID.isEmpty else { return }
        let displayValue = display
        let primaryValue = primaryID
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
        isLoading = true
        loadError = nil
        Task.detached {
            do {
                let decoded = try WindogParser.parseHistogram(
                    fileURL: fileURL,
                    display: displayValue,
                    primaryID: primaryValue,
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
                let parsed = HistogramData(
                    bars: decoded.bars.map { HistogramBar(x: $0.x, y: $0.y, width: $0.width) },
                    curve: decoded.curve.map { SeriesPoint(x: $0.x, y: $0.y) },
                    xLabel: decoded.xLabel,
                    yLabel: decoded.yLabel,
                    weibull: decoded.weibull
                )
                await MainActor.run {
                    histogram = parsed
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

private struct HistogramChart: View {
    let data: HistogramData

    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 48
            let bottom: CGFloat = 78
            let top: CGFloat = 10
            let right: CGFloat = 20
            let size = CGSize(width: max(geometry.size.width - left - right, 10), height: max(geometry.size.height - top - bottom, 10))
            let origin = CGPoint(x: left, y: top)
            let xMax = max((data.bars.last?.x ?? 1) + (data.bars.last?.width ?? 0.5), 1)
            let yMax = max((data.bars.map(\.y) + data.curve.map(\.y)).max() ?? 1, 1)
            let xTicks = stride(from: 0.0, through: xMax, by: niceStep(xMax / 5)).map { $0 }
            let yTicks = stride(from: 0.0, through: yMax, by: niceStep(yMax / 5)).map { $0 }
            ZStack(alignment: .topLeading) {
                ChartGrid(
                    xTicks: xTicks,
                    yTicks: yTicks,
                    xRange: 0...xMax,
                    yRange: 0...yMax,
                    origin: origin,
                    size: size
                )
                ForEach(data.bars) { bar in
                    let x0 = xPosition(bar.x - bar.width / 2, xMax: xMax, origin: origin, size: size)
                    let x1 = xPosition(bar.x + bar.width / 2, xMax: xMax, origin: origin, size: size)
                    let y = yPosition(bar.y, yMax: yMax, origin: origin, size: size)
                    Rectangle()
                        .fill(Color(red: 0.62, green: 0.32, blue: 0.17))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.6))
                        .frame(width: max(x1 - x0, 1), height: origin.y + size.height - y)
                        .position(x: (x0 + x1) / 2, y: y + (origin.y + size.height - y) / 2)
                }
                Path { path in
                    for (index, point) in data.curve.enumerated() {
                        let mapped = CGPoint(x: xPosition(point.x, xMax: xMax, origin: origin, size: size), y: yPosition(point.y, yMax: yMax, origin: origin, size: size))
                        index == 0 ? path.move(to: mapped) : path.addLine(to: mapped)
                    }
                }
                .stroke(.black, lineWidth: 2)
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: size.width, height: size.height)
                    .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                ForEach(yTicks, id: \.self) { tick in
                    Text(formatTick(tick))
                        .font(.system(size: 10))
                        .position(
                            x: origin.x - 20,
                            y: yPosition(tick, yMax: yMax, origin: origin, size: size)
                        )
                }
                ForEach(xTicks, id: \.self) { tick in
                    Text(formatTick(tick))
                        .font(.system(size: 10))
                        .position(
                            x: xTickLabelPosition(tick, xMax: xMax, origin: origin, size: size),
                            y: origin.y + size.height + 16
                        )
                }
                Text(data.yLabel)
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(-90))
                    .position(x: 10, y: origin.y + size.height / 2)
                Text(data.xLabel)
                    .font(.system(size: 10))
                    .position(x: origin.x + size.width / 2, y: origin.y + size.height + 30)
                HStack(spacing: 10) {
                    LegendSwatch(color: Color(red: 0.62, green: 0.32, blue: 0.17), text: "Actual data")
                    LegendLine(text: "Best-fit Weibull distribution (\(data.weibull))")
                }
                .position(x: origin.x + size.width / 2, y: geometry.size.height - 18)
            }
        }
    }

    private func xPosition(_ value: Double, xMax: Double, origin: CGPoint, size: CGSize) -> CGFloat {
        origin.x + CGFloat(value / xMax) * size.width
    }

    private func xTickLabelPosition(_ value: Double, xMax: Double, origin: CGPoint, size: CGSize) -> CGFloat {
        let raw = xPosition(value, xMax: xMax, origin: origin, size: size)
        if value == 0 {
            return max(raw, origin.x + 6)
        }
        if abs(value - xMax) < 0.0001 {
            return min(raw, origin.x + size.width - 10)
        }
        return min(max(raw, origin.x + 8), origin.x + size.width - 10)
    }

    private func yPosition(_ value: Double, yMax: Double, origin: CGPoint, size: CGSize) -> CGFloat {
        origin.y + size.height - CGFloat(value / yMax) * size.height
    }

    private func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let scaled = raw / magnitude
        if scaled <= 2 { return 2 * magnitude }
        if scaled <= 5 { return 5 * magnitude }
        return 10 * magnitude
    }

    private func formatTick(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private struct LegendSwatch: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 20, height: 4)
            Text(text).font(.system(size: 10))
        }
    }
}

private struct LegendLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(Color.black).frame(width: 20, height: 3)
            Text(text).font(.system(size: 10))
        }
    }
}

private struct RadioButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "smallcircle.filled.circle" : "circle")
                    .font(.system(size: 10))
                Text(title)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SmallIconButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 22)
                .background(isSelected ? Color(.selectedControlColor).opacity(0.22) : Color(.controlBackgroundColor))
                .overlay(Rectangle().stroke(Color(.separatorColor)))
        }
        .buttonStyle(.plain)
    }
}

struct HistogramFilterPanel: View {
    let years: [Int]
    @Binding var selectedYear: String
    @Binding var selectedMonth: String
    @Binding var rangeStart: String
    @Binding var rangeEnd: String
    @Binding var filterMode: String
    @Binding var filterColumn: String
    @Binding var filterMin: String
    @Binding var filterMax: String
    let channels: [TimeSeriesChannel]
    let minDate: Date
    let maxDate: Date
    private let months = [("-", "<All>"), ("1", "Jan"), ("2", "Feb"), ("3", "Mar"), ("4", "Apr"), ("5", "May"), ("6", "Jun"), ("7", "Jul"), ("8", "Aug"), ("9", "Sep"), ("10", "Oct"), ("11", "Nov"), ("12", "Dec")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Filter by")
                Rectangle().fill(Color(.separatorColor)).frame(height: 1)
            }
            HStack(spacing: 7) {
                CheckBox(isOn: .constant(true))
                Text("Flag").frame(width: 56, alignment: .leading)
                Text("Include").fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    HStack { CheckBox(isOn: .constant(true)); Text("<Unflagged data>") }
                    HStack { CheckBox(isOn: .constant(true)); Text("Synthesized") }
                }
            }
            HStack(spacing: 5) {
                CheckBox(isOn: binding("date"))
                Text("Date").frame(width: 64, alignment: .leading)
                Text("Year").foregroundStyle(.secondary).fixedSize()
                Picker("", selection: $selectedYear) {
                    Text("<All>").tag("-")
                    ForEach(years, id: \.self) { Text(String($0)).tag(String($0)) }
                }
                .labelsHidden().frame(width: 62)
                Text("Month").foregroundStyle(.secondary).fixedSize()
                Picker("", selection: $selectedMonth) {
                    ForEach(months, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 68)
            }
            HStack(spacing: 6) {
                CheckBox(isOn: binding("range"))
                Text("Date range").frame(width: 64, alignment: .leading)
                DatePicker("", selection: dateBinding(for: $rangeStart), in: minDate...maxDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(width: 88)
                Text("to").foregroundStyle(.secondary).fixedSize()
                DatePicker("", selection: dateBinding(for: $rangeEnd), in: minDate...maxDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(width: 88)
            }
            HStack(spacing: 6) {
                CheckBox(isOn: binding("column"))
                Text("Data column").frame(width: 64, alignment: .leading)
                Picker("", selection: $filterColumn) {
                    Text("<All>").tag("-")
                    ForEach(channels) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 202)
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 28)
                CheckBox(isOn: .constant(true)); Text("Min").foregroundStyle(.secondary)
                TextField("", text: $filterMin).textFieldStyle(.roundedBorder).frame(width: 54)
                CheckBox(isOn: .constant(true)); Text("Max").foregroundStyle(.secondary)
                TextField("", text: $filterMax).textFieldStyle(.roundedBorder).frame(width: 54)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func binding(_ mode: String) -> Binding<Bool> {
        Binding {
            filterMode == mode
        } set: { value in
            filterMode = value ? mode : "none"
        }
    }

    private func dateBinding(for text: Binding<String>) -> Binding<Date> {
        Binding {
            Self.parseDate(text.wrappedValue) ?? minDate
        } set: { value in
            text.wrappedValue = Self.formatDate(min(max(value, minDate), maxDate))
        }
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
