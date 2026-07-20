import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var fileOpenCoordinator: WindLabFileOpenCoordinator

    @State private var selectedTab = "Summary"
    @State private var propertySections: [PropertySection] = []
    @State private var sourcePropertySections: [PropertySection] = []
    @State private var chartData = AppChartData.sample
    @State private var sourceChartData = AppChartData.sample
    @State private var loadedFileName = "No file loaded"
    @State private var parserError: String?
    @State private var isLoadingWindog = false
    @State private var hasLoadedFile = false
    @State private var loadedFileURL: URL?
    @State private var showsDistributionAnalysis = false
    @State private var showsConfiguration = false
    @State private var isLoadingConfiguration = false
    @State private var dataSetConfiguration = DataSetConfiguration.empty
    @State private var pendingTextImportURL: URL?
    @State private var lastOpenPanelRequestID = 0
    @State private var lastSaveRequestID = 0
    @State private var lastSaveAsRequestID = 0

    private let tabs = ["Summary", "Time Series", "Wind Rose", "Diurnal Profile", "Histogram", "Scatter Plot", "Tables", "Reports"]
    private let toolbarItems: [(String, String)] = [
        ("doc", "New project"),
        ("folder", "Open"),
        ("square.and.arrow.down", "Save"),
        ("tablecells", "Import data"),
        ("clock", "Time settings"),
        ("gearshape", "Configuration"),
        ("pencil", "Edit properties"),
        ("line.3.horizontal.decrease", "Filter"),
        ("flag.fill", "Flag data"),
        ("flag.slash", "Clear flag"),
        ("magnifyingglass", "Inspect"),
        ("percent", "Frequency"),
        ("chart.bar", "Histogram"),
        ("arrow.triangle.2.circlepath", "Refresh")
    ]

    var body: some View {
        VStack(spacing: 0) {
            menuStrip
            iconToolbar
            tabStrip

            if hasLoadedFile {
                HStack(spacing: 0) {
                    if selectedTab == "Time Series" {
                        timeSeriesView
                    } else if selectedTab == "Wind Rose" {
                        windRoseView
                    } else if selectedTab == "Histogram" {
                        histogramView
                    } else if selectedTab == "Summary" {
                        SummarySidebar(
                            sections: propertySections,
                            fileName: loadedFileName,
                            parserError: parserError,
                            isLoading: isLoadingWindog
                        )
                            .frame(width: 300)

                        Divider()
                        chartsView
                    } else {
                        BlankTabView(title: selectedTab)
                    }
                }
            } else {
                EmptyFileView(
                    parserError: parserError,
                    isLoading: isLoadingWindog,
                    openAction: openWindogFile,
                    openURLAction: openWindogURL
                )
            }
        }
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showsDistributionAnalysis) {
            DistributionAnalysisView(data: chartData.timeSeries, fileURL: loadedFileURL) {
                showsDistributionAnalysis = false
            }
        }
        .sheet(isPresented: $showsConfiguration) {
            ConfigureDataSetView(configuration: dataSetConfiguration, fileURL: loadedFileURL) { updated in
                applyConfiguration(updated)
                showsConfiguration = false
                if let pendingURL = pendingTextImportURL {
                    pendingTextImportURL = nil
                    loadWindog(pendingURL, preserveConfiguration: true)
                }
            } cancel: {
                showsConfiguration = false
                if pendingTextImportURL != nil {
                    pendingTextImportURL = nil
                    loadedFileURL = nil
                    loadedFileName = "No file loaded"
                    dataSetConfiguration = .empty
                }
            }
            .id(dataSetConfiguration.columns.map(\.id).joined(separator: "\u{1f}"))
        }
        .onAppear {
            openPendingWindogURL()
        }
        .onOpenURL { url in
            openWindogURL(url)
        }
        .onReceive(fileOpenCoordinator.$requestedURL.compactMap { $0 }) { url in
            openPendingWindogURL(url)
        }
        .onReceive(fileOpenCoordinator.$openPanelRequestID) { requestID in
            guard requestID != lastOpenPanelRequestID else { return }
            lastOpenPanelRequestID = requestID
            guard requestID > 0 else { return }
            openWindogFile()
        }
        .onReceive(fileOpenCoordinator.$saveRequestID) { requestID in
            guard requestID != lastSaveRequestID else { return }
            lastSaveRequestID = requestID
            guard requestID > 0 else { return }
            saveWindog()
        }
        .onReceive(fileOpenCoordinator.$saveAsRequestID) { requestID in
            guard requestID != lastSaveAsRequestID else { return }
            lastSaveAsRequestID = requestID
            guard requestID > 0 else { return }
            saveWindogAs()
        }
    }

    private var menuStrip: some View {
        HStack(spacing: 22) {
            fileMenu
            MenuText("View")
            MenuText("Revise")
            MenuText("Flag")
            MenuText("Analyze")
            MenuText("Compare")
            MenuText("Tools")
            MenuText("Window")
            MenuText("Help")

            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var fileMenu: some View {
        Menu {
            Button("Open Windographer File...") {
                openWindogFile()
            }

            Button("Save") {
                saveWindog()
            }
            .disabled(!canSaveWindog)

            Button("Save As...") {
                saveWindogAs()
            }
            .disabled(!canSaveWindog)

            Menu("Open Recent") {
                if fileOpenCoordinator.recentFiles.isEmpty {
                    Text("No Recent Files")
                } else {
                    ForEach(fileOpenCoordinator.recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            openWindogURL(url)
                        }
                        .help(url.path)
                    }
                }
            }
        } label: {
            Text("File")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .underline()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var iconToolbar: some View {
        HStack(spacing: 5) {
            ForEach(toolbarItems, id: \.1) { item in
                Button {
                    if item.1 == "Open" {
                        openWindogFile()
                    } else if item.1 == "Save" {
                        saveWindog()
                    } else if item.1 == "Histogram" {
                        showsDistributionAnalysis = true
                    } else if item.1 == "Configuration" {
                        openConfiguration()
                    }
                } label: {
                    Image(systemName: item.0)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ToolIconButtonStyle())
                .help(item.1)
            }
            Divider()
                .frame(height: 22)
                .padding(.horizontal, 3)
            Button {} label: {
                Image(systemName: "wind")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .blue)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(ToolIconButtonStyle())
            .help("Run wind analysis")
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(selectedTab == tab ? Color(.windowBackgroundColor) : Color(.controlBackgroundColor))
                        .overlay {
                            Rectangle()
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.leading, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func openWindogFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Windographer File"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "windog"),
            .plainText,
            .commaSeparatedText,
            .tabSeparatedText,
        ].compactMap { $0 }
        panel.allowsOtherFileTypes = false

        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else {
                return
            }
            openWindogURL(fileURL)
        }
    }

    private func openWindogURL(_ fileURL: URL) {
        if isTextDataFile(fileURL) {
            configureTextImport(fileURL)
        } else {
            loadWindog(fileURL)
        }
    }

    private func openPendingWindogURL(_ url: URL? = nil) {
        guard let fileURL = url ?? fileOpenCoordinator.requestedURL else {
            return
        }

        fileOpenCoordinator.requestedURL = nil
        openWindogURL(fileURL)
    }

    private func isTextDataFile(_ fileURL: URL) -> Bool {
        ["txt", "csv", "tsv"].contains(fileURL.pathExtension.lowercased())
    }

    private var canSaveWindog: Bool {
        guard hasLoadedFile, let loadedFileURL else { return false }
        return loadedFileURL.pathExtension.lowercased() == "windog"
    }

    private func configureTextImport(_ fileURL: URL) {
        isLoadingWindog = true
        parserError = nil
        hasLoadedFile = false
        loadedFileName = fileURL.lastPathComponent
        loadedFileURL = fileURL
        pendingTextImportURL = fileURL
        dataSetConfiguration = .empty

        Task.detached {
            do {
                let decoded = try WindogParser.parseConfiguration(fileURL: fileURL)
                await MainActor.run {
                    dataSetConfiguration = DataSetConfiguration(decoded: decoded)
                    fileOpenCoordinator.noteOpened(fileURL)
                    isLoadingWindog = false
                    DispatchQueue.main.async {
                        showsConfiguration = true
                    }
                }
            } catch {
                await MainActor.run {
                    parserError = error.localizedDescription
                    isLoadingWindog = false
                    pendingTextImportURL = nil
                }
            }
        }
    }

    private func loadWindog(_ fileURL: URL, preserveConfiguration: Bool = false) {
        isLoadingWindog = true
        parserError = nil
        loadedFileName = fileURL.lastPathComponent
        loadedFileURL = fileURL
        if !preserveConfiguration {
            dataSetConfiguration = .empty
        }

        Task.detached {
            do {
                let summary = try WindogParser.parse(fileURL: fileURL)
                let sections = summary.sections.map { section in
                    PropertySection(
                        title: section.title,
                        rows: section.rows.map { row in
                            PropertyRow(label: row.label, value: row.value)
                        }
                    )
                }
                await MainActor.run {
                    let parsedCharts = AppChartData(decoded: summary.charts)
                    sourcePropertySections = sections
                    sourceChartData = parsedCharts
                    propertySections = sections
                    chartData = parsedCharts
                    if preserveConfiguration {
                        applyConfiguration(dataSetConfiguration)
                    }
                    loadedFileName = summary.fileName
                    fileOpenCoordinator.noteOpened(fileURL)
                    hasLoadedFile = true
                    isLoadingWindog = false
                }
            } catch {
                await MainActor.run {
                    parserError = error.localizedDescription
                    isLoadingWindog = false
                }
            }
        }
    }

    private func openConfiguration() {
        guard let loadedFileURL else { return }
        if !dataSetConfiguration.columns.isEmpty {
            showsConfiguration = true
            return
        }
        guard !isLoadingConfiguration else { return }
        isLoadingConfiguration = true
        parserError = nil
        Task.detached {
            do {
                let decoded = try WindogParser.parseConfiguration(fileURL: loadedFileURL)
                await MainActor.run {
                    dataSetConfiguration = DataSetConfiguration(decoded: decoded)
                    isLoadingConfiguration = false
                    DispatchQueue.main.async {
                        showsConfiguration = true
                    }
                }
            } catch {
                await MainActor.run {
                    parserError = error.localizedDescription
                    isLoadingConfiguration = false
                }
            }
        }
    }

    private func applyConfiguration(_ updated: DataSetConfiguration) {
        dataSetConfiguration = updated
        let shear = ShearComputation(columns: updated.columns)
        chartData = sourceChartData.applying(configuration: updated, shear: shear)
        propertySections = sourcePropertySections.applying(dataSet: updated.dataSet, shear: shear)
    }

    private func saveWindog() {
        guard canSaveWindog, let loadedFileURL else {
            parserError = "Saving is only supported after opening a .windog file."
            return
        }
        saveWindog(to: loadedFileURL, reopenSavedFile: false)
    }

    private func saveWindogAs() {
        guard canSaveWindog, let loadedFileURL else {
            parserError = "Save As is only supported after opening a .windog file."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Windographer File As"
        panel.prompt = "Save"
        panel.nameFieldStringValue = loadedFileURL.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "windog")].compactMap { $0 }
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else {
                return
            }
            saveWindog(to: destinationURL, reopenSavedFile: true)
        }
    }

    private func saveWindog(to destinationURL: URL, reopenSavedFile: Bool) {
        guard let sourceURL = loadedFileURL else { return }
        isLoadingWindog = true
        parserError = nil
        let configuration = dataSetConfiguration

        Task.detached {
            do {
                try WindogParser.saveConfiguration(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    configuration: configuration
                )
                await MainActor.run {
                    fileOpenCoordinator.noteOpened(destinationURL)
                    isLoadingWindog = false
                    if reopenSavedFile {
                        loadWindog(destinationURL)
                    } else {
                        loadWindog(sourceURL, preserveConfiguration: true)
                    }
                }
            } catch {
                await MainActor.run {
                    parserError = error.localizedDescription
                    isLoadingWindog = false
                }
            }
        }
    }

    private var chartsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PlotPanel(title: "Vertical Wind Shear Profile") {
                    CartesianLineChart(
                        series: chartData.shear,
                        xRange: 0...max(10, chartRange(for: chartData.shear, axis: \.x, fallback: 0...10, lower: 0, padding: 0.6).upperBound),
                        yRange: chartRange(for: chartData.shear, axis: \.y, fallback: 0...150, lower: 0, padding: 10),
                        xTicks: [0, 2, 4, 6, 8, 10],
                        yTicks: yTicks(for: chartData.shear, fallback: [0, 50, 100, 150]),
                        xLabel: "Mean Wind Speed (m/s)",
                        yLabel: "Height Above Ground (m)",
                        markerSeriesName: "Measured data"
                    )
                }

                PlotPanel(title: "Wind Frequency Rose") {
                    WindRoseChart(series: chartData.rose)
                }
            }

            HStack(spacing: 8) {
                PlotPanel(title: "Monthly Mean Wind Speeds") {
                    CartesianLineChart(
                        series: chartData.monthly,
                        xRange: 0...11,
                        yRange: chartRange(for: chartData.monthly, axis: \.y, fallback: 0...16, lower: 0, padding: 1),
                        xTicks: Array(0...11).map(Double.init),
                        yTicks: compactTicks(for: chartData.monthly, fallback: [0, 4, 8, 12, 16]),
                        xLabels: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
                        xLabel: "",
                        yLabel: "Mean Wind Speed (m/s)",
                        markerSeriesName: nil,
                        markerMode: .all
                    )
                }

                PlotPanel(title: "Diurnal Wind Speed Profile") {
                    CartesianLineChart(
                        series: chartData.diurnal,
                        xRange: 0...24,
                        yRange: chartRange(for: chartData.diurnal, axis: \.y, fallback: 0...12, lower: 0, padding: 1),
                        xTicks: [0, 6, 12, 18, 24],
                        yTicks: compactTicks(for: chartData.diurnal, fallback: [0, 3, 6, 9, 12]),
                        xLabel: "Hour of Day",
                        yLabel: "Mean Wind Speed (m/s)",
                        markerSeriesName: nil
                    )
                }
            }
        }
        .padding(8)
        .background(Color(.windowBackgroundColor))
    }

    private var timeSeriesView: some View {
        TimeSeriesView(data: chartData.timeSeries, fileURL: loadedFileURL)
            .background(Color(.windowBackgroundColor))
    }

    private var windRoseView: some View {
        WindRoseView(series: chartData.rose, data: chartData.timeSeries, fileURL: loadedFileURL)
            .background(Color(.windowBackgroundColor))
    }

    private var histogramView: some View {
        HistogramView(data: chartData.timeSeries, fileURL: loadedFileURL)
            .background(Color(.windowBackgroundColor))
    }

    private func chartRange(
        for series: [NamedSeries],
        axis: KeyPath<SeriesPoint, Double>,
        fallback: ClosedRange<Double>,
        lower: Double? = nil,
        padding: Double
    ) -> ClosedRange<Double> {
        let values = series.flatMap(\.points).map { $0[keyPath: axis] }.filter(\.isFinite)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return fallback
        }
        let start = lower ?? minValue - padding
        let end = max(maxValue + padding, start + 1)
        return start...end
    }

    private func yTicks(for series: [NamedSeries], fallback: [Double]) -> [Double] {
        let maxValue = series.flatMap(\.points).map(\.y).max() ?? fallback.last ?? 150
        let step = maxValue > 160 ? 50.0 : 30.0
        let top = ceil(maxValue / step) * step
        return stride(from: 0.0, through: top, by: step).map { $0 }
    }

    private func compactTicks(for series: [NamedSeries], fallback: [Double]) -> [Double] {
        let maxValue = series.flatMap(\.points).map(\.y).max() ?? fallback.last ?? 12
        let top = max(ceil(maxValue / 2) * 2, 2)
        let step = max(top / 4, 1)
        return stride(from: 0.0, through: top, by: step).map { $0 }
    }
}

