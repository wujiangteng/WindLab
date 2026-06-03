import SwiftUI

struct WindRoseView: View {
    let series: [NamedPolarSeries]
    let data: TimeSeriesData
    let fileURL: URL?

    @State private var display = "occurrences"
    @State private var versus = "all direction sensors"
    @State private var sectors = 16
    @State private var format = "chart"
    @State private var directionID = ""
    @State private var selectedDataColumns: Set<String> = []
    @State private var selectedSeries: Set<String> = []
    @State private var roseSeries: [NamedPolarSeries] = []
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

    private let displayOptions = ["occurrences", "frequency", "mean", "min", "max", "std. dev.", "total energy", "scatter plot"]
    private let normalVersusOptions = ["all direction sensors", "direction", "direction and month", "direction and hour", "direction and bin"]
    private let energyVersusOptions = ["direction", "direction and month"]
    private let sectorOptions = [4, 8, 12, 16, 18, 24, 36, 48, 72, 120, 180, 360]
    private let months = [("-", "<All>"), ("1", "Jan"), ("2", "Feb"), ("3", "Mar"), ("4", "Apr"), ("5", "May"), ("6", "Jun"), ("7", "Jul"), ("8", "Aug"), ("9", "Sep"), ("10", "Oct"), ("11", "Nov"), ("12", "Dec")]

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 360)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                PlotPanel(title: chartTitle) {
                    if visibleRoseSeries.isEmpty {
                        EmptyRosePlaceholder()
                    } else {
                        WindRoseChart(series: visibleRoseSeries, showsLegend: false)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                roseLegend
                    .frame(width: 170)
                    .padding(.top, 12)
                    .padding(.horizontal, 8)
            }
            .overlay(alignment: .topLeading) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                }
            }
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            resetDefaults()
            loadWindRose()
        }
        .onChange(of: data.channels) { _, _ in
            resetDefaults()
            loadWindRose()
        }
        .onChange(of: display) { _, _ in normalizeForDisplay(); loadWindRose() }
        .onChange(of: versus) { _, _ in loadWindRose() }
        .onChange(of: sectors) { _, _ in loadWindRose() }
        .onChange(of: directionID) { _, _ in loadWindRose() }
        .onChange(of: selectedDataColumns) { _, _ in loadWindRose() }
        .onChange(of: filterMode) { _, _ in loadWindRose() }
        .onChange(of: selectedYear) { _, _ in loadWindRose() }
        .onChange(of: selectedMonth) { _, _ in loadWindRose() }
        .onChange(of: rangeStart) { _, _ in loadWindRose() }
        .onChange(of: rangeEnd) { _, _ in loadWindRose() }
        .onChange(of: filterColumn) { _, _ in loadWindRose() }
        .onChange(of: filterMin) { _, _ in loadWindRose() }
        .onChange(of: filterMax) { _, _ in loadWindRose() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Display")
                    .frame(width: 92, alignment: .leading)
                CompactPicker(selection: $display, options: displayOptions)
                    .frame(width: 190)
            }
            .padding(.top, 10)

            HStack(spacing: 8) {
                Text("versus")
                    .frame(width: 92, alignment: .leading)
                CompactPicker(selection: $versus, options: versusOptions)
                    .frame(width: 190)
            }

            HStack(spacing: 10) {
                Text("Sectors")
                    .frame(width: 92, alignment: .leading)
                CompactNumberPicker(selection: $sectors, options: sectorOptions)
                    .frame(width: 64)
                Text("Format")
                    .padding(.leading, 8)
                FormatButton(systemName: "chart.bar.xaxis", isSelected: format == "chart") { format = "chart" }
                FormatButton(systemName: "tablecells", isSelected: format == "table") { format = "table" }
            }

            HStack(spacing: 10) {
                Text("Style")
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                DisabledToolButton(systemName: "gearshape")
                DisabledToolButton(systemName: "globe")
            }

            modeSpecificControls

            BinSettingsView()

            Spacer(minLength: 14)

            FilterPanel(
                directionName: currentDirectionName,
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
            .frame(height: 246)
            .padding(.bottom, 14)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .background(Color(.windowBackgroundColor))
    }

    @ViewBuilder
    private var modeSpecificControls: some View {
        if versus == "direction" || display == "total energy" {
            VStack(alignment: .leading, spacing: 8) {
                PickerField(label: "Direction sensor", selection: $directionID, options: directionChannels.map(\.id))
                HStack(alignment: .top, spacing: 8) {
                    Text("Data column")
                        .frame(width: 92, alignment: .leading)
                    Button("Clear All") {
                        selectedDataColumns.removeAll()
                    }
                    .controlSize(.small)
                    DataColumnChecklist(
                        channels: windRoseDataChannels,
                        selectedIDs: $selectedDataColumns,
                        enabledUnit: display == "total energy" ? "m/s" : nil
                    )
                    .frame(height: 190)
                }
            }
        } else {
            VStack(spacing: 7) {
                DisabledField(label: "Direction sensor", value: currentDirectionName)
                DisabledField(label: "Data column", value: currentDirectionName)
                DisabledField(label: "Bin column", value: currentDirectionName)
                DisabledField(label: "Speed sensor", value: firstSpeedName)
            }
        }
    }

    private var roseLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(roseSeries) { item in
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.chartColor(item.colorName))
                        .frame(width: 18, height: 3)
                    CheckBox(isOn: binding(for: item.name))
                    Text(item.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(height: 17)
            }
            if let loadError {
                Text(loadError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .background(Color(.windowBackgroundColor))
    }

    private var visibleRoseSeries: [NamedPolarSeries] {
        roseSeries.filter { selectedSeries.contains($0.name) }
    }

    private var directionChannels: [TimeSeriesChannel] {
        data.channels.filter { isAverageWindDirectionChannel($0) }
    }

    private var speedChannels: [TimeSeriesChannel] {
        data.channels.filter { isAverageWindSpeedChannel($0) }
    }

    private var windRoseDataChannels: [TimeSeriesChannel] {
        data.channels.filter { isAverageWindSpeedChannel($0) }
    }

    private var versusOptions: [String] {
        display == "total energy" ? energyVersusOptions : normalVersusOptions
    }

    private var chartTitle: String {
        if display == "total energy" {
            return "Proportion of Total Wind Energy vs. \(currentDirectionName)"
        }
        return display == "frequency" ? "Wind Direction Frequency" : "Wind Direction Occurrences"
    }

    private var currentDirectionName: String {
        directionChannels.first { $0.id == directionID }?.name ?? directionChannels.first?.name ?? ""
    }

    private var firstSpeedName: String {
        speedChannels.first?.name ?? ""
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding {
            selectedSeries.contains(id)
        } set: { newValue in
            if newValue {
                selectedSeries.insert(id)
            } else {
                selectedSeries.remove(id)
            }
        }
    }

    private func resetDefaults() {
        if directionID.isEmpty || !directionChannels.contains(where: { $0.id == directionID }) {
            directionID = directionChannels.first?.id ?? ""
        }
        let availableSpeedIDs = Set(speedChannels.map(\.id))
        let validSelection = selectedDataColumns.intersection(availableSpeedIDs)
        if validSelection.isEmpty {
            selectedDataColumns = availableSpeedIDs
        } else if validSelection != selectedDataColumns {
            selectedDataColumns = validSelection
        }
        if selectedYear == "-", let firstYear = data.years.first {
            selectedYear = String(firstYear)
        }
        if rangeStart.isEmpty {
            rangeStart = Self.formatDate(data.startDate)
        }
        if rangeEnd.isEmpty {
            rangeEnd = Self.formatDate(data.endDate)
        }
    }

    private func normalizeForDisplay() {
        if display == "total energy", !energyVersusOptions.contains(versus) {
            versus = "direction"
        }
    }

    private func loadWindRose() {
        guard let fileURL else {
            roseSeries = series
            selectedSeries = Set(series.map(\.name))
            return
        }
        normalizeForDisplay()
        let displayValue = display
        let versusValue = versus
        let sectorsValue = sectors
        let directionValue = directionID.isEmpty ? "-" : directionID
        let dataIDs = selectedDataColumns.sorted()
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
                let decoded = try WindogParser.parseWindRose(
                    fileURL: fileURL,
                    display: displayValue,
                    versus: versusValue,
                    sectors: sectorsValue,
                    directionID: directionValue,
                    dataIDs: dataIDs,
                    filterMode: filterValue,
                    year: yearValue,
                    month: monthValue,
                    rangeStart: rangeStartValue,
                    rangeEnd: rangeEndValue,
                    filterColumn: filterColumnValue,
                    filterMin: filterMinValue,
                    filterMax: filterMaxValue
                )
                let parsedSeries = decoded.series.map(NamedPolarSeries.init(decoded:))
                await MainActor.run {
                    roseSeries = parsedSeries
                    selectedSeries = Set(parsedSeries.map(\.name))
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

    private func isAverageWindSpeedChannel(_ channel: TimeSeriesChannel) -> Bool {
        guard channel.unit == "m/s" else { return false }
        return !isStatisticalChannel(channel)
    }

    private func isAverageWindDirectionChannel(_ channel: TimeSeriesChannel) -> Bool {
        channel.kind == "wind_direction" && !isStatisticalChannel(channel)
    }

    private func isStatisticalChannel(_ channel: TimeSeriesChannel) -> Bool {
        let name = channel.name.lowercased()
        let excludedTokens = ["_sd", "_std", "_max", "_min", "_gust", " sd", " std", " max", " min", " gust", "std. dev", "standard deviation"]
        if excludedTokens.contains(where: name.contains) {
            return true
        }
        let chineseExcludedTokens = ["标准差", "最大", "最小", "极大", "极小", "阵风"]
        return chineseExcludedTokens.contains(where: channel.name.contains)
    }
}

private struct CompactPicker: View {
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}

private struct CompactNumberPicker: View {
    @Binding var selection: Int
    let options: [Int]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text("\(option)").tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}

private struct PickerField: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 92, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }
}

