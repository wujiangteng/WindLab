import Foundation

struct PropertySection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [PropertyRow]
}

struct PropertyRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct SeriesPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

struct NamedSeries: Identifiable {
    let id = UUID()
    let name: String
    let colorName: String
    let points: [SeriesPoint]
}

struct PolarPoint: Identifiable {
    let id = UUID()
    let degrees: Double
    let radius: Double
}

struct NamedPolarSeries: Identifiable {
    let id = UUID()
    let name: String
    let colorName: String
    let points: [PolarPoint]
}

struct AppChartData {
    let shear: [NamedSeries]
    let rose: [NamedPolarSeries]
    let monthly: [NamedSeries]
    let diurnal: [NamedSeries]
    let timeSeries: TimeSeriesData

    static let sample = AppChartData(
        shear: [SampleData.shearMeasured, SampleData.shearPower, SampleData.shearLog],
        rose: [
            NamedPolarSeries(name: "150m", colorName: "measured", points: SampleData.rosePoints)
        ],
        monthly: [SampleData.monthly150, SampleData.monthly100],
        diurnal: [SampleData.diurnal150, SampleData.diurnal100],
        timeSeries: TimeSeriesData(series: [], channels: [], monthLabels: [], startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 0), years: [])
    )
}

struct TimeSeriesData {
    let series: [NamedSeries]
    let channels: [TimeSeriesChannel]
    let monthLabels: [TimeAxisLabel]
    let startDate: Date
    let endDate: Date
    let years: [Int]
}

struct TimeSeriesChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let colorName: String
    let defaultVisible: Bool
    let unit: String
    let kind: String
}

struct TimeAxisLabel: Identifiable {
    let id = UUID()
    let x: Double
    let label: String
}

struct DataSetConfiguration {
    var columns: [DataColumnConfiguration]
    var dataSet: DataSetInformation

    static let empty = DataSetConfiguration(columns: [], dataSet: .empty)
}

struct DataColumnConfiguration: Identifiable {
    var id: String
    var label: String
    var unit: String
    var type: String
    var subtype: String
    var colorName: String
    var height: Double?
    var visible: Bool
    var mean: String
    var min: String
    var max: String
    var associated: AssociatedColumns
    var preview: ColumnPreview
}

struct AssociatedColumns: Hashable {
    var stdDev: String
    var min: String
    var max: String
    var speed: String
}

struct ColumnPreview {
    var pdf: [HistogramBar]
    var diurnal: [SeriesPoint]
    var monthly: [MonthlyStatistic]

    static let empty = ColumnPreview(pdf: [], diurnal: [], monthly: [])
}

struct MonthlyStatistic: Identifiable {
    let id = UUID()
    var x: Double
    var min: Double
    var q1: Double
    var mean: Double
    var q3: Double
    var max: Double
}

struct DataSetInformation: Hashable {
    var name: String
    var description: String
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var start: String
    var end: String
    var duration: String
    var timeStep: String
    var calmThreshold: Double
    var invalidValue: Double
    var timestampsIndicate: String
    var metadataSource: String

    static let empty = DataSetInformation(
        name: "",
        description: "",
        latitude: 0,
        longitude: 0,
        elevation: 0,
        start: "-",
        end: "-",
        duration: "-",
        timeStep: "-",
        calmThreshold: 0,
        invalidValue: 9999,
        timestampsIndicate: "Start",
        metadataSource: ""
    )
}

enum SampleData {
    static let propertySections = [
        PropertySection(
            title: "Data set properties",
            rows: [
                .init(label: "Latitude:", value: "N 0.000000"),
                .init(label: "Longitude:", value: "E 0.000000"),
                .init(label: "Elevation:", value: "0 m"),
                .init(label: "Start date:", value: "2022/7/1 00:00"),
                .init(label: "End date:", value: "2023/7/1 00:00"),
                .init(label: "Duration:", value: "12 months"),
                .init(label: "Time step:", value: "60 minutes"),
                .init(label: "Data points:", value: "35,040"),
                .init(label: "Calm threshold:", value: "0 m/s")
            ]
        ),
        PropertySection(
            title: "Environmental conditions",
            rows: [
                .init(label: "Mean temperature:", value: "15.0 C"),
                .init(label: "Mean pressure:", value: "101.3 kPa"),
                .init(label: "Mean air density:", value: "1.221 kg/m3"),
                .init(label: "Air density ratio:", value: "0.997")
            ]
        ),
        PropertySection(
            title: "Wind speed and power",
            rows: [
                .init(label: "Mean at 150 m:", value: "9.76 m/s"),
                .init(label: "Power density at 50m:", value: "689 W/m2"),
                .init(label: "Wind power class:", value: "6 (Outstanding)")
            ]
        ),
        PropertySection(
            title: "Wind shear coefficients",
            rows: [
                .init(label: "Power law exponent:", value: "0.108"),
                .init(label: "Surface roughness:", value: "0.0116 m"),
                .init(label: "Roughness class:", value: "0.81")
            ]
        )
    ]

