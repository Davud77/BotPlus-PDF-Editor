import AppKit
import PDFKit
import SwiftUI

struct PDFCanvas: NSViewRepresentable {
    @ObservedObject var model: PDFWorkspaceModel

    func makeNSView(context: Context) -> PDFCanvasHostView {
        let host = PDFCanvasHostView()
        host.pdfView.document = model.selectedDocument?.pdfDocument
        host.pdfView.displayMode = model.twoPageSpread ? .twoUp : .singlePageContinuous
        host.pdfView.displayDirection = .vertical
        host.pdfView.autoScales = true
        host.overlay.onPoint = { [weak model] point, pageIndex, finished in
            model?.measurement.accept(point: point, pageIndex: pageIndex, finishes: finished)
        }
        host.overlay.onDragPoint = { [weak model] point, pageIndex in model?.measurement.appendDragPoint(point, pageIndex: pageIndex) }
        host.overlay.onCursor = { [weak model] point in model?.measurement.cursorPDFPoint = point }
        host.overlay.measurement = model.measurement
        host.syncOverlay()
        return host
    }

    func updateNSView(_ host: PDFCanvasHostView, context: Context) {
        host.pdfView.document = model.selectedDocument?.pdfDocument
        host.pdfView.displayMode = model.twoPageSpread ? .twoUp : .singlePageContinuous
        host.pdfView.displayDirection = .vertical
        host.overlay.measurement = model.measurement
        host.overlay.needsDisplay = true
        if model.pendingPageChange != nil { host.goToPage(model.pendingPageChange!) ; DispatchQueue.main.async { model.pendingPageChange = nil } }
        if model.pendingZoom != nil { host.pdfView.scaleFactor = model.pendingZoom!; DispatchQueue.main.async { model.pendingZoom = nil } }
    }
}

final class PDFCanvasHostView: NSView {
    let pdfView = PDFView()
    let overlay = AnnotationOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        addSubview(overlay)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor), pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor), pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor), overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor), overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        pdfView.backgroundColor = NSColor(calibratedWhite: 0.23, alpha: 1)
        pdfView.displaysPageBreaks = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func syncOverlay() { overlay.pdfView = pdfView }
    func goToPage(_ index: Int) {
        guard let doc = pdfView.document, index >= 0, index < doc.pageCount, let page = doc.page(at: index) else { return }
        pdfView.go(to: page)
    }
}

final class AnnotationOverlayView: NSView {
    weak var pdfView: PDFView?
    weak var measurement: MeasurementController? { didSet { needsDisplay = true } }
    var onPoint: ((CGPoint, Int, Bool) -> Void)?
    var onDragPoint: ((CGPoint, Int) -> Void)?
    var onCursor: ((CGPoint?) -> Void)?
    private var dragPageIndex = 0
    private var isDrawing = false

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let tool = measurement?.activeTool, tool != .hand, tool != .textSelection, tool != .snapshot else { return nil }
        return super.hitTest(point)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let location = pdfLocation(event) else { onCursor?(nil); return }
        onCursor?(location.point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let hit = hit(event) else { return }
        window?.makeFirstResponder(self)
        dragPageIndex = hit.pageIndex
        isDrawing = measurement?.activeTool == .freehand || measurement?.activeTool == .highlight || measurement?.activeTool == .underline
        onPoint?(hit.point, hit.pageIndex, false)
        if isDrawing { onDragPoint?(hit.point, hit.pageIndex) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let hit = hit(event), hit.pageIndex == dragPageIndex else { return }
        if isDrawing { onDragPoint?(hit.point, hit.pageIndex); needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        guard let hit = hit(event) else { return }
        let isDistance = measurement?.activeTool == .distance
        onPoint?(hit.point, hit.pageIndex, isDistance || event.clickCount > 1)
        isDrawing = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let pdfView, let document = pdfView.document else { return }
        for record in measurement?.records ?? [] {
            guard let page = document.page(at: record.pageIndex) else { continue }
            drawRecord(record.points.map(\.cgPoint), value: record.value, unit: record.unit, page: page, isDraft: false, kind: record.kind, markStyle: record.markStyle)
        }
        if let selected = pdfView.currentPage {
            let draft = measurement?.draftPoints ?? []
            if !draft.isEmpty { drawRecord(draft, value: 0, unit: "", page: selected, isDraft: true, kind: measurement?.activeTool == .area ? .area : .distance, markStyle: measurement?.activeTool.rawValue) }
        }
    }

    private func drawRecord(_ points: [CGPoint], value: Double, unit: String, page: PDFPage, isDraft: Bool, kind: MeasurementKind, markStyle: String?) {
        guard let pdfView, points.count > 0 else { return }
        let converted = points.map { pdfView.convert($0, from: page) }
        let path = NSBezierPath()
        path.move(to: converted[0])
        for point in converted.dropFirst() { path.line(to: point) }
        if kind == .area && converted.count >= 3 { path.close() }
        let color: NSColor
        let width: CGFloat
        switch markStyle {
        case EditorTool.highlight.rawValue: color = NSColor.systemYellow; width = 12
        case EditorTool.underline.rawValue: color = NSColor.systemBlue; width = 2
        default: color = kind == .area ? NSColor.systemBlue : NSColor.systemOrange; width = 2
        }
        color.withAlphaComponent(markStyle == EditorTool.highlight.rawValue ? 0.42 : (isDraft ? 0.85 : 0.95)).setStroke()
        path.lineWidth = width
        path.setLineDash(isDraft ? [6, 4] : [], count: isDraft ? 2 : 0, phase: 0)
        path.stroke()
        if kind == .area && converted.count >= 3 { color.withAlphaComponent(0.10).setFill(); path.fill() }
        if !isDraft, let last = converted.last, unit != "ink" {
            let text = String(format: "%.3f %@", value, unit) as NSString
            text.draw(at: NSPoint(x: last.x + 8, y: last.y + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.windowBackgroundColor])
        }
    }

    private func pdfLocation(_ event: NSEvent) -> (point: CGPoint, pageIndex: Int)? {
        guard let pdfView, let page = pdfView.page(for: convert(event.locationInWindow, from: nil), nearest: true),
              let index = pdfView.document?.index(for: page), page.bounds(for: .cropBox).contains(pdfView.convert(convert(event.locationInWindow, from: nil), to: page)) else { return nil }
        return (pdfView.convert(convert(event.locationInWindow, from: nil), to: page), index)
    }

    private func hit(_ event: NSEvent) -> (point: CGPoint, pageIndex: Int)? { pdfLocation(event) }
}