struct MenuText: View {
    let title: String
    var action: (() -> Void)?

    init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .underline()
        }
        .buttonStyle(.plain)
    }
}

extension AppChartData {
    init(decoded: DecodedCharts) {
        self.init(
            shear: decoded.shear.series.map(NamedSeries.init(decoded:)),
            rose: decoded.rose.series.map(NamedPolarSeries.init(decoded:)),
            monthly: decoded.monthly.series.map(NamedSeries.init(decoded:)),
            diurnal: decoded.diurnal.series.map(NamedSeries.init(decoded:)),
            timeSeries: TimeSeriesData(decoded: decoded.timeSeries)
        )
    }

    func applying(configuration: DataSetConfiguration, shear recalculatedShear: ShearComputation? = nil) -> AppChartData {
        let visibleColumns = configuration.columns.filter(\.visible)
        let visibleIDs = Set(visibleColumns.map(\.id))
        let columnByID = Dictionary(uniqueKeysWithValues: visibleColumns.map { ($0.id, $0) })

        func displayName(for id: String) -> String {
            columnByID[id]?.label ?? id
        }

        func filterSeries(_ series: [NamedSeries], rename: Bool) -> [NamedSeries] {
            series.compactMap { item in
                guard visibleIDs.contains(item.name) else { return nil }
                return NamedSeries(
                    name: rename ? displayName(for: item.name) : item.name,
                    colorName: columnByID[item.name]?.colorName ?? item.colorName,
                    points: item.points
                )
            }
        }

        return AppChartData(
            shear: recalculatedShear?.series ?? shear,
            rose: rose,
            monthly: filterSeries(monthly, rename: true),
            diurnal: filterSeries(diurnal, rename: true),
            timeSeries: timeSeries.applying(configuration: configuration)
        )
    }
}

