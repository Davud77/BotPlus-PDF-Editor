import AppKit
import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenPDFDocument: Identifiable {
    let id = UUID()
    var url: URL
    var pdfDocument: PDFDocument
    var isDirty = false
    var title: String { url.lastPathComponent }
}

@MainActor
final class PDFWorkspaceModel: ObservableObject {
    @Published var documents: [OpenPDFDocument] = []
    @Published var selectedDocumentID: UUID?
    @Published var selectedTab: RibbonTab = .home
    @Published var selectedSidebar: SidebarSection = .thumbnails
    @Published var leftPanelVisible = true
    @Published var rightPanelVisible = true
    @Published var twoPageSpread = false
    @Published var zoomPercent = 100.0
    @Published var pageNumberInput = "1"
    @Published var pendingPageChange: Int?
    @Published var pendingZoom: CGFloat?
    @Published var alertMessage: String?
    let measurement = MeasurementController()
    private let repository = MeasurementRepository()

    init() { measurement.onChange = { [weak self] in self?.saveMeasurementSidecar() } }
    var selectedDocument: OpenPDFDocument? { documents.first { $0.id == selectedDocumentID } }
    var pageCount: Int { selectedDocument?.pdfDocument.pageCount ?? 0 }
    var currentPageNumber: Int {
        guard let page = selectedDocument?.pdfDocument.page(at: max(0, pendingPageChange ?? 0)) else { return 1 }
        return (selectedDocument?.pdfDocument.index(for: page) ?? 0) + 1
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { open(url) }
    }

    func open(_ url: URL) {
        guard let document = PDFDocument(url: url) else { alertMessage = "Could not open \(url.lastPathComponent)."; return }
        let opened = OpenPDFDocument(url: url, pdfDocument: document)
        documents.append(opened)
        selectedDocumentID = opened.id
        loadMeasurementSidecar(for: url)
        pageNumberInput = "1"
    }

    func selectDocument(_ id: UUID) {
        selectedDocumentID = id
        if let document = selectedDocument { loadMeasurementSidecar(for: document.url) }
    }

    func savePDF() {
        guard var doc = selectedDocument else { return }
        if doc.pdfDocument.write(to: doc.url) {
            doc.isDirty = false
            if let index = documents.firstIndex(where: { $0.id == doc.id }) { documents[index] = doc }
        } else { alertMessage = "Could not save the PDF." }
        saveMeasurementSidecar()
    }

    func savePDFAs() {
        guard let doc = selectedDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = doc.url.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard doc.pdfDocument.write(to: url) else { alertMessage = "Could not save the PDF."; return }
        if let index = documents.firstIndex(where: { $0.id == doc.id }) { documents[index].url = url }
        saveMeasurementSidecar()
    }

    func closeDocument(_ id: UUID) {
        documents.removeAll { $0.id == id }
        if selectedDocumentID == id { selectedDocumentID = documents.last?.id }
    }

    func navigatePage(_ offset: Int) {
        guard pageCount > 0 else { return }
        let proposed = max(0, min(pageCount - 1, (Int(pageNumberInput) ?? 1) - 1 + offset))
        pageNumberInput = String(proposed + 1)
        pendingPageChange = proposed
    }

    func goToEnteredPage() {
        guard pageCount > 0 else { return }
        let proposed = max(0, min(pageCount - 1, (Int(pageNumberInput) ?? 1) - 1))
        pageNumberInput = String(proposed + 1)
        pendingPageChange = proposed
    }

    func setZoom(_ percent: Double) {
        zoomPercent = max(25, min(400, percent))
        pendingZoom = CGFloat(zoomPercent / 100)
    }

    func printDocument() {
        guard let document = selectedDocument else { return }
        let printInfo = NSPrintInfo.shared
        let operation = document.pdfDocument.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true)
        operation?.run()
    }

    func loadMeasurementSidecar(for url: URL) {
        let data = repository.load(for: url)
        measurement.records = data.records
        measurement.calibration = data.calibration
        measurement.clearDraft()
        measurement.statusMessage = data.calibration?.label
    }

    private func saveMeasurementSidecar() {
        guard let document = selectedDocument else { return }
        do { try repository.save(MeasurementDocument(calibration: measurement.calibration, records: measurement.records), for: document.url) }
        catch { measurement.statusMessage = "Could not save measurements: \(error.localizedDescription)" }
    }
}
