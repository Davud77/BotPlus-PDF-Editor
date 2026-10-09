import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class MeasurementController: ObservableObject {
    @Published var activeTool: EditorTool = .hand
    @Published var calibration: ScaleCalibration?
    @Published var records: [MeasurementRecord] = []
    @Published var draftPoints: [CGPoint] = []
    @Published var cursorPDFPoint: CGPoint?
    @Published var calibrationDrawingLength = "10"
    @Published var calibrationRealLength = "1000"
    @Published var calibrationLabel = "10 mm = 1 m"
    @Published var statusMessage: String?

    var onChange: (() -> Void)?

    func setTool(_ tool: EditorTool) {
        activeTool = tool
        draftPoints = []
    }

    func configureCalibration() {
        guard let drawing = Double(calibrationDrawingLength), let real = Double(calibrationRealLength) else {
            statusMessage = "Enter numeric calibration lengths."; return
        }
        do {
            calibration = try ScaleCalibration(drawingLengthMillimeters: drawing, realLengthMillimeters: real, label: calibrationLabel)
            statusMessage = "Scale set: \(calibrationLabel)"
            onChange?()
        } catch { statusMessage = error.localizedDescription }
    }

    func accept(point: CGPoint, pageIndex: Int, finishes: Bool) {
        switch activeTool {
        case .distance:
            if draftPoints.isEmpty { draftPoints = [point] }
            else {
                appendDistinct(point)
                if finishes && draftPoints.count >= 2 { commit(kind: .distance, pageIndex: pageIndex) }
            }
        case .perimeter, .area:
            if draftPoints.isEmpty { draftPoints = [point] }
            else {
                appendDistinct(point)
                if finishes && draftPoints.count >= 3 { commit(kind: activeTool == .area ? .area : .perimeter, pageIndex: pageIndex) }
            }
        case .freehand, .highlight, .underline:
            draftPoints.append(point)
            if finishes { commitInk(pageIndex: pageIndex) }
        default: break
        }
    }

    func appendDragPoint(_ point: CGPoint, pageIndex: Int) {
        guard activeTool == .freehand || activeTool == .highlight || activeTool == .underline else { return }
        if draftPoints.isEmpty { draftPoints = [point] }
        else if hypot(draftPoints.last!.x - point.x, draftPoints.last!.y - point.y) > 1.5 { draftPoints.append(point) }
    }

    func undo() { if !records.isEmpty { records.removeLast(); onChange?() } }
    func clearDraft() { draftPoints = [] }

    private func commit(kind: MeasurementKind, pageIndex: Int) {
        guard let calibration, draftPoints.count >= 2 else { statusMessage = "Set a scale and add points first."; return }
        let raw: Double
        let unit: String
        switch kind {
        case .distance:
            raw = polylineLength(draftPoints) * calibration.millimetersPerPDFPoint
            unit = raw >= 1000 ? "m" : "mm"
        case .perimeter:
            raw = (polylineLength(draftPoints) + distance(draftPoints.last!, draftPoints[0])) * calibration.millimetersPerPDFPoint
            unit = raw >= 1000 ? "m" : "mm"
        case .area:
            raw = polygonArea(draftPoints) * pow(calibration.millimetersPerPDFPoint, 2)
            unit = "m²"
        }
        let value = unit == "m" ? raw / 1000 : (unit == "m²" ? raw / 1_000_000 : raw)
        records.append(MeasurementRecord(kind: kind, pageIndex: pageIndex, points: draftPoints, value: value, unit: unit))
        draftPoints = []
        statusMessage = String(format: "%@ saved: %.3f %@", kind.rawValue.capitalized, value, unit)
        onChange?()
    }

    private func commitInk(pageIndex: Int) {
        guard draftPoints.count > 1 else { draftPoints = []; return }
        records.append(MeasurementRecord(kind: .distance, pageIndex: pageIndex, points: draftPoints, value: 0, unit: "ink", markStyle: activeTool.rawValue))
        draftPoints = []
        onChange?()
    }

    private func appendDistinct(_ point: CGPoint) {
        guard let last = draftPoints.last,
              hypot(last.x - point.x, last.y - point.y) < 0.5 else {
            draftPoints.append(point)
            return
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private func polylineLength(_ points: [CGPoint]) -> Double { zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) } }
    private func polygonArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        return abs(zip(points, points.dropFirst() + [points[0]]).reduce(0.0) { $0 + Double($1.0.x * $1.1.y - $1.1.x * $1.0.y) }) / 2
    }
}
