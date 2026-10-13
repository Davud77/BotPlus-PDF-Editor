// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct PDFColorComponents: Sendable {
    var red: Double, green: Double, blue: Double, alpha: Double
    @MainActor init(_ color: Color, opacity: Double = 1) {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(value.redComponent); green = Double(value.greenComponent)
        blue = Double(value.blueComponent); alpha = opacity
    }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

enum PDFFormattingKind: String {
    case margins, header, watermark, bates, background, images
    func title(russian: Bool) -> String {
        switch self {
        case .margins: return russian ? "Поля страницы" : "Page margins"
        case .header: return russian ? "Колонтитулы" : "Header / Footer"
        case .watermark: return russian ? "Водяной знак" : "Watermark"
        case .bates: return russian ? "Нумерация Бейтса" : "Bates numbering"
        case .background: return russian ? "Фон страниц" : "Page background"
        case .images: return russian ? "Экспорт изображений" : "Export images"
        }
    }
}
enum PDFImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, tiff
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var bitmapType: NSBitmapImageRep.FileType { self == .png ? .png : (self == .jpeg ? .jpeg : .tiff) }
}
struct PDFFormattingOptions {
    var range = "all"
    var left: Double = 18, right: Double = 18, top: Double = 18, bottom: Double = 18
    var headerLeft = "", headerCenter = "{file}", headerRight = ""
    var footerLeft = "", footerCenter = "{page} / {pages}", footerRight = ""
    var text = "DRAFT"
    var fontName = "Helvetica"
    var fontSize: Double = 12
    var color: Color = .black
    var opacity: Double = 1
    var alignment = 1 // Left, center, right.
    var position = 1 // Top, center, bottom.
    var batesStart = 1
    var batesDigits = 6
    var image: CGImage?
    var imageName = ""
    var format: PDFImageFormat = .png
    var dpi = 150
    var transparent = false
    var jpegQuality = 0.9
}

@MainActor
struct PDFFormattingRequest: Identifiable {
    let id = UUID()
    let kind: PDFFormattingKind
    let document: PDFDocument
    let pageIndex: Int
    let filename: String
    let russian: Bool
    let isOwned: (PDFAnnotation) -> Bool
    let apply: (PDFFormattingOptions, Bool) -> String?
}

@MainActor
enum PDFDecorationEngine {
    static func expand(_ value: String, page: Int, count: Int, filename: String,
                       start: Int, digits: Int, sequence: Int, date: Date = Date(), russian: Bool) -> String {
        let total = start.addingReportingOverflow(sequence)
        guard !total.overflow, start >= 0, start <= 1_000_000_000, (1...12).contains(digits) else { return value }
        let number = String(total.partialValue)
        let bates = String(repeating: "0", count: max(0, digits - number.count)) + number
        let formattedDate = date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)
            .locale(Locale(identifier: russian ? "ru_RU" : "en_US")))
        return value.replacingOccurrences(of: "{page}", with: String(page + 1))
            .replacingOccurrences(of: "{pages}", with: String(count))
            .replacingOccurrences(of: "{file}", with: filename)
            .replacingOccurrences(of: "{date}", with: formattedDate)
            .replacingOccurrences(of: "{bates}", with: bates)
    }
    static func annotations(kind: PDFFormattingKind, options: PDFFormattingOptions, box: CGRect,
                            page: Int, count: Int, filename: String, sequence: Int, russian: Bool) -> [PDFAnnotation] {
        var result: [PDFAnnotation] = []
        guard options.fontSize.isFinite, (4...200).contains(options.fontSize), box.width > 0, box.height > 0 else { return result }
        let inset = min(18, box.width / 12)
        let font = NSFont(name: options.fontName, size: options.fontSize) ?? NSFont.systemFont(ofSize: options.fontSize)
        let color = PDFColorComponents(options.color, opacity: options.opacity).nsColor
        func add(_ template: String, rect: CGRect, alignment: NSTextAlignment) {
            guard !template.isEmpty, rect.width > 1, rect.height > 1 else { return }
            let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.contents = expand(template, page: page, count: count, filename: filename,
                start: options.batesStart, digits: options.batesDigits, sequence: sequence, russian: russian)
            annotation.font = font; annotation.fontColor = color; annotation.color = .clear
            annotation.alignment = alignment; annotation.userName = "BotPlus PDF Editor"
            annotation.shouldPrint = true
            let border = PDFBorder(); border.lineWidth = 0; annotation.border = border
            result.append(annotation)
        }
        let height = max(18, options.fontSize * 1.7)
        if kind == .header {
            let column = max(1, (box.width - inset * 2) / 3)
            let headers = [options.headerLeft, options.headerCenter, options.headerRight]
            let footers = [options.footerLeft, options.footerCenter, options.footerRight]
            let alignments: [NSTextAlignment] = [.left, .center, .right]
            for index in 0..<3 {
                let x = box.minX + inset + CGFloat(index) * column
                add(headers[index], rect: CGRect(x: x, y: box.maxY - inset - height, width: column, height: height), alignment: alignments[index])
                add(footers[index], rect: CGRect(x: x, y: box.minY + inset, width: column, height: height), alignment: alignments[index])
            }
        } else {
            let lines = max(1, options.text.components(separatedBy: "\n").count)
            let blockHeight = min(box.height - inset * 2, height * CGFloat(lines))
            let y = options.position == 0 ? box.maxY - inset - blockHeight : (options.position == 2 ? box.minY + inset : box.midY - blockHeight / 2)
            add(options.text, rect: CGRect(x: box.minX + inset, y: y, width: box.width - inset * 2, height: blockHeight),
                alignment: options.alignment == 0 ? .left : (options.alignment == 2 ? .right : .center))
        }
        return result
    }
}