extension TimeSeriesData {
    func applying(configuration: DataSetConfiguration) -> TimeSeriesData {
        let visibleColumns = configuration.columns.filter(\.visible)
        let columnByID = Dictionary(uniqueKeysWithValues: visibleColumns.map { ($0.id, $0) })
        let channels = channels.compactMap { channel -> TimeSeriesChannel? in
            guard let column = columnByID[channel.id] else { return nil }
            return TimeSeriesChannel(
                id: channel.id,
                name: column.label,
                colorName: column.colorName,
                defaultVisible: channel.defaultVisible,
                unit: column.unit,
                kind: channel.kind
            )
        }
        return TimeSeriesData(
            series: series.filter { columnByID[$0.name] != nil },
            channels: channels,
            monthLabels: monthLabels,
            startDate: startDate,
            endDate: endDate,
            years: years
        )
    }
}

extension Array where Element == PropertySection {
    func applying(dataSet: DataSetInformation, shear: ShearComputation? = nil) -> [PropertySection] {
        map { section in
            if section.title == "Wind shear coefficients", let shear {
                return PropertySection(
                    title: section.title,
                    rows: [
                        PropertyRow(label: "Power law exponent:", value: formatOptionalNumber(shear.powerLawExponent, digits: 3)),
                        PropertyRow(label: "Surface roughness:", value: "\(formatRoughness(shear.roughnessLength)) m"),
                        PropertyRow(label: "Roughness class:", value: formatOptionalNumber(shear.roughnessClass, digits: 2))
                    ]
                )
            }
            guard section.title == "Data set properties" else { return section }
            return PropertySection(
                title: section.title,
                rows: section.rows.map { row in
                    switch row.label {
                    case "Latitude:":
                        return PropertyRow(label: row.label, value: String(format: "N %.6f", dataSet.latitude))
                    case "Longitude:":
                        return PropertyRow(label: row.label, value: String(format: "E %.6f", dataSet.longitude))
                    case "Elevation:":
                        return PropertyRow(label: row.label, value: "\(formatDataSetNumber(dataSet.elevation, digits: 0)) m")
                    case "Calm threshold:":
                        return PropertyRow(label: row.label, value: "\(formatDataSetNumber(dataSet.calmThreshold, digits: 0)) m/s")
                    default:
                        return row
                    }
                }
            )
        }
    }
}

