import Foundation

struct WindogSummary: Decodable {
    let fileName: String
    let sections: [DecodedPropertySection]
    let charts: DecodedCharts
    let configuration: DecodedDataSetConfiguration?
}

struct DecodedPropertySection: Decodable {
    let title: String
    let rows: [DecodedPropertyRow]
}

struct DecodedPropertyRow: Decodable {
    let label: String
    let value: String
}

struct DecodedCharts: Decodable {
    let shear: DecodedLineChart
    let rose: DecodedRoseChart
    let monthly: DecodedLineChart
    let diurnal: DecodedLineChart
    let timeSeries: DecodedTimeSeries
}

struct DecodedLineChart: Decodable {
    let series: [DecodedSeries]
}

struct DecodedRoseChart: Decodable {
    let series: [DecodedPolarSeries]
}

struct DecodedSeries: Decodable {
    let name: String
    let colorName: String
    let points: [DecodedPoint]
}

struct DecodedPolarSeries: Decodable {
    let name: String
    let colorName: String
    let points: [DecodedPolarPoint]
}

struct DecodedPoint: Decodable {
    let x: Double
    let y: Double
}

struct DecodedPolarPoint: Decodable {
    let degrees: Double
    let radius: Double
}

struct DecodedTimeSeries: Decodable {
    let series: [DecodedSeries]
    let channels: [DecodedTimeSeriesChannel]
    let monthLabels: [DecodedTimeAxisLabel]
    let startDate: String?
    let endDate: String?
    let years: [Int]?
}

struct DecodedTimeSeriesChannel: Decodable {
    let id: String
    let name: String
    let colorName: String
    let defaultVisible: Bool
    let unit: String
    let kind: String
}

struct DecodedDataSetConfiguration: Decodable {
    let columns: [DecodedDataColumnConfiguration]
    let dataSet: DecodedDataSetInformation
}

struct DecodedDataColumnConfiguration: Decodable {
    let id: String
    let label: String
    let unit: String
    let type: String
    let subtype: String
    let colorName: String
    let height: Double?
    let visible: Bool
    let mean: String
    let min: String
    let max: String
    let associated: DecodedAssociatedColumns
    let preview: DecodedColumnPreview
}

struct DecodedAssociatedColumns: Decodable {
    let stdDev: String
    let min: String
    let max: String
    let speed: String
}

struct DecodedColumnPreview: Decodable {
    let pdf: [DecodedHistogramBar]
    let diurnal: [DecodedPoint]
    let monthly: [DecodedMonthlyStatistic]
}

struct DecodedMonthlyStatistic: Decodable {
    let x: Double
    let min: Double
    let q1: Double
    let mean: Double
    let q3: Double
    let max: Double
}

struct DecodedDataSetInformation: Decodable {
    let name: String
    let description: String
    let latitude: Double
    let longitude: Double
    let elevation: Double
    let start: String
    let end: String
    let duration: String
    let timeStep: String
    let calmThreshold: Double
    let invalidValue: Double
    let timestampsIndicate: String
    let metadataSource: String
}

struct DecodedTimeAxisLabel: Decodable {
    let x: Double
    let label: String
}

struct DecodedHistogram: Decodable {
    let bars: [DecodedHistogramBar]
    let curve: [DecodedPoint]
    let xLabel: String
    let yLabel: String
    let weibull: String
}

struct DecodedHistogramBar: Decodable {
    let x: Double
    let y: Double
    let width: Double
}

struct DecodedDistributionAnalysis: Decodable {
    let bars: [DecodedHistogramBar]
    let curves: [DecodedSeries]
    let rows: [DecodedDistributionRow]
    let xLabel: String
    let yLabel: String
    let thresholdLabel: String
}

struct DecodedDistributionRow: Decodable {
    let algorithm: String
    let k: String
    let c: String
    let mean: String
    let proportionAbove: String
    let powerDensity: String
    let rSquared: String
}

enum WindogParser {
    static func parse(fileURL: URL) throws -> WindogSummary {
        try runParser(arguments: [fileURL.path], outputType: WindogSummary.self)
    }

    static func parseTimeSeries(fileURL: URL, channelID: String, mode: String) throws -> DecodedSeries {
        try runParser(arguments: ["--time-series", fileURL.path, mode, channelID], outputType: DecodedSeries.self)
    }

    static func parseConfigurationPreview(fileURL: URL, channelID: String) throws -> DecodedColumnPreview {
        try runParser(arguments: ["--config-preview", fileURL.path, channelID], outputType: DecodedColumnPreview.self)
    }

    static func parseConfiguration(fileURL: URL) throws -> DecodedDataSetConfiguration {
        try runParser(arguments: ["--configuration", fileURL.path], outputType: DecodedDataSetConfiguration.self)
    }

    static func saveConfiguration(sourceURL: URL, destinationURL: URL, configuration: DataSetConfiguration) throws {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(EncodableDataSetConfiguration(configuration))
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("windlab-save-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try payload.write(to: temporaryURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        _ = try runParser(
            arguments: ["--save-config", sourceURL.path, destinationURL.path, temporaryURL.path],
            outputType: SaveResult.self
        )
    }