private struct DataColumnChecklist: View {
    let channels: [TimeSeriesChannel]
    @Binding var selectedIDs: Set<String>
    let enabledUnit: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(channels) { channel in
                    let enabled = enabledUnit == nil || channel.unit == enabledUnit
                    HStack(spacing: 5) {
                        CheckBox(isOn: binding(for: channel.id, enabled: enabled))
                            .opacity(enabled ? 1 : 0.45)
                        Text(channel.name)
                            .font(.system(size: 11))
                            .foregroundStyle(enabled ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 18)
                }
            }
            .padding(5)
        }
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .overlay(Rectangle().stroke(Color(.separatorColor)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func binding(for id: String, enabled: Bool) -> Binding<Bool> {
        Binding {
            enabled && selectedIDs.contains(id)
        } set: { newValue in
            guard enabled else { return }
            if newValue {
                selectedIDs.insert(id)
            } else {
                selectedIDs.remove(id)
            }
        }
    }
}

private struct FormatButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 24, height: 22)
                .background(isSelected ? Color(.selectedControlColor).opacity(0.22) : Color(.controlBackgroundColor))
                .overlay(Rectangle().stroke(Color(.separatorColor)))
        }
        .buttonStyle(.plain)
    }
}

private struct DisabledToolButton: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12))
            .foregroundStyle(.secondary.opacity(0.6))
            .frame(width: 24, height: 22)
            .background(Color(.controlBackgroundColor).opacity(0.6))
            .overlay(Rectangle().stroke(Color(.separatorColor).opacity(0.7)))
    }
}