struct ShearComputation {
    let series: [NamedSeries]
    let powerLawExponent: Double?
    let roughnessLength: Double?
    let roughnessClass: Double?

    init(columns: [DataColumnConfiguration]) {
        let measured = columns
            .filter { $0.visible && $0.type == "Wind Speed" && $0.subtype == "Mean" }
            .compactMap { column -> (height: Double, speed: Double)? in
                guard let height = column.height, height > 0, let speed = parseStatNumber(column.mean), speed > 0 else {
                    return nil
                }
                return (height, speed)
            }
            .sorted { $0.height < $1.height }

        guard measured.count >= 2, let maxHeight = measured.map(\.height).max() else {
            series = []
            powerLawExponent = nil
            roughnessLength = nil
            roughnessClass = nil
            return
        }

        let samples = (0...80).map { 1.0 + (maxHeight - 1.0) * Double($0) / 80.0 }
        let powerFit = linearFit(measured.map { (log($0.height), log($0.speed)) })
        let alpha = powerFit?.slope
        let powerPoints = powerFit.map { fit in
            samples.map { height in
                SeriesPoint(x: exp(fit.intercept) * pow(height, fit.slope), y: height)
            }
        } ?? []

        let logFit = linearFit(measured.map { (log($0.height), $0.speed) })
        let roughness = logFit.flatMap { fit -> Double? in
            guard fit.slope > 0 else { return nil }
            return exp(-fit.intercept / fit.slope)
        }
        let logPoints = logFit.map { fit in
            samples.map { height in
                SeriesPoint(x: max(0, fit.intercept + fit.slope * log(height)), y: height)
            }
        } ?? []

        series = [
            NamedSeries(
                name: "Measured data",
                colorName: "measured",
                points: measured.map { SeriesPoint(x: $0.speed, y: $0.height) }
            ),
            NamedSeries(name: "Power law fit", colorName: "power", points: powerPoints),
            NamedSeries(name: "Log law fit", colorName: "log", points: logPoints)
        ]
        powerLawExponent = alpha
        roughnessLength = roughness
        if let roughness {
            roughnessClass = roughnessClassValue(roughness)
        } else {
            roughnessClass = nil
        }
    }
}

