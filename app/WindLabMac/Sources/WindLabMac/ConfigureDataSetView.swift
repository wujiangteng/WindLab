import AppKit
import SwiftUI

@MainActor
private final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    var onChange: ((NSColor) -> Void)?

    @objc func colorDidChange(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

struct ConfigureDataSetView: View {
    @State private var draft: DataSetConfiguration
    @State private var selectedColumnID: String?
    @State private var selectedTab = "Data Columns"
    @State private var previewLoadingID: String?
    @State private var previewError: String?
    @State private var isLoadingConfiguration = false
    @State private var configurationError: String?
    @State private var showsColorPalette = false
    let configuration: DataSetConfiguration
    let fileURL: URL?
    let apply: (DataSetConfiguration) -> Void
    let cancel: () -> Void

    init(configuration: DataSetConfiguration, fileURL: URL?, apply: @escaping (DataSetConfiguration) -> Void, cancel: @escaping () -> Void) {
        _draft = State(initialValue: configuration)
        _selectedColumnID = State(initialValue: configuration.columns.first?.id)
        self.configuration = configuration
        self.fileURL = fileURL
        self.apply = apply
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Configure Data Set")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)

            Picker("", selection: $selectedTab) {
                Text("Data Columns").tag("Data Columns")
                Text("Data Set").tag("Data Set")
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .padding(.bottom, 8)

            if selectedTab == "Data Columns" {
                dataColumnsView
            } else {
                dataSetView
            }

            HStack(spacing: 6) {
                Button("Help") {}
                    .frame(width: 72)
                Spacer()
                Button("Cancel", action: cancel)
                    .frame(width: 72)
                Button("OK") {
                    apply(draft)
                }
                .keyboardShortcut(.defaultAction)
                .frame(width: 72)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 1140, height: 820)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            ensureSelection()
        }
        .task {
            await loadConfigurationIfNeeded()
        }
        .onChange(of: configurationSignature) { _, _ in
            draft = configuration
            selectedColumnID = configuration.columns.first?.id
            previewLoadingID = nil
            previewError = nil
            configurationError = nil
        }
    }

    private let labelWidth: CGFloat = 286
    private let unitWidth: CGFloat = 70
    private let colorWidth: CGFloat = 60
    private let heightWidth: CGFloat = 76
    private let statWidth: CGFloat = 78

    private var tableWidth: CGFloat {
        labelWidth + unitWidth + colorWidth + heightWidth + statWidth * 3
    }

    private var dataColumnsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Add Column...", action: addColumn)
                Button("Delete Column(s)", action: deleteSelectedColumn)
                    .disabled(selectedColumnID == nil)
                Spacer()
                Button("Assign Default Colors to All Columns", action: assignDefaultColors)
                Spacer()
                Button("Save Template...") {}
                    .disabled(true)
                Button("Load Template...") {}
                    .disabled(true)
            }
            .font(.system(size: 12))

            HStack(spacing: 8) {
                columnTable
                    .frame(width: tableWidth)
                Divider()
                columnProperties
                    .frame(width: 350)
            }

            HStack(spacing: 8) {
                PDFPreviewChart(column: selectedColumn, isLoading: isSelectedPreviewLoading, errorMessage: previewError)
                DiurnalPreviewChart(column: selectedColumn, isLoading: isSelectedPreviewLoading, errorMessage: previewError)
                MonthlyStatisticsPreviewChart(column: selectedColumn, isLoading: isSelectedPreviewLoading, errorMessage: previewError)
            }
            .frame(height: 178)
        }
        .padding(.horizontal, 10)
        .task(id: selectedColumnID) {
            await loadSelectedPreviewIfNeeded()
        }
    }

    private var columnTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tableHeader("Label", width: labelWidth, alignment: .leading, leadingInset: 22)
                tableHeader("Units", width: unitWidth)
                tableHeader("", width: colorWidth)
                tableHeader("Height", width: heightWidth)
                tableHeader("Mean", width: statWidth)
                tableHeader("Min", width: statWidth)
                tableHeader("Max", width: statWidth)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(draft.columns) { column in
                        columnRow(column)
                    }
                }
            }
            .background(Color.white)
            .overlay {
                Rectangle().stroke(Color(.separatorColor), lineWidth: 1)
            }
            .overlay {
                if isLoadingConfiguration || configurationError != nil || draft.columns.isEmpty {
                    configurationStatusOverlay
                }
            }
        }
    }

    private func columnRow(_ column: DataColumnConfiguration) -> some View {
        Button {
            selectedColumnID = column.id
            previewError = nil
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: column.type))
                        .foregroundStyle(Color.chartColor(column.colorName))
                        .frame(width: 16)
                    Text(column.label)
                        .lineLimit(1)
                    Spacer()
                }
                .frame(width: labelWidth, height: 22)
                Text(column.unit).frame(width: unitWidth, height: 22)
                Rectangle()
                    .fill(Color.chartColor(column.colorName))
                    .frame(width: colorWidth, height: 22)
                Text(heightText(column.height)).frame(width: heightWidth, height: 22)
                Text(column.mean).frame(width: statWidth, height: 22)
                Text(column.min).frame(width: statWidth, height: 22)
                Text(column.max).frame(width: statWidth, height: 22)
            }
            .font(.system(size: 12))
            .background(selectedColumnID == column.id ? Color.accentColor.opacity(0.20) : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var columnProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data column properties")
            if let binding = selectedColumnBinding {
                configRow("Type") {
                    Picker("", selection: binding.type) {
                        ForEach(columnTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                configRow("Subtype") {
                    Text(binding.wrappedValue.subtype)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                configRow("Label") {
                    TextField("", text: binding.label)
                        .textFieldStyle(.roundedBorder)
                }
                configRow("Units") {
                    TextField("", text: binding.unit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                configRow("Color") {
                    colorControl(binding.colorName)
                }
                configRow("Height") {
                    TextField("", value: binding.height, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("m")
                }
                Toggle("Visible", isOn: binding.visible)
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)

                sectionHeader("Associated data columns")
                    .padding(.top, 14)
                associationPicker("Std. dev.", binding.associated.stdDev)
                associationPicker("Max.", binding.associated.max)
                associationPicker("Min.", binding.associated.min)
                associationPicker("Speed", binding.associated.speed)

                Spacer()
                Button("Edit Calculation Properties...") {}
                    .disabled(true)
                    .frame(width: 230)
                Button("Make Static Copy") {}
                    .disabled(true)
                    .frame(width: 230)
            } else {
                Text("No data column selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.system(size: 12))
        .padding(10)
    }

    private var dataSetView: some View {
        VStack(alignment: .leading, spacing: 22) {
            dataSetSection("Site information") {
                formRow("Name") {
                    TextField("", text: $draft.dataSet.name)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text("Description")
                        .frame(width: 130, alignment: .trailing)
                    TextEditor(text: $draft.dataSet.description)
                        .frame(height: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3).stroke(Color(.separatorColor))
                        }
                }
            }

            dataSetSection("Location") {
                formRow("Latitude") {
                    TextField("", value: $draft.dataSet.latitude, format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("° N")
                }
                formRow("Longitude") {
                    TextField("", value: $draft.dataSet.longitude, format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("° E")
                }
                formRow("Elevation") {
                    TextField("", value: $draft.dataSet.elevation, format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("m above sea level")
                    Button("Map") {}
                        .disabled(true)
                }
            }

            dataSetSection("Date and time") {
                staticRow("Data set starts:", draft.dataSet.start)
                staticRow("Data set ends:", draft.dataSet.end)
                staticRow("Data set duration:", draft.dataSet.duration)
                staticRow("Length of time step:", draft.dataSet.timeStep)
                formRow("Time stamps indicate") {
                    Picker("", selection: $draft.dataSet.timestampsIndicate) {
                        Text("Start").tag("Start")
                        Text("End").tag("End")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Text("of time step")
                }
            }

            dataSetSection("Other") {
                formRow("Calm threshold") {
                    TextField("", value: $draft.dataSet.calmThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Text("m/s")
                }
                formRow("Invalid value") {
                    TextField("", value: $draft.dataSet.invalidValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                if !draft.dataSet.metadataSource.isEmpty {
                    Text(draft.dataSet.metadataSource)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 142)
                }
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 90)
        .padding(.top, 30)
    }

    private var selectedColumnBinding: Binding<DataColumnConfiguration>? {
        guard let selectedColumnID,
              let index = draft.columns.firstIndex(where: { $0.id == selectedColumnID }) else {
            return nil
        }
        return $draft.columns[index]
    }

    private var selectedColumn: DataColumnConfiguration? {
        guard let selectedColumnID else { return draft.columns.first }
        return draft.columns.first { $0.id == selectedColumnID }
    }

    private var isSelectedPreviewLoading: Bool {
        guard selectedColumnID != nil else { return false }
        return previewLoadingID == selectedColumnID
    }

    private func loadSelectedPreviewIfNeeded() async {
        guard let fileURL, let selectedColumnID else { return }
        guard let index = draft.columns.firstIndex(where: { $0.id == selectedColumnID }) else { return }
        let preview = draft.columns[index].preview
        guard preview.pdf.isEmpty && preview.diurnal.isEmpty && preview.monthly.isEmpty else { return }

        await MainActor.run {
            previewLoadingID = selectedColumnID
            previewError = nil
        }

        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try WindogParser.parseConfigurationPreview(fileURL: fileURL, channelID: selectedColumnID)
            }.value
            let mapped = ColumnPreview(decoded: decoded)
            await MainActor.run {
                if let currentIndex = draft.columns.firstIndex(where: { $0.id == selectedColumnID }) {
                    draft.columns[currentIndex].preview = mapped
                }
                if previewLoadingID == selectedColumnID {
                    previewLoadingID = nil
                }
            }
        } catch {
            await MainActor.run {
                if previewLoadingID == selectedColumnID {
                    previewLoadingID = nil
                }
                previewError = error.localizedDescription
            }
        }
    }

    private var configurationStatusOverlay: some View {
        ZStack {
            Color.white.opacity(0.88)
            VStack(spacing: 8) {
                if isLoadingConfiguration {
                    ProgressView()
                    Text("Loading data columns...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let configurationError {
                    Text(configurationError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    Text("No data columns loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadConfigurationIfNeeded() async {
        guard draft.columns.isEmpty, !isLoadingConfiguration, let fileURL else {
            ensureSelection()
            return
        }
        await MainActor.run {
            isLoadingConfiguration = true
            configurationError = nil
        }
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try WindogParser.parseConfiguration(fileURL: fileURL)
            }.value
            let loaded = DataSetConfiguration(decoded: decoded)
            await MainActor.run {
                draft = loaded
                selectedColumnID = loaded.columns.first?.id
                isLoadingConfiguration = false
                configurationError = nil
            }
        } catch {
            await MainActor.run {
                isLoadingConfiguration = false
                configurationError = error.localizedDescription
            }
        }
    }

    private var configurationSignature: String {
        configuration.columns.map(\.id).joined(separator: "\u{1f}")
    }

    private func ensureSelection() {
        if selectedColumnID == nil {
            selectedColumnID = draft.columns.first?.id
        }
    }

    private var columnTypes: [String] {
        ["Wind Speed", "Vert. Wind Speed", "Wind Direction", "Temperature", "Air Pressure", "Relative Humidity", "Wind Turbine Output", "Quality", "Other"]
    }

    private var colorNames: [String] {
        ["measured", "primary", "secondary", "accent", "brown", "violet", "yellow", "green2", "red", "purple", "orange", "blue2", "blue3", "blue4", "blue5", "blue6", "blue7", "blue8"]
    }

    private var presetColorHexes: [String] {
        [
            "#FF6F72", "#FFF86A", "#7AF07A", "#00E878", "#79E0E3", "#147FE8", "#EF69AE", "#E861E8",
            "#FF2A10", "#FFF000", "#63F000", "#08E83F", "#12CFCF", "#0F83B5", "#7F7DBB", "#EF2BE4",
            "#874140", "#FF7C3E", "#00E000", "#087C72", "#0E3F78", "#7678EE", "#8A0E42", "#F92B72",
            "#951000", "#FF8300", "#007F00", "#078143", "#1D36F2", "#0F2394", "#84208A", "#782FF0",
            "#590800", "#8A4D00", "#004C09", "#084D48", "#151D83", "#06093A", "#460B46", "#3A1678",
            "#000000", "#838700", "#848944", "#808080", "#3E8580", "#B8B8B8", "#4A084A", "#FFFFFF"
        ]
    }

    private var allColumnNames: [String] {
        ["<none>", "<nearest in height>"] + draft.columns.map(\.label)
    }

    private func tableHeader(_ text: String, width: CGFloat, alignment: Alignment = .center, leadingInset: CGFloat = 0) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.leading, leadingInset)
            .frame(width: width, height: 22, alignment: alignment)
            .background(Color(.controlBackgroundColor))
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
            Rectangle().fill(Color(.separatorColor)).frame(height: 1)
        }
    }

    private func configRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }

    private func associationPicker(_ label: String, _ selection: Binding<String>) -> some View {
        configRow(label) {
            Picker("", selection: selection) {
                ForEach(allColumnNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
        }
    }

    private func colorControl(_ colorName: Binding<String>) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.chartColor(colorName.wrappedValue))
                .frame(width: 48, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                }

            Button("More") {
                showsColorPalette.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(width: 56, height: 24)
            .popover(isPresented: $showsColorPalette, arrowEdge: .bottom) {
                colorPalette(colorName)
            }
        }
    }

    private func colorPalette(_ colorName: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Basic colors")
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), spacing: 6) {
                ForEach(presetColorHexes, id: \.self) { hex in
                    Button {
                        colorName.wrappedValue = hex
                        showsColorPalette = false
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.chartColor(hex))
                            .frame(width: 24, height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Button("Custom Color...") {
                showsColorPalette = false
                showColorPanel(for: colorName)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func hexString(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        let red = max(0, min(255, Int(round(nsColor.redComponent * 255))))
        let green = max(0, min(255, Int(round(nsColor.greenComponent * 255))))
        let blue = max(0, min(255, Int(round(nsColor.blueComponent * 255))))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func showColorPanel(for colorName: Binding<String>) {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.color = NSColor(Color.chartColor(colorName.wrappedValue)).usingColorSpace(.sRGB) ?? .systemBlue
        ColorPanelBridge.shared.onChange = { color in
            colorName.wrappedValue = hexString(from: Color(nsColor: color))
        }
        panel.setTarget(ColorPanelBridge.shared)
        panel.setAction(#selector(ColorPanelBridge.colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    private func dataSetSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            content()
        }
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func staticRow(_ label: String, _ value: String) -> some View {
        formRow(label) {
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func miniPanel(title: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 18)
            Rectangle()
                .fill(Color.white)
                .overlay {
                    ChartGrid(
                        xTicks: [0, 0.5, 1],
                        yTicks: [0, 0.5, 1],
                        xRange: 0...1,
                        yRange: 0...1,
                        origin: CGPoint(x: 24, y: 10),
                        size: CGSize(width: 230, height: 94)
                    )
                }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func heightText(_ height: Double?) -> String {
        guard let height else { return "" }
        return height.rounded() == height ? "\(Int(height)) m" : String(format: "%.1f m", height)
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "Wind Direction": return "location.north"
        case "Relative Humidity": return "drop.fill"
        case "Temperature": return "thermometer.medium"
        case "Air Pressure": return "barometer"
        case "Quality": return "star"
        default: return "wind"
        }
    }

    private func addColumn() {
        let newColumn = DataColumnConfiguration(
            id: "New Column \(draft.columns.count + 1)",
            label: "New Column",
            unit: "",
            type: "Other",
            subtype: "Mean",
            colorName: colorNames[draft.columns.count % colorNames.count],
            height: nil,
            visible: true,
            mean: "-",
            min: "-",
            max: "-",
            associated: AssociatedColumns(stdDev: "<none>", min: "<none>", max: "<none>", speed: "<none>"),
            preview: .empty
        )
        draft.columns.append(newColumn)
        selectedColumnID = newColumn.id
    }

    private func deleteSelectedColumn() {
        guard let selectedColumnID else { return }
        draft.columns.removeAll { $0.id == selectedColumnID }
        self.selectedColumnID = draft.columns.first?.id
    }

    private func assignDefaultColors() {
        for index in draft.columns.indices {
            draft.columns[index].colorName = colorNames[index % colorNames.count]
        }
    }
}

private struct PreviewPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            content
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct PreviewAxisScale {
    let range: ClosedRange<Double>
    let ticks: [Double]
}

private func previewYAxisScale(for column: DataColumnConfiguration?, values: [Double], fallback: ClosedRange<Double> = 0...1) -> PreviewAxisScale {
    switch column?.type {
    case "Wind Direction":
        return PreviewAxisScale(range: 0...360, ticks: [0, 90, 180, 270, 360])
    case "Relative Humidity":
        return PreviewAxisScale(range: 0...100, ticks: [0, 25, 50, 75, 100])
    case "Air Pressure":
        return niceAxis(values: values, fallback: 95...105, includeZero: false, maxTickCount: 5)
    default:
        return niceAxis(values: values, fallback: fallback, includeZero: column?.unit == "m/s", maxTickCount: 5)
    }
}

private func previewPDFXAxisScale(for column: DataColumnConfiguration?, bars: [HistogramBar]) -> PreviewAxisScale {
    switch column?.type {
    case "Wind Direction":
        return PreviewAxisScale(range: 0...360, ticks: [0, 90, 180, 270, 360])
    case "Relative Humidity":
        return PreviewAxisScale(range: 0...100, ticks: [0, 25, 50, 75, 100])
    case "Air Pressure":
        let values = bars.flatMap { [$0.x - $0.width / 2, $0.x + $0.width / 2] }
        return niceAxis(values: values, fallback: 95...105, includeZero: false, maxTickCount: 5)
    default:
        let upper = max(bars.map { $0.x + $0.width / 2 }.max() ?? 1, 1)
        return niceAxis(values: [0, upper], fallback: 0...1, includeZero: true, maxTickCount: 5)
    }
}

private func niceAxis(values: [Double], fallback: ClosedRange<Double>, includeZero: Bool, maxTickCount: Int) -> PreviewAxisScale {
    let finite = values.filter(\.isFinite)
    guard var lower = finite.min(), var upper = finite.max() else {
        return PreviewAxisScale(range: fallback, ticks: niceTicks(for: fallback, maxTickCount: maxTickCount))
    }
    if includeZero {
        lower = min(0, lower)
        upper = max(0, upper)
    }
    if abs(upper - lower) < 1e-9 {
        let padding = max(abs(upper) * 0.1, 1)
        lower -= padding
        upper += padding
    }
    let padding = max((upper - lower) * 0.06, 1e-9)
    lower = includeZero ? min(0, lower) : lower - padding
    upper += padding
    let ticks = niceTicks(for: lower...upper, maxTickCount: maxTickCount)
    return PreviewAxisScale(range: (ticks.first ?? lower)...(ticks.last ?? upper), ticks: ticks)
}

private func niceTicks(for range: ClosedRange<Double>, maxTickCount: Int) -> [Double] {
    let span = max(range.upperBound - range.lowerBound, 1e-9)
    let rawStep = span / Double(max(maxTickCount - 1, 1))
    let magnitude = pow(10, floor(log10(rawStep)))
    let residual = rawStep / magnitude
    let niceResidual: Double
    if residual <= 1 {
        niceResidual = 1
    } else if residual <= 2 {
        niceResidual = 2
    } else if residual <= 5 {
        niceResidual = 5
    } else {
        niceResidual = 10
    }
    let step = niceResidual * magnitude
    let start = floor(range.lowerBound / step) * step
    let end = ceil(range.upperBound / step) * step
    return Array(stride(from: start, through: end + step * 0.5, by: step)).filter { $0 >= start - 1e-9 && $0 <= end + 1e-9 }
}

private struct PDFPreviewChart: View {
    let column: DataColumnConfiguration?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        PreviewPanel(title: "PDF") {
            GeometryReader { geometry in
                let bars = column?.preview.pdf ?? []
                let xScale = previewPDFXAxisScale(for: column, bars: bars)
                let yScale = niceAxis(values: bars.map(\.y), fallback: 0...1, includeZero: true, maxTickCount: 5)
                let frame = PlotFrame(size: geometry.size, left: 36, right: 8, top: 8, bottom: 32)
                ZStack(alignment: .topLeading) {
                    PreviewGrid(frame: frame, xTicks: xScale.ticks, yTicks: yScale.ticks, xRange: xScale.range, yRange: yScale.range)
                    ForEach(bars) { bar in
                        let x0 = frame.x(bar.x - bar.width / 2, in: xScale.range)
                        let x1 = frame.x(bar.x + bar.width / 2, in: xScale.range)
                        let y = frame.y(bar.y, in: yScale.range)
                        Rectangle()
                            .fill(Color.chartColor(column?.colorName ?? "primary"))
                            .overlay(Rectangle().stroke(.black, lineWidth: 0.5))
                            .frame(width: max(x1 - x0, 1), height: frame.bottomY - y)
                            .position(x: (x0 + x1) / 2, y: y + (frame.bottomY - y) / 2)
                    }
                    PreviewAxes(frame: frame, xTicks: xScale.ticks, yTicks: yScale.ticks, xRange: xScale.range, yRange: yScale.range, xLabel: "Value (\(column?.unit ?? "-"))", yLabel: "Frequency (%)")
                    PreviewStatusOverlay(isLoading: isLoading, errorMessage: errorMessage, isEmpty: bars.isEmpty)
                }
            }
        }
    }
}

private struct DiurnalPreviewChart: View {
    let column: DataColumnConfiguration?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        PreviewPanel(title: "Mean Diurnal Profile") {
            GeometryReader { geometry in
                let points = column?.preview.diurnal ?? []
                let values = points.map(\.y)
                let yScale = previewYAxisScale(for: column, values: values, fallback: 0...2)
                let frame = PlotFrame(size: geometry.size, left: 36, right: 8, top: 8, bottom: 32)
                ZStack(alignment: .topLeading) {
                    PreviewGrid(frame: frame, xTicks: [0, 6, 12, 18, 24], yTicks: yScale.ticks, xRange: 0...24, yRange: yScale.range)
                    ForEach(points) { point in
                        let x0 = frame.x(point.x, in: 0...24)
                        let x1 = frame.x(point.x + 1, in: 0...24)
                        let y = frame.y(point.y, in: yScale.range)
                        Rectangle()
                            .fill(Color.chartColor(column?.colorName ?? "primary"))
                            .overlay(Rectangle().stroke(.black, lineWidth: 0.5))
                            .frame(width: max(x1 - x0 - 1, 1), height: frame.bottomY - y)
                            .position(x: (x0 + x1) / 2, y: y + (frame.bottomY - y) / 2)
                    }
                    PreviewAxes(frame: frame, xTicks: [0, 6, 12, 18, 24], yTicks: yScale.ticks, xRange: 0...24, yRange: yScale.range, xLabel: "Time Of Day", yLabel: "Mean Value (\(column?.unit ?? "-"))")
                    PreviewStatusOverlay(isLoading: isLoading, errorMessage: errorMessage, isEmpty: points.isEmpty)
                }
            }
        }
    }
}

private struct MonthlyStatisticsPreviewChart: View {
    let column: DataColumnConfiguration?
    let isLoading: Bool
    let errorMessage: String?
    private let labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        PreviewPanel(title: "Monthly Statistics for \(column?.label ?? "")") {
            GeometryReader { geometry in
                let stats = column?.preview.monthly ?? []
                let values = stats.flatMap { [$0.min, $0.q1, $0.mean, $0.q3, $0.max] }
                let yScale = previewYAxisScale(for: column, values: values, fallback: 0...5)
                let xTicks = Array(0..<12).map { Double($0) + 0.5 }
                let frame = PlotFrame(size: geometry.size, left: 36, right: 42, top: 8, bottom: 32)
                ZStack(alignment: .topLeading) {
                    PreviewGrid(frame: frame, xTicks: xTicks, yTicks: yScale.ticks, xRange: 0...12, yRange: yScale.range)
                    ForEach(stats) { item in
                        let center = frame.x(item.x + 0.5, in: 0...12)
                        let minY = frame.y(item.min, in: yScale.range)
                        let maxY = frame.y(item.max, in: yScale.range)
                        let q1Y = frame.y(item.q1, in: yScale.range)
                        let q3Y = frame.y(item.q3, in: yScale.range)
                        let meanY = frame.y(item.mean, in: yScale.range)
                        Path { path in
                            path.move(to: CGPoint(x: center, y: maxY))
                            path.addLine(to: CGPoint(x: center, y: minY))
                        }
                        .stroke(.black, lineWidth: 1)
                        Rectangle()
                            .fill(Color.chartColor(column?.colorName ?? "primary"))
                            .overlay(Rectangle().stroke(.black, lineWidth: 0.6))
                            .frame(width: 12, height: max(q1Y - q3Y, 1))
                            .position(x: center, y: (q1Y + q3Y) / 2)
                        Path { path in
                            path.move(to: CGPoint(x: center - 7, y: meanY))
                            path.addLine(to: CGPoint(x: center + 7, y: meanY))
                        }
                        .stroke(.black, lineWidth: 1)
                    }
                    PreviewAxes(frame: frame, xTicks: xTicks, yTicks: yScale.ticks, xRange: 0...12, yRange: yScale.range, xLabels: labels, xLabel: "", yLabel: "")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("max")
                        Text("q3")
                        Text("mean")
                        Text("q1")
                        Text("min")
                    }
                    .font(.system(size: 9))
                    .position(x: frame.rightX + 22, y: frame.topY + 34)
                    PreviewStatusOverlay(isLoading: isLoading, errorMessage: errorMessage, isEmpty: stats.isEmpty)
                }
            }
        }
    }
}

private struct PreviewStatusOverlay: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool

    var body: some View {
        if isLoading || errorMessage != nil || isEmpty {
            ZStack {
                Color.white.opacity(0.78)
                VStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Select a column")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
        }
    }
}

private struct PlotFrame {
    let size: CGSize
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    var origin: CGPoint { CGPoint(x: left, y: top) }
    var plotSize: CGSize { CGSize(width: max(size.width - left - right, 10), height: max(size.height - top - bottom, 10)) }
    var bottomY: CGFloat { top + plotSize.height }
    var rightX: CGFloat { left + plotSize.width }
    var topY: CGFloat { top }

    func x(_ value: Double, in range: ClosedRange<Double>) -> CGFloat {
        left + CGFloat((value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1e-9)) * plotSize.width
    }

    func y(_ value: Double, in range: ClosedRange<Double>) -> CGFloat {
        top + plotSize.height - CGFloat((value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1e-9)) * plotSize.height
    }
}

private func ceilToMultiple(_ value: Double, step: Double) -> Double {
    max(step, ceil(value / step) * step)
}

private func multipleTicks(through upper: Double, step: Double) -> [Double] {
    Array(stride(from: 0.0, through: upper, by: step))
}

private struct PreviewGrid: View {
    let frame: PlotFrame
    let xTicks: [Double]
    let yTicks: [Double]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for index in 0...10 {
                    let x = frame.left + frame.plotSize.width * CGFloat(index) / 10
                    path.move(to: CGPoint(x: x, y: frame.top))
                    path.addLine(to: CGPoint(x: x, y: frame.bottomY))
                }
                for index in 0...6 {
                    let y = frame.top + frame.plotSize.height * CGFloat(index) / 6
                    path.move(to: CGPoint(x: frame.left, y: y))
                    path.addLine(to: CGPoint(x: frame.rightX, y: y))
                }
            }
            .stroke(Color(red: 0.92, green: 0.92, blue: 0.92), lineWidth: 0.6)
            Path { path in
                for tick in xTicks {
                    let x = frame.x(tick, in: xRange)
                    path.move(to: CGPoint(x: x, y: frame.top))
                    path.addLine(to: CGPoint(x: x, y: frame.bottomY))
                }
                for tick in yTicks {
                    let y = frame.y(tick, in: yRange)
                    path.move(to: CGPoint(x: frame.left, y: y))
                    path.addLine(to: CGPoint(x: frame.rightX, y: y))
                }
            }
            .stroke(Color(red: 0.78, green: 0.78, blue: 0.78), lineWidth: 0.8)
            Rectangle()
                .stroke(Color.black, lineWidth: 0.8)
                .frame(width: frame.plotSize.width, height: frame.plotSize.height)
                .position(x: frame.left + frame.plotSize.width / 2, y: frame.top + frame.plotSize.height / 2)
        }
    }
}

private struct PreviewAxes: View {
    let frame: PlotFrame
    let xTicks: [Double]
    let yTicks: [Double]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    var xLabels: [String]? = nil
    let xLabel: String
    let yLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                Text(format(tick))
                    .font(.system(size: 9))
                    .position(x: frame.left - 18, y: frame.y(tick, in: yRange))
            }
            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, tick in
                Text(xLabels?[safe: index] ?? format(tick))
                    .font(.system(size: 9))
                    .position(x: frame.x(tick, in: xRange), y: frame.bottomY + 12)
            }
            if !xLabel.isEmpty {
                Text(xLabel)
                    .font(.system(size: 9))
                    .position(x: frame.left + frame.plotSize.width / 2, y: frame.bottomY + 25)
            }
            if !yLabel.isEmpty {
                Text(yLabel)
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(-90))
                    .position(x: 9, y: frame.top + frame.plotSize.height / 2)
            }
        }
    }

    private func format(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}