private struct DisabledField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 98, alignment: .leading)
            HStack {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(Color(.controlBackgroundColor).opacity(0.55))
            .overlay(Rectangle().stroke(Color(.separatorColor)))
        }
    }
}

private struct BinSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DividerWithTitle("Bin settings")
            HStack(spacing: 8) {
                CheckBox(isOn: .constant(false))
                Text("Width").foregroundStyle(.secondary)
                DisabledInput(value: "10")
                Text("deg").foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                CheckBox(isOn: .constant(false))
                Text("Make first bin\nhalf this width")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                CheckBox(isOn: .constant(false))
                Text("Start at").foregroundStyle(.secondary)
                DisabledInput(value: "0")
                Text("deg").foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct FilterPanel: View {
    let directionName: String
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
            DividerWithTitle("Filter by")
            HStack(spacing: 7) {
                CheckBox(isOn: .constant(true))
                Text("Flag").frame(width: 54, alignment: .leading)
                Text("Include").fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    HStack { CheckBox(isOn: .constant(true)); Text("<Unflagged data>") }
                    HStack { CheckBox(isOn: .constant(true)); Text("Synthesized") }
                }
            }
            HStack(spacing: 5) {
                CheckBox(isOn: dateBinding)
                Text("Date").frame(width: 62, alignment: .leading)
                Text("Year").foregroundStyle(.secondary).fixedSize()
                Picker("", selection: $selectedYear) {
                    ForEach(yearOptions, id: \.self) { year in Text(year == "-" ? "<All>" : year).tag(year) }
                }
                .labelsHidden()
                .frame(width: 62)
                Text("Month").foregroundStyle(.secondary).fixedSize()
                Picker("", selection: $selectedMonth) {
                    ForEach(months, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                .labelsHidden()
                .frame(width: 68)
            }
            HStack(spacing: 6) {
                CheckBox(isOn: rangeBinding)
                Text("Date range").frame(width: 62, alignment: .leading)
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
                CheckBox(isOn: columnBinding)
                Text("Data column").frame(width: 62, alignment: .leading)
                Picker("", selection: $filterColumn) {
                    Text(directionName.isEmpty ? "<All>" : directionName).tag("-")
                    ForEach(channels) { channel in
                        Text(channel.name).tag(channel.id)
                    }
                }
                .labelsHidden()
                .frame(width: 202)
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 28)
                CheckBox(isOn: .constant(true))
                Text("Min").foregroundStyle(.secondary)
                TextField("", text: $filterMin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                CheckBox(isOn: .constant(true))
                Text("Max").foregroundStyle(.secondary)
                TextField("", text: $filterMax)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
            }
            Text("Range: \(Self.formatDate(minDate)) to \(Self.formatDate(maxDate))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: rangeStart) { _, _ in clampRanges() }
        .onChange(of: rangeEnd) { _, _ in clampRanges() }
    }

    private var yearOptions: [String] {
        ["-"] + years.map(String.init)
    }

    private var dateBinding: Binding<Bool> {
        Binding {
            filterMode == "date"
        } set: { value in
            filterMode = value ? "date" : "none"
        }
    }

    private var rangeBinding: Binding<Bool> {
        Binding {
            filterMode == "range"
        } set: { value in
            filterMode = value ? "range" : "none"
        }
    }

    private var columnBinding: Binding<Bool> {
        Binding {
            filterMode == "column"
        } set: { value in
            filterMode = value ? "column" : "none"
        }
    }

    private func clampRanges() {
        if let start = Self.parseDate(rangeStart) {
            rangeStart = Self.formatDate(min(max(start, minDate), maxDate))
        }
        if let end = Self.parseDate(rangeEnd) {
            rangeEnd = Self.formatDate(min(max(end, minDate), maxDate))
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

private struct DividerWithTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Rectangle().fill(Color(.separatorColor)).frame(height: 1)
        }
    }
}

private struct DisabledInput: View {
    let value: String

    var body: some View {
        Text(value)
            .foregroundStyle(.secondary)
            .frame(width: 38, height: 20, alignment: .trailing)
            .padding(.trailing, 4)
            .background(Color(.controlBackgroundColor).opacity(0.6))
            .overlay(Rectangle().stroke(Color(.separatorColor).opacity(0.8)))
    }
}

private struct DisabledFilterRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            CheckBox(isOn: .constant(false))
            Text(label).frame(width: 70, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }
}

private struct EmptyRosePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No wind direction data")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