private func parseStatNumber(_ value: String) -> Double? {
    Double(value.replacingOccurrences(of: ",", with: ""))
}

private func linearFit(_ points: [(x: Double, y: Double)]) -> (intercept: Double, slope: Double)? {
    let pairs = points.filter { $0.x.isFinite && $0.y.isFinite && $0.x > 0 && $0.y > 0 }
    guard pairs.count >= 2 else { return nil }
    let n = Double(pairs.count)
    let sx = pairs.reduce(0) { $0 + $1.x }
    let sy = pairs.reduce(0) { $0 + $1.y }
    let sxx = pairs.reduce(0) { $0 + $1.x * $1.x }
    let sxy = pairs.reduce(0) { $0 + $1.x * $1.y }
    let denominator = n * sxx - sx * sx
    guard abs(denominator) > 1e-12 else { return nil }
    let slope = (n * sxy - sx * sy) / denominator
    let intercept = (sy - slope * sx) / n
    return (intercept, slope)
}

private func roughnessClassValue(_ roughnessLength: Double) -> Double? {
    guard roughnessLength > 0, roughnessLength.isFinite else { return nil }
    let table: [(Double, Double)] = [
        (0.0, 0.0002), (0.5, 0.0024), (1.0, 0.03), (1.5, 0.055),
        (2.0, 0.1), (2.5, 0.2), (3.0, 0.4), (3.5, 0.8), (4.0, 1.6)
    ]
    if roughnessLength <= table[0].1 { return table[0].0 }
    if roughnessLength >= table[table.count - 1].1 { return table[table.count - 1].0 }
    let logZ = log(roughnessLength)
    for index in 0..<(table.count - 1) {
        let a = table[index]
        let b = table[index + 1]
        if a.1 <= roughnessLength && roughnessLength <= b.1 {
            let fraction = (logZ - log(a.1)) / (log(b.1) - log(a.1))
            return a.0 + (b.0 - a.0) * fraction
        }
    }
    return nil
}

