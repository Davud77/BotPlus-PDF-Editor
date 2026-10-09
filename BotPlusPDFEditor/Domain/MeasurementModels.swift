import CoreGraphics
import Foundation

enum MeasurementKind: String, Codable, CaseIterable {
    case distance, perimeter, area
}

struct ScaleCalibration: Codable, Equatable {
    /// Real-world millimeters represented by one PDF point.
    var millimetersPerPDFPoint: Double
    var label: String

    init(drawingLengthMillimeters: Double, realLengthMillimeters: Double, label: String = "Custom scale") throws {
        guard drawingLengthMillimeters.isFinite, realLengthMillimeters.isFinite,
              drawingLengthMillimeters > 0, realLengthMillimeters > 0 else { throw CalibrationError.invalidLength }
        millimetersPerPDFPoint = realLengthMillimeters / drawingLengthMillimeters * (25.4 / 72.0)
        self.label = label
    }

    func realMillimeters(forPDFPoints points: Double) -> Double { points * millimetersPerPDFPoint }
    func realMeters(forPDFPoints points: Double) -> Double { realMillimeters(forPDFPoints: points) / 1000 }
    func realSquareMeters(forPDFSquarePoints points: Double) -> Double { points * pow(millimetersPerPDFPoint, 2) / 1_000_000 }
}

enum CalibrationError: LocalizedError {
    case invalidLength
    var errorDescription: String? { "Drawing and real-world lengths must be positive finite numbers." }
}

struct MeasurementRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: MeasurementKind
    var pageIndex: Int
    var points: [CGPointCodable]
    var value: Double
    var unit: String
    var markStyle: String?
    var createdAt: Date

    init(id: UUID = UUID(), kind: MeasurementKind, pageIndex: Int, points: [CGPoint], value: Double, unit: String, markStyle: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.pageIndex = pageIndex
        self.points = points.map(CGPointCodable.init)
        self.value = value
        self.unit = unit
        self.markStyle = markStyle
        self.createdAt = createdAt
    }
}

struct CGPointCodable: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct MeasurementDocument: Codable {
    var version = 1
    var calibration: ScaleCalibration?
    var records: [MeasurementRecord] = []
}
