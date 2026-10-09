import PDFKit
import SwiftUI

struct LeftSidebarView: View {
    @ObservedObject var model: PDFWorkspaceModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(SidebarSection.allCases) { section in
                    Button { model.selectedSidebar = section } label: {
                        Image(systemName: section.symbol).frame(width: 34, height: 32)
                            .background(model.selectedSidebar == section ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help(section.rawValue)
                }
                Spacer()
            }.padding(.vertical, 9).frame(width: 45)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(model.selectedSidebar.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary).padding(12)
                Divider()
                ScrollView {
                    switch model.selectedSidebar {
                    case .thumbnails: thumbnails
                    case .bookmarks: bookmarks
                    case .annotations: annotations
                    case .attachments: emptyMessage("No attachments in this PDF", symbol: "paperclip")
                    case .layers: emptyMessage("This PDF has no optional content groups", symbol: "square.3.layers.3d")
                    }
                }
            }.frame(minWidth: 176, idealWidth: 205, maxWidth: 240)
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private var thumbnails: some View {
        if let document = model.selectedDocument?.pdfDocument {
            LazyVStack(spacing: 12) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    if let page = document.page(at: index) {
                        Button { model.pageNumberInput = String(index + 1); model.pendingPageChange = index } label: {
                            VStack(spacing: 4) {
                                PDFPageThumbnail(page: page).frame(width: 124, height: 160).background(.white).shadow(radius: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke((Int(model.pageNumberInput) ?? 1) == index + 1 ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2))
                                Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxWidth: .infinity).padding(10)
        } else { emptyMessage("Open a PDF to see page thumbnails", symbol: "doc.text") }
    }

    @ViewBuilder private var bookmarks: some View {
        if let document = model.selectedDocument?.pdfDocument, document.outlineRoot != nil {
            OutlineList(outline: document.outlineRoot!, level: 0) { pageIndex in model.pendingPageChange = pageIndex }
        } else { emptyMessage("No bookmarks in this PDF", symbol: "bookmark") }
    }

    private var annotations: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.measurement.records) { item in
                Button { model.pendingPageChange = item.pageIndex } label: {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.kind == .area ? "square.dashed" : "ruler").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.unit == "ink" ? "Freehand mark" : "\(item.kind.rawValue.capitalized): \(item.value, specifier: "%.3f") \(item.unit)").font(.system(size: 11, weight: .medium))
                            Text("Page \(item.pageIndex + 1)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(7).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if model.measurement.records.isEmpty { emptyMessage("No annotations yet", symbol: "text.bubble") }
        }.padding(6)
    }

    private func emptyMessage(_ message: String, symbol: String) -> some View {
        VStack(spacing: 8) { Image(systemName: symbol).font(.title3).foregroundStyle(.tertiary); Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity).padding(18)
    }
}

struct PDFPageThumbnail: NSViewRepresentable {
    let page: PDFPage
    func makeNSView(context: Context) -> PDFPageView { PDFPageView(page: page) }
    func updateNSView(_ nsView: PDFPageView, context: Context) { nsView.page = page }
}

final class PDFPageView: NSView {
    var page: PDFPage? { didSet { needsDisplay = true } }
    init(page: PDFPage) { self.page = page; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.white.cgColor); context.fill(bounds)
        let box = page.bounds(for: .cropBox)
        let scale = min(bounds.width / box.width, bounds.height / box.height)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let rect = CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.minY); context.scaleBy(x: scale, y: scale); page.draw(with: .cropBox, to: context); context.restoreGState()
    }
}

struct OutlineList: View {
    let outline: PDFOutline
    let level: Int
    let select: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if level > 0 || outline.label != nil {
                Button {
                    if let destination = outline.destination, let page = destination.page, let index = page.document?.index(for: page) { select(index) }
                } label: { Text(outline.label ?? "Bookmark").font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, CGFloat(level * 12)).padding(.vertical, 5) }.buttonStyle(.plain)
            }
            ForEach(0..<outline.numberOfChildren, id: \.self) { index in
                if let child = outline.child(at: index) { OutlineList(outline: child, level: level + 1, select: select) }
            }
        }.padding(.horizontal, 8)
    }
}

struct PropertiesInspector: View {
    @ObservedObject var model: PDFWorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROPERTIES").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary).padding(12)
            Divider()
            if let selected = model.selectedDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        property("File", selected.url.lastPathComponent)
                        property("Pages", "\(selected.pdfDocument.pageCount)")
                        property("Tool", model.measurement.activeTool.rawValue)
                        property("Scale", model.measurement.calibration?.label ?? "Not calibrated")
                        property("Measurements", "\(model.measurement.records.count)")
                        if let point = model.measurement.cursorPDFPoint {
                            Divider(); Text("CURSOR").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            property("X", String(format: "%.2f pt", point.x)); property("Y", String(format: "%.2f pt", point.y))
                        }
                        if let message = model.measurement.statusMessage { Divider(); Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }.padding(12)
                }
            } else { Text("Select a document or drawing tool to inspect its properties.").font(.caption).foregroundStyle(.secondary).padding(12) }
            Spacer(minLength: 0)
        }.frame(minWidth: 190, idealWidth: 225, maxWidth: 270).background(Color(nsColor: .controlBackgroundColor))
    }
    private func property(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 10)).foregroundStyle(.secondary); Text(value).font(.system(size: 12)).lineLimit(2).textSelection(.enabled) }
    }
}