private func formatOptionalNumber(_ value: Double?, digits: Int) -> String {
    guard let value, value.isFinite else { return "-" }
    return String(format: "%.\(digits)f", value)
}

private func formatRoughness(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }
    if value < 0.0001 {
        return String(format: "%.6f", value)
    }
    if value < 0.01 {
        return String(format: "%.5f", value)
    }
    return String(format: "%.4f", value)
}

private func formatDataSetNumber(_ value: Double, digits: Int) -> String {
    if abs(value.rounded() - value) < 0.001 {
        return String(Int(value.rounded()))
    }
    return String(format: "%.\(digits)f", value)
}

extension DataSetConfiguration {
    init(decoded: DecodedDataSetConfiguration?) {
        guard let decoded else {
            self = .empty
            return
        }
        columns = decoded.columns.map(DataColumnConfiguration.init(decoded:))
        dataSet = DataSetInformation(decoded: decoded.dataSet)
    }
}

extension DataColumnConfiguration {
    init(decoded: DecodedDataColumnConfiguration) {
        id = decoded.id
        label = decoded.label
        unit = decoded.unit
        type = decoded.type
        subtype = decoded.subtype
        colorName = decoded.colorName
        height = decoded.height
        visible = decoded.visible
        mean = decoded.mean
        min = decoded.min
        max = decoded.max
        associated = AssociatedColumns(decoded: decoded.associated)
        preview = ColumnPreview(decoded: decoded.preview)
    }
}

extension AssociatedColumns {
    init(decoded: DecodedAssociatedColumns) {
        stdDev = decoded.stdDev
        min = decoded.min
        max = decoded.max
        speed = decoded.speed
    }
}

extension ColumnPreview {
    init(decoded: DecodedColumnPreview) {
        pdf = decoded.pdf.map { HistogramBar(x: $0.x, y: $0.y, width: $0.width) }
        diurnal = decoded.diurnal.map { SeriesPoint(x: $0.x, y: $0.y) }
        monthly = decoded.monthly.map(MonthlyStatistic.init(decoded:))
    }
}