    static func parseWindRose(
        fileURL: URL,
        display: String,
        versus: String,
        sectors: Int,
        directionID: String,
        dataIDs: [String],
        filterMode: String,
        year: String,
        month: String,
        rangeStart: String,
        rangeEnd: String,
        filterColumn: String = "-",
        filterMin: String = "-",
        filterMax: String = "-"
    ) throws -> DecodedRoseChart {
        try runParser(
            arguments: [
                "--wind-rose",
                fileURL.path,
                display,
                versus,
                String(sectors),
                directionID,
                dataIDs.isEmpty ? "-" : dataIDs.joined(separator: "\u{1f}"),
                filterMode,
                year,
                month,
                "\(rangeStart),\(rangeEnd)",
                filterColumn,
                filterMin,
                filterMax
            ],
            outputType: DecodedRoseChart.self
        )
    }

    static func parseHistogram(
        fileURL: URL,
        display: String,
        primaryID: String,
        width: String,
        start: String,
        filterMode: String,
        year: String,
        month: String,
        rangeStart: String,
        rangeEnd: String,
        filterColumn: String,
        filterMin: String,
        filterMax: String
    ) throws -> DecodedHistogram {
        try runParser(
            arguments: [
                "--histogram",
                fileURL.path,
                display,
                primaryID,
                width,
                start,
                filterMode,
                year,
                month,
                "\(rangeStart),\(rangeEnd)",
                filterColumn,
                filterMin,
                filterMax
            ],
            outputType: DecodedHistogram.self
        )
    }

    static func parseDistributionAnalysis(
        fileURL: URL,
        primaryID: String,
        width: String,
        start: String,
        filterMode: String,
        year: String,
        month: String,
        rangeStart: String,
        rangeEnd: String,
        filterColumn: String,
        filterMin: String,
        filterMax: String
    ) throws -> DecodedDistributionAnalysis {
        try runParser(
            arguments: [
                "--distribution-analysis",
                fileURL.path,
                primaryID,
                width,
                start,
                filterMode,
                year,
                month,
                "\(rangeStart),\(rangeEnd)",
                filterColumn,
                filterMin,
                filterMax
            ],
            outputType: DecodedDistributionAnalysis.self
        )
    }

    private static func runParser<T: Decodable>(arguments: [String], outputType: T.Type) throws -> T {
        let sourceParserURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Python")
            .appendingPathComponent("parse_windog.py")
        let packagedParserURL = Bundle.main.resourceURL?
            .appendingPathComponent("WindLabMac_WindLabMac.bundle")
            .appendingPathComponent("parse_windog.py")
        let parserURL: URL
        if FileManager.default.fileExists(atPath: sourceParserURL.path) {
            parserURL = sourceParserURL
        } else if let packagedParserURL, FileManager.default.fileExists(atPath: packagedParserURL.path) {
            parserURL = packagedParserURL
        } else {
            parserURL = Bundle.module.url(forResource: "parse_windog", withExtension: "py", subdirectory: "Python")!
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [parserURL.path] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let message = String(data: output + errorOutput, encoding: .utf8) ?? "Unknown parser error"
            throw ParserError.failed(message)
        }

        if let envelope = try? JSONDecoder().decode(ParserErrorEnvelope.self, from: output), let error = envelope.error {
            throw ParserError.failed(error)
        }

        return try JSONDecoder().decode(T.self, from: output)
    }

    enum ParserError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    private struct ParserErrorEnvelope: Decodable {
        let error: String?
    }

    private struct SaveResult: Decodable {
        let saved: Bool
    }
}

private struct EncodableDataSetConfiguration: Encodable {
    let columns: [EncodableDataColumnConfiguration]
    let dataSet: EncodableDataSetInformation

    init(_ configuration: DataSetConfiguration) {
        columns = configuration.columns.map(EncodableDataColumnConfiguration.init)
        dataSet = EncodableDataSetInformation(configuration.dataSet)
    }
}

private struct EncodableDataColumnConfiguration: Encodable {
    let id: String
    let label: String
    let unit: String
    let type: String
    let subtype: String
    let colorName: String
    let height: Double?
    let visible: Bool
    let associated: EncodableAssociatedColumns

    init(_ column: DataColumnConfiguration) {
        id = column.id
        label = column.label
        unit = column.unit
        type = column.type
        subtype = column.subtype
        colorName = column.colorName
        height = column.height
        visible = column.visible
        associated = EncodableAssociatedColumns(column.associated)
    }
}

private struct EncodableAssociatedColumns: Encodable {
    let stdDev: String
    let min: String
    let max: String
    let speed: String

    init(_ associated: AssociatedColumns) {
        stdDev = associated.stdDev
        min = associated.min
        max = associated.max
        speed = associated.speed
    }
}

private struct EncodableDataSetInformation: Encodable {
    let name: String
    let description: String
    let latitude: Double
    let longitude: Double
    let elevation: Double
    let calmThreshold: Double
    let invalidValue: Double
    let timestampsIndicate: String

    init(_ dataSet: DataSetInformation) {
        name = dataSet.name
        description = dataSet.description
        latitude = dataSet.latitude
        longitude = dataSet.longitude
        elevation = dataSet.elevation
        calmThreshold = dataSet.calmThreshold
        invalidValue = dataSet.invalidValue
        timestampsIndicate = dataSet.timestampsIndicate
    }
}