@MainActor
private final class PDFFormattingEditorModel: ObservableObject {
    @Published var options: PDFFormattingOptions
    @Published var error: String?
    @Published var previewPage: Int
    let fontNames = NSFontManager.shared.availableFonts.sorted()
    init(options: PDFFormattingOptions, page: Int) { self.options = options; previewPage = page }
}

@MainActor
struct PDFFormattingEditor: View {
    let request: PDFFormattingRequest
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: PDFFormattingEditorModel
    init(request: PDFFormattingRequest) {
        self.request = request
        var initial = PDFFormattingOptions()
        if request.kind == .margins { initial.range = String(request.pageIndex + 1) }
        if request.kind == .watermark { initial.opacity = 0.2; initial.fontSize = 48; initial.color = .red }
        if request.kind == .bates { initial.text = "BP-{bates}"; initial.position = 2; initial.alignment = 2 }
        if request.kind == .background { initial.color = .white }
        _state = StateObject(wrappedValue: PDFFormattingEditorModel(options: initial, page: request.pageIndex))
    }
    private func text(_ en: String, _ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(request.kind.title(russian: request.russian)).font(.title2); Spacer() }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(text("Pages: all or 1-3,5", "Страницы: all или 1-3,5"), text: $state.options.range)
                        if request.kind == .margins { marginControls }
                        else if request.kind == .images { imageControls }
                        else if request.kind == .background { backgroundControls }
                        else { decorationControls }
                    }.padding(4)
                }.frame(width: 310)
                VStack {
                    PDFFormattingPreview(request: request, options: state.options, pageIndex: state.previewPage)
                        .frame(width: 400, height: 450)
                        .background(Color(nsColor: .windowBackgroundColor))
                    HStack {
                        Button { state.previewPage = max(0, state.previewPage - 1) } label: { Image(systemName: "chevron.left") }.disabled(state.previewPage == 0)
                        Text("\(state.previewPage + 1) / \(request.document.pageCount)")
                        Button { state.previewPage = min(request.document.pageCount - 1, state.previewPage + 1) } label: { Image(systemName: "chevron.right") }.disabled(state.previewPage + 1 >= request.document.pageCount)
                    }.font(.caption)
                    Text((PDFPageRange.parse(state.options.range, count: request.document.pageCount) ?? []).contains(state.previewPage)
                        ? text("Preview does not change the document.", "Предпросмотр не изменяет документ.")
                        : text("This page is outside the selected range.", "Эта страница вне выбранного диапазона."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = state.error { Text(error).foregroundStyle(.red).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                if [.header, .watermark, .bates, .background].contains(request.kind) {
                    Button(text("Remove from selected pages", "Удалить на выбранных страницах")) { submit(remove: true) }
                }
                Spacer()
                Button(text("Cancel", "Отмена")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(text(request.kind == .images ? "Export…" : "Apply", request.kind == .images ? "Экспортировать…" : "Применить")) { submit(remove: false) }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 770, height: 600)
    }
    private func submit(remove: Bool) {
        if let message = request.apply(state.options, remove) { state.error = message }
        else { dismiss() }
    }
    private var marginControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("CropBox inset from MediaBox (pt)", "Отступ CropBox от MediaBox (pt)")).font(.caption)
            number(text("Left", "Слева"), $state.options.left)
            number(text("Right", "Справа"), $state.options.right)
            number(text("Top", "Сверху"), $state.options.top)
            number(text("Bottom", "Снизу"), $state.options.bottom)
            Text(text("Red outline shows the new visible region. Content is preserved.", "Красная рамка — новая видимая область. Содержимое сохраняется.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func number(_ name: String, _ value: Binding<Double>) -> some View {
        HStack { Text(name); Spacer(); TextField("", value: value, format: .number).frame(width: 82) }
    }
    private var decorationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if request.kind == .header {
                Text(text("Header", "Верхний колонтитул")).font(.headline)
                TextField(text("Left", "Слева"), text: $state.options.headerLeft)
                TextField(text("Center", "По центру"), text: $state.options.headerCenter)
                TextField(text("Right", "Справа"), text: $state.options.headerRight)
                Text(text("Footer", "Нижний колонтитул")).font(.headline)
                TextField(text("Left", "Слева"), text: $state.options.footerLeft)
                TextField(text("Center", "По центру"), text: $state.options.footerCenter)
                TextField(text("Right", "Справа"), text: $state.options.footerRight)
            } else {
                TextField(text("Text / template", "Текст / шаблон"), text: $state.options.text, axis: .vertical).lineLimit(2...4)
                Picker(text("Position", "Положение"), selection: $state.options.position) {
                    Text(text("Top", "Вверху")).tag(0); Text(text("Center", "По центру")).tag(1); Text(text("Bottom", "Внизу")).tag(2)
                }
                Picker(text("Alignment", "Выравнивание"), selection: $state.options.alignment) {
                    Text(text("Left", "Слева")).tag(0); Text(text("Center", "По центру")).tag(1); Text(text("Right", "Справа")).tag(2)
                }
            }
            Text("{page} · {pages} · {file} · {date} · {bates}").font(.caption).textSelection(.enabled)
            if request.kind == .bates {
                HStack {
                    Text(text("Start", "Начало")); Spacer()
                    TextField("", value: $state.options.batesStart, format: .number).frame(width: 100)
                }
                Stepper(text("Digits: \(state.options.batesDigits)", "Цифр: \(state.options.batesDigits)"), value: $state.options.batesDigits, in: 1...12)
            }
            Picker(text("Font", "Шрифт"), selection: $state.options.fontName) {
                ForEach(state.fontNames, id: \.self) { Text($0).tag($0) }
            }
            number(text("Size (pt)", "Размер (pt)"), $state.options.fontSize)
            ColorPicker(text("Color", "Цвет"), selection: $state.options.color, supportsOpacity: false)
            opacityControl
            Text(text("Apply replaces this type of BotPlus decoration in the chosen range.", "Применение заменяет оформление этого типа, созданное этой версией BotPlus, в выбранном диапазоне.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var opacityControl: some View {
        VStack(alignment: .leading) {
            Text(text("Opacity", "Непрозрачность") + " \(Int(state.options.opacity * 100))%")
            Slider(value: $state.options.opacity, in: 0...1)
        }
    }
    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(text("Background color", "Цвет фона"), selection: $state.options.color, supportsOpacity: false).disabled(state.options.image != nil)
            opacityControl
            Button(text("Choose image…", "Выбрать изображение…")) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          image.width <= 16_384, image.height <= 16_384, image.width * image.height <= 40_000_000 else {
                        state.error = text("Cannot read image or image exceeds 40 MP.", "Не удалось прочитать изображение или размер превышает 40 Мп."); return
                    }
                    state.options.image = image; state.options.imageName = url.lastPathComponent
                }
            }
            if state.options.image != nil {
                Text(state.options.imageName).font(.caption)
                Button(text("Use color only", "Только цвет")) { state.options.image = nil; state.options.imageName = "" }
            }
            Text(text("Color or image is inserted behind the original content. Opaque white fills in the original may cover the background.", "Цвет или изображение вставляется за исходным содержимым. Белые непрозрачные заливки исходного PDF могут закрыть фон.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text("Format", "Формат"), selection: $state.options.format) {
                ForEach(PDFImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }
            Picker("DPI", selection: $state.options.dpi) { ForEach([72, 96, 150, 200, 300, 600], id: \.self) { Text(String($0)).tag($0) } }
            Toggle(text("Transparent paper", "Прозрачный лист"), isOn: $state.options.transparent).disabled(state.options.format == .jpeg)
            if state.options.format == .jpeg {
                Text(text("JPEG quality", "Качество JPEG")); Slider(value: $state.options.jpegQuality, in: 0.1...1)
            }
            if let page = request.document.page(at: state.previewPage) {
                let box = page.bounds(for: .cropBox)
                let rotated = abs(page.rotation % 180) == 90
                let width = Int(ceil((rotated ? box.height : box.width) * Double(state.options.dpi) / 72))
                let height = Int(ceil((rotated ? box.width : box.height) * Double(state.options.dpi) / 72))
                Text("\(width) × \(height) px").font(.caption)
            }
            Text(text("Export runs from an independent PDF snapshot, with progress and cancellation. Files go into a new subfolder; existing files are kept.", "Экспорт использует отдельный снимок PDF, показывает прогресс и поддерживает отмену. Файлы записываются в новую подпапку; существующие файлы сохраняются.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct PDFFormattingPreview: NSViewRepresentable {
    let request: PDFFormattingRequest
    let options: PDFFormattingOptions
    let pageIndex: Int
    func makeNSView(context: Context) -> FormattingPreviewView {
        let view = FormattingPreviewView(); view.clipsToBounds = true; return view
    }
    func updateNSView(_ view: FormattingPreviewView, context: Context) {
        view.configure(request: request, options: options, pageIndex: pageIndex)
    }
}

@MainActor
enum PDFFormattingGeometry {
    static func transform(_ page: PDFPage, box: PDFDisplayBox, target: CGRect) -> CGAffineTransform {
        if let ref = page.pageRef { return ref.getDrawingTransform(box == .mediaBox ? .mediaBox : .cropBox, rect: target, rotate: 0, preserveAspectRatio: true) }
        let source = page.bounds(for: box)
        let rotation = CGAffineTransform(rotationAngle: -CGFloat(page.rotation) * .pi / 180)
        let local = CGAffineTransform(translationX: -source.minX, y: -source.minY).concatenating(rotation)
        let rotated = source.applying(local)
        let scale = min(target.width / max(1, rotated.width), target.height / max(1, rotated.height))
        return local.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: target.midX - rotated.midX * scale, y: target.midY - rotated.midY * scale))
    }
}

@MainActor
private final class FormattingPreviewView: NSView {
    private var request: PDFFormattingRequest?
    private var options = PDFFormattingOptions()
    private var index = 0
    private var cachedIdentity: ObjectIdentifier?
    private var baseImage: NSImage?
    private var previewApplies = false
    func configure(request: PDFFormattingRequest, options: PDFFormattingOptions, pageIndex: Int) {
        self.request = request; self.options = options; index = pageIndex
        guard let page = request.document.page(at: pageIndex) else { return }
        let applies = (PDFPageRange.parse(options.range, count: request.document.pageCount) ?? []).contains(pageIndex)
        if cachedIdentity != ObjectIdentifier(page) || previewApplies != applies {
            previewApplies = applies
            cachedIdentity = ObjectIdentifier(page)
            let box: CGPDFBox = request.kind == .margins ? .mediaBox : .cropBox
            let source = page.bounds(for: request.kind == .margins ? .mediaBox : .cropBox)
            let rotated = abs(page.rotation % 180) == 90
            let size = NSSize(width: rotated ? source.height : source.width, height: rotated ? source.width : source.height)
            let scale = min(1, 800 / max(size.width, size.height))
            baseImage = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale), flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.clear(rect)
                context.saveGState(); context.concatenate(PDFFormattingGeometry.transform(page, box: box == .mediaBox ? .mediaBox : .cropBox, target: rect))
                if let ref = page.pageRef { context.drawPDFPage(ref) }
                for annotation in page.annotations where annotation.shouldDisplay && (!applies || !request.isOwned(annotation)) {
                    annotation.draw(with: request.kind == .margins ? .mediaBox : .cropBox, in: context)
                }
                context.restoreGState(); return true
            }
            // Materialize once. Slider/text changes reuse the page raster.
            baseImage?.cacheMode = .always
            _ = baseImage?.tiffRepresentation
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); bounds.fill()
        guard let request, let page = request.document.page(at: index), let image = baseImage,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min((bounds.width - 24) / image.size.width, (bounds.height - 24) / image.size.height)
        let rect = CGRect(x: (bounds.width - image.size.width * scale) / 2, y: (bounds.height - image.size.height * scale) / 2,
                          width: image.size.width * scale, height: image.size.height * scale)
        NSColor.white.setFill(); rect.fill()
        if previewApplies && request.kind == .background {
            if let cgImage = options.image {
                context.saveGState(); context.setAlpha(options.opacity); context.draw(cgImage, in: rect); context.restoreGState()
            } else { PDFColorComponents(options.color, opacity: options.opacity).nsColor.setFill(); rect.fill() }
        }
        image.draw(in: rect)
        context.saveGState(); context.clip(to: rect)
        context.concatenate(PDFFormattingGeometry.transform(page, box: request.kind == .margins ? .mediaBox : .cropBox, target: rect))
        if previewApplies && request.kind == .margins {
            let media = page.bounds(for: .mediaBox)
            let crop = CGRect(x: media.minX + options.left, y: media.minY + options.bottom,
                              width: media.width - options.left - options.right, height: media.height - options.top - options.bottom)
            context.setStrokeColor(NSColor.systemRed.cgColor); context.setLineWidth(2 / scale)
            if [crop.minX, crop.minY, crop.width, crop.height].allSatisfy({ $0.isFinite }), crop.width > 0 && crop.height > 0 { context.stroke(crop) }
        } else if previewApplies && [.header, .watermark, .bates].contains(request.kind) {
            for annotation in PDFDecorationEngine.annotations(kind: request.kind, options: options, box: page.bounds(for: .cropBox),
                page: index, count: request.document.pageCount, filename: request.filename, sequence: (PDFPageRange.parse(options.range, count: request.document.pageCount) ?? []).firstIndex(of: index) ?? 0, russian: request.russian) {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = annotation.alignment
                NSAttributedString(string: annotation.contents ?? "", attributes: [.font: annotation.font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: annotation.fontColor ?? .black, .paragraphStyle: paragraph]).draw(in: annotation.bounds)
            }
        }
        context.restoreGState()
    }
}

struct PDFImageExportOptions: Sendable {
    let indices: [Int]
    let format: PDFImageFormat
    let dpi: Int
    let transparent: Bool
    let quality: Double
}

enum PDFImageExportError: Error {
    case invalidPDF, tooLarge, render, encode
}
enum PDFImageExporter {
    static func dimensions(_ page: PDFPage, dpi: Int) -> (Int, Int) {
        let box = page.bounds(for: .cropBox)
        let rotated = abs(page.rotation % 180) == 90
        let width = ceil((rotated ? box.height : box.width) * Double(dpi) / 72)
        let height = ceil((rotated ? box.width : box.height) * Double(dpi) / 72)
        guard dpi > 0, width.isFinite, height.isFinite, width > 0, height > 0, width <= 1_000_000, height <= 1_000_000 else { return (0, 0) }
        return (Int(width), Int(height))
    }
    static func export(data: Data, to folder: URL, options: PDFImageExportOptions,
                       progress: @Sendable (Double) -> Void) throws -> Int {
        guard let document = PDFDocument(data: data), !document.isLocked else { throw PDFImageExportError.invalidPDF }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
        for (position, index) in options.indices.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index), let ref = page.pageRef else { throw PDFImageExportError.invalidPDF }
                let (width, height) = dimensions(page, dpi: options.dpi)
                guard width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000 else { throw PDFImageExportError.tooLarge }
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PDFImageExportError.render }
                let context = graphics.cgContext
                let target = CGRect(x: 0, y: 0, width: width, height: height)
                context.clear(target)
                if !options.transparent || options.format == .jpeg { context.setFillColor(NSColor.white.cgColor); context.fill(target) }
                context.saveGState(); context.concatenate(ref.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                context.drawPDFPage(ref)
                for annotation in page.annotations where annotation.shouldDisplay && annotation.shouldPrint {
                    if !(annotation.contents ?? "").hasPrefix("BotPlus PDF Editor metadata v1:") {
                        annotation.draw(with: .cropBox, in: context)
                    }
                }
                NSGraphicsContext.restoreGraphicsState(); context.restoreGState()
                bitmap.size = NSSize(width: Double(width) * 72 / Double(options.dpi), height: Double(height) * 72 / Double(options.dpi))
                let properties: [NSBitmapImageRep.PropertyKey: Any] = options.format == .jpeg ? [.compressionFactor: options.quality] : [:]
                guard let bytes = bitmap.representation(using: options.format.bitmapType, properties: properties) else { throw PDFImageExportError.encode }
                try Task.checkCancellation()
                let name = "Page-" + String(repeating: "0", count: max(0, 4 - String(index + 1).count)) + String(index + 1) + "." + options.format.fileExtension
                try bytes.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            progress(Double(position + 1) / Double(options.indices.count))
        }
        complete = true
        return options.indices.count
    }
}