extension MonthlyStatistic {
    init(decoded: DecodedMonthlyStatistic) {
        x = decoded.x
        min = decoded.min
        q1 = decoded.q1
        mean = decoded.mean
        q3 = decoded.q3
        max = decoded.max
    }
}

extension DataSetInformation {
    init(decoded: DecodedDataSetInformation) {
        name = decoded.name
        description = decoded.description
        latitude = decoded.latitude
        longitude = decoded.longitude
        elevation = decoded.elevation
        start = decoded.start
        end = decoded.end
        duration = decoded.duration
        timeStep = decoded.timeStep
        calmThreshold = decoded.calmThreshold
        invalidValue = decoded.invalidValue
        timestampsIndicate = decoded.timestampsIndicate
        metadataSource = decoded.metadataSource
    }
}

extension TimeSeriesData {
    init(decoded: DecodedTimeSeries) {
        self.init(
            series: decoded.series.map(NamedSeries.init(decoded:)),
            channels: decoded.channels.map {
                TimeSeriesChannel(id: $0.id, name: $0.name, colorName: $0.colorName, defaultVisible: $0.defaultVisible, unit: $0.unit, kind: $0.kind)
            },
            monthLabels: decoded.monthLabels.map {
                TimeAxisLabel(x: $0.x, label: $0.label)
            },
            startDate: Self.parseDate(decoded.startDate),
            endDate: Self.parseDate(decoded.endDate),
            years: decoded.years ?? []
        )
    }

    private static func parseDate(_ value: String?) -> Date {
        guard let value else {
            return Date(timeIntervalSince1970: 0)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}

extension NamedSeries {
    init(decoded: DecodedSeries) {
        self.init(
            name: decoded.name,
            colorName: decoded.colorName,
            points: decoded.points.map { SeriesPoint(x: $0.x, y: $0.y) }
        )
    }
}

extension NamedPolarSeries {
    init(decoded: DecodedPolarSeries) {
        self.init(
            name: decoded.name,
            colorName: decoded.colorName,
            points: decoded.points.map { PolarPoint(degrees: $0.degrees, radius: $0.radius) }
        )
    }
}

struct ToolIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : Color.primary)
            .background(configuration.isPressed ? Color(.selectedControlColor) : Color(.controlBackgroundColor))
            .overlay {
                Rectangle()
                    .stroke(Color(.separatorColor), lineWidth: 1)
            }
    }
}

struct EmptyFileView: View {
    let parserError: String?
    let isLoading: Bool
    let openAction: () -> Void
    let openURLAction: (URL) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("Open a Windographer file")
                .font(.system(size: 20, weight: .semibold))

            Text("Choose a .windog, .txt, .csv, or .tsv file to load dataset properties and charts.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if isLoading {
                VStack(spacing: 6) {
                    ProgressView(value: 0.65)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                    Text("Loading and parsing wind data...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let parserError {
                Text(parserError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 520)
            }

            Button {
                openAction()
            } label: {
                Label("Open File", systemImage: "folder")
            }
            .controlSize(.large)
            .padding(.top, 4)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(24)
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard !isLoading else { return false }
            return openDroppedFile(from: providers)
        }
    }

    private func openDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let droppedURL = item as? URL {
                url = droppedURL
            } else if let path = item as? String {
                url = URL(string: path)?.isFileURL == true ? URL(string: path) : URL(fileURLWithPath: path)
            } else {
                url = nil
            }

            guard let url else { return }
            DispatchQueue.main.async {
                openURLAction(url)
            }
        }

        return true
    }
}

struct SummarySidebar: View {
    let sections: [PropertySection]
    let fileName: String
    let parserError: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(fileName)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                if let parserError {
                    Text(parserError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(4)
                }
            }
            .padding(.bottom, 12)

            ForEach(sections) { section in
                PropertyGroup(section: section)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .background(Color(.windowBackgroundColor))
    }
}

struct PropertyGroup: View {
    let section: PropertySection

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 1)
            }

            ForEach(section.rows) { row in
                HStack {
                    Text(row.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 13, design: .monospaced))
            }
        }
        .padding(.bottom, 18)
    }
}

struct PlotPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
            content
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct BlankTabView: View {
    let title: String

    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}