    static let shearMeasured = NamedSeries(
        name: "Measured data",
        colorName: "measured",
        points: [
            .init(x: 5.2, y: 1), .init(x: 6.0, y: 3), .init(x: 6.8, y: 7),
            .init(x: 7.3, y: 15), .init(x: 7.8, y: 28), .init(x: 8.25, y: 48),
            .init(x: 8.65, y: 75), .init(x: 9.0, y: 100), .init(x: 9.42, y: 150)
        ]
    )

    static let shearPower = NamedSeries(
        name: "Power law fit",
        colorName: "power",
        points: stride(from: 5.1, through: 9.45, by: 0.12).map { x in
            SeriesPoint(x: x, y: pow(max(x - 5.0, 0.05), 2.55) * 7.5)
        }
    )

    static let shearLog = NamedSeries(
        name: "Log law fit",
        colorName: "log",
        points: stride(from: 5.0, through: 9.45, by: 0.12).map { x in
            SeriesPoint(x: x, y: pow(max(x - 4.9, 0.05), 2.42) * 8.0)
        }
    )

    static let monthly150 = NamedSeries(
        name: "150m",
        colorName: "primary",
        points: [11.4, 11.2, 8.8, 7.4, 8.0, 6.1, 8.9, 5.4, 8.6, 15.2, 10.7, 13.4].enumerated().map {
            SeriesPoint(x: Double($0.offset), y: $0.element)
        }
    )

    static let monthly100 = NamedSeries(
        name: "Speed 100 m Synthesized",
        colorName: "secondary",
        points: [10.9, 10.8, 8.5, 7.1, 7.7, 5.9, 8.6, 5.2, 8.4, 14.6, 10.5, 12.8].enumerated().map {
            SeriesPoint(x: Double($0.offset), y: $0.element)
        }
    )

    static let diurnal150 = NamedSeries(
        name: "150m",
        colorName: "primary",
        points: (0...24).map { hour in
            SeriesPoint(x: Double(hour), y: 9.72 + sin(Double(hour) / 2.2) * 0.10 + (hour > 15 && hour < 19 ? 0.22 : 0))
        }
    )

    static let diurnal100 = NamedSeries(
        name: "Speed 100 m Synthesized",
        colorName: "secondary",
        points: (0...24).map { hour in
            SeriesPoint(x: Double(hour), y: 9.32 + sin(Double(hour) / 2.2) * 0.09 + (hour > 15 && hour < 19 ? 0.18 : 0))
        }
    )

    static let rosePoints = [
        PolarPoint(degrees: 0, radius: 0.17),
        PolarPoint(degrees: 22.5, radius: 0.86),
        PolarPoint(degrees: 45, radius: 0.46),
        PolarPoint(degrees: 67.5, radius: 0.28),
        PolarPoint(degrees: 90, radius: 0.18),
        PolarPoint(degrees: 112.5, radius: 0.13),
        PolarPoint(degrees: 135, radius: 0.09),
        PolarPoint(degrees: 157.5, radius: 0.12),
        PolarPoint(degrees: 180, radius: 0.16),
        PolarPoint(degrees: 202.5, radius: 0.35),
        PolarPoint(degrees: 225, radius: 0.29),
        PolarPoint(degrees: 247.5, radius: 0.19),
        PolarPoint(degrees: 270, radius: 0.16),
        PolarPoint(degrees: 292.5, radius: 0.18),
        PolarPoint(degrees: 315, radius: 0.22),
        PolarPoint(degrees: 337.5, radius: 0.30)
    ]
}
