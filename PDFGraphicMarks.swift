// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
struct PDFGraphicMarkRequest: Identifiable {
    let id = UUID()
    let kind: String
    let russian: Bool
    let filename: String
    let page: Int
    let apply: (CGImage) -> String?
    var title: String { kind == "stamp" ? (russian ? "Штамп" : "Stamp") : kind == "initials" ? (russian ? "Инициалы" : "Initials") : (russian ? "Графическая подпись" : "Graphic signature") }
}

struct PDFGraphicMarkPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var mode: Int
    var text: String
    var font: String
    var size: Double
    var red: Double, green: Double, blue: Double, opacity: Double
    var thickness: Double
    var border: Bool
    var strokes: [[CGPoint]]
    var image: Data?
    var isValid: Bool {
        (0...2).contains(mode) && name.count <= 80 && text.count <= 4000 && font.count <= 200 &&
        [size, red, green, blue, opacity, thickness].allSatisfy { $0.isFinite } &&
        (8...120).contains(size) && [red,green,blue,opacity].allSatisfy { (0...1).contains($0) } &&
        (0.5...40).contains(thickness) && strokes.count <= 1000 && strokes.reduce(0) { $0+$1.count } <= 100000 &&
        strokes.flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } &&
        (image?.count ?? 0) <= 2_000_000
    }
}

@MainActor
final class PDFGraphicMarkModel: ObservableObject {
    @Published var mode = 0
    @Published var text: String
    @Published var font = "Helvetica"
    @Published var size: Double = 56
    @Published var color: Color = .black
    @Published var opacity: Double = 1
    @Published var thickness: Double = 3
    @Published var border: Bool
    @Published var strokes: [[CGPoint]] = []
    @Published var image: CGImage?
    @Published var error = ""
    @Published var name = ""
    @Published var presets: [PDFGraphicMarkPreset]
    let request: PDFGraphicMarkRequest
    let fonts = NSFontManager.shared.availableFonts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    private let key = "BotPlusPDFEditor.graphicMarks.v1"
    init(request: PDFGraphicMarkRequest) {
        self.request = request
        text = request.kind == "stamp" ? (request.russian ? "СОГЛАСОВАНО\n{date}" : "APPROVED\n{date}") : ""
        border = request.kind == "stamp"
        presets = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PDFGraphicMarkPreset].self, from: $0) } ?? []).filter { $0.isValid }.prefix(20).map { $0 }
        if request.kind == "stamp" { color = .red; size = 42 }
    }
    var hasContent: Bool {
        opacity > 0 && (mode == 0 ? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : mode == 1 ? strokes.contains { !$0.isEmpty } : image != nil)
    }
    func rendered(date: Date = Date()) -> CGImage? {
        Self.render(mode: mode, text: expanded(text, date: date), font: font, size: size,
                    color: NSColor(color).withAlphaComponent(opacity), thickness: thickness,
                    border: border, strokes: strokes, image: image)
    }
    func expanded(_ source: String, date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: request.russian ? "ru_RU" : "en_US"); formatter.dateStyle = .medium
        return source.replacingOccurrences(of: "{date}", with: formatter.string(from: date))
            .replacingOccurrences(of: "{file}", with: request.filename)
            .replacingOccurrences(of: "{page}", with: String(request.page+1))
    }
    static func render(mode: Int, text: String, font: String, size: Double, color: NSColor,
                       thickness: Double, border: Bool, strokes: [[CGPoint]], image: CGImage?) -> CGImage? {
        guard size.isFinite, thickness.isFinite, color.alphaComponent > 0 else { return nil }
        if mode == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if mode == 1 && !strokes.contains(where: { !$0.isEmpty }) { return nil }
        if mode == 2 && image == nil { return nil }
        let width = 1200, height = 400
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        if mode == 2, let image {
            let factor = min(1160/CGFloat(image.width), 360/CGFloat(image.height))
            let w = CGFloat(image.width)*factor, h = CGFloat(image.height)*factor
            context.setAlpha(color.alphaComponent)
            context.draw(image, in: CGRect(x: (1200-w)/2, y: (400-h)/2, width: w, height: h))
        } else if mode == 1 {
            context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
            context.setLineCap(.round); context.setLineJoin(.round); context.setLineWidth(min(40, max(0.5, thickness))*2)
            for stroke in strokes {
                let points = stroke.filter { $0.x.isFinite && $0.y.isFinite }.map { CGPoint(x: min(1,max(0,$0.x))*1200, y: (1-min(1,max(0,$0.y)))*400) }
                guard let first = points.first else { continue }
                if points.count == 1 { context.fillEllipse(in: CGRect(x: first.x-thickness, y: first.y-thickness, width: thickness*2, height: thickness*2)); continue }
                context.beginPath(); context.move(to: first)
                for point in points.dropFirst() { context.addLine(to: point) }; context.strokePath()
            }
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            var fontSize = min(120,max(8,size))*2
            let target = rect.insetBy(dx: 35, dy: 25)
            var attributed = NSAttributedString()
            var measured = CGSize.zero
            for _ in 0..<8 {
                attributed = NSAttributedString(string: String(text.prefix(4000)), attributes: [.font: NSFont(name: font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize), .foregroundColor: color, .paragraphStyle: paragraph])
                measured = attributed.boundingRect(with: CGSize(width: target.width, height: 10000), options: [.usesLineFragmentOrigin,.usesFontLeading]).size
                if measured.height <= target.height { break }; fontSize *= 0.75
            }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            context.saveGState(); context.clip(to: target)
            attributed.draw(with: CGRect(x: target.minX, y: target.midY-min(measured.height,target.height)/2, width: target.width, height: min(measured.height,target.height)), options: [.usesLineFragmentOrigin,.usesFontLeading])
            context.restoreGState(); NSGraphicsContext.restoreGraphicsState()
        }
        if border {
            context.setStrokeColor(color.cgColor); context.setLineWidth(min(20,max(1,thickness))*2)
            context.stroke(rect.insetBy(dx: 8, dy: 8))
        }
        return context.makeImage()
    }
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384, width*height <= 40_000_000 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary)
    }
    func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff]; panel.allowsMultipleSelection = false
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32_000_000,
                  let data = try? Data(contentsOf: url), let image = Self.decodeImage(data) else {
                self.error = self.request.russian ? "Не удалось прочитать изображение (до 40 Мп / 32 МБ)." : "Cannot read image (40 MP / 32 MB limit)."; return
            }
            self.image = image; self.mode = 2; self.error = ""
        }
    }
    func savePreset() {
        guard rendered() != nil else { error = request.russian ? "Сначала создайте подпись или штамп." : "Create a mark first."; return }
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        // Imports are downsampled once by ImageIO; keep the unstyled source
        // so repeatedly loading/saving a preset never adds padding or opacity.
        let png = image.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        guard (png?.count ?? 0) <= 2_000_000 else { error = request.russian ? "Изображение слишком большое для шаблона." : "Image is too large for a preset."; return }
        let preset = PDFGraphicMarkPreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? request.title : String(name.prefix(80)), mode: mode, text: String(text.prefix(4000)), font: font, size: size, red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, opacity: opacity, thickness: thickness, border: border, strokes: strokes.map { Array($0.prefix(10000)) }, image: png)
        guard preset.isValid else { error = request.russian ? "Слишком сложный шаблон." : "Preset is too complex."; return }
        let next = Array(([preset]+presets).prefix(20))
        guard let encoded = try? JSONEncoder().encode(next), encoded.count <= 16_000_000 else { error = request.russian ? "Библиотека превышает 16 МБ." : "Library exceeds 16 MB."; return }
        presets = next; persist(); error = ""
    }
    func load(_ preset: PDFGraphicMarkPreset) {
        guard preset.isValid else { return }
        mode = preset.mode; text = preset.text; font = preset.font; size = preset.size
        color = Color(red: preset.red, green: preset.green, blue: preset.blue); opacity = preset.opacity
        thickness = preset.thickness; border = preset.border; strokes = preset.strokes
        image = preset.image.flatMap(Self.decodeImage)
        name = preset.name; error = ""
    }
    func delete(_ preset: PDFGraphicMarkPreset) { presets.removeAll { $0.id == preset.id }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) } }
    func exportLibrary() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "BotPlus-marks.json"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(self.presets).write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
    func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 16_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let imported = try JSONDecoder().decode([PDFGraphicMarkPreset].self, from: Data(contentsOf: url))
                guard imported.count <= 20, imported.allSatisfy({ $0.isValid && ($0.mode != 2 || $0.image.flatMap(Self.decodeImage) != nil) }), Set(imported.map(\.id)).count == imported.count else { throw CocoaError(.fileReadCorruptFile) }
                var next = self.presets
                for preset in imported { next.removeAll { $0.id == preset.id }; next.append(preset) }
                guard next.count <= 20, (try JSONEncoder().encode(next)).count <= 16_000_000 else { throw CocoaError(.fileReadTooLarge) }
                self.presets = next; self.persist(); self.error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    func exportPNG() {
        guard let image = rendered() else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "BotPlus-mark.png"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }; try data.write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor
struct PDFGraphicMarkEditor: View {
    @StateObject private var model: PDFGraphicMarkModel
    @Environment(\.dismiss) private var dismiss
    init(request: PDFGraphicMarkRequest) { _model = StateObject(wrappedValue: PDFGraphicMarkModel(request: request)) }
    private func t(_ ru: String, _ en: String) -> String { model.request.russian ? ru : en }
    var body: some View {
        let preview = model.mode == 1 ? nil : model.rendered()
        VStack(alignment: .leading, spacing: 12) {
            Text(model.request.title).font(.title2)
            Text(t("Графический объект; не цифровая подпись с сертификатом.", "Graphic object; not a certificate-based digital signature.")).font(.caption).foregroundStyle(.secondary)
            Picker(t("Способ", "Mode"), selection: $model.mode) {
                Text(t("Текст", "Text")).tag(0); Text(t("Нарисовать", "Draw")).tag(1); Text(t("Изображение", "Image")).tag(2)
            }.pickerStyle(.segmented)
            if model.mode == 0 {
                TextField(t("Подпись / инициалы / текст штампа", "Signature / initials / stamp text"), text: $model.text, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                HStack {
                    Picker(t("Шрифт", "Font"), selection: $model.font) { ForEach(model.fonts, id: \.self) { Text($0).tag($0) } }.frame(width: 280)
                    Stepper("\(Int(model.size)) pt", value: $model.size, in: 8...120)
                }
                Text(t("Шаблоны: {date}, {file}, {page}", "Templates: {date}, {file}, {page}")).font(.caption).foregroundStyle(.secondary)
            }
            if model.mode == 2 { Button(t("Импорт PNG / JPEG / TIFF", "Import PNG / JPEG / TIFF")) { model.importImage() } }
            HStack {
                ColorPicker(t("Цвет", "Color"), selection: $model.color, supportsOpacity: false)
                Text(t("Непрозрачность", "Opacity")); Slider(value: $model.opacity, in: 0.1...1).frame(width: 100)
                Toggle(t("Рамка", "Border"), isOn: $model.border)
            }
            if model.mode == 1 || model.border { Stepper(t("Толщина: \(Int(model.thickness))", "Width: \(Int(model.thickness))"), value: $model.thickness, in: 1...20) }
            Group {
                if model.mode == 1 { GraphicMarkDrawingSurface(model: model) }
                else if let image = preview { Image(decorative: image, scale: 2).resizable().scaledToFit() }
                else { Text(t("Введите текст или импортируйте изображение", "Enter text or import an image")).foregroundStyle(.secondary) }
            }.frame(width: 600, height: 200).background(Color.white).overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
            if model.mode == 1 { Button(t("Очистить рисунок", "Clear drawing")) { model.strokes = [] } }
            HStack {
                TextField(t("Имя шаблона", "Preset name"), text: $model.name).textFieldStyle(.roundedBorder)
                Button(t("Сохранить шаблон", "Save preset")) { model.savePreset() }.disabled(!model.hasContent)
                Button(t("Экспорт PNG", "Export PNG")) { model.exportPNG() }.disabled(!model.hasContent)
            }
            HStack {
                Button(t("Импорт библиотеки", "Import library")) { model.importLibrary() }
                Button(t("Экспорт библиотеки", "Export library")) { model.exportLibrary() }.disabled(model.presets.isEmpty)
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.presets) { preset in
                        HStack(spacing: 4) {
                            Button(preset.name) { model.load(preset) }
                            Button { model.delete(preset) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.padding(6).background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }.frame(height: 40)
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer(); Button(t("Отмена", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(t("Вставить на страницу", "Insert on page")) {
                    guard let image = model.rendered() else { return }
                    if let error = model.request.apply(image) { model.error = error } else { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(!model.hasContent)
            }
        }.padding(20).frame(width: 640)
    }
}

@MainActor
private struct GraphicMarkDrawingSurface: NSViewRepresentable {
    @ObservedObject var model: PDFGraphicMarkModel
    func makeNSView(context: Context) -> DrawingView { let view = DrawingView(); view.model = model; return view }
    func updateNSView(_ view: DrawingView, context: Context) { view.model = model; view.needsDisplay = true }
    final class DrawingView: NSView {
        weak var model: PDFGraphicMarkModel?
        override var isFlipped: Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func draw(_ dirtyRect: NSRect) {
            guard let model else { return }
            let color = NSColor(model.color).withAlphaComponent(model.opacity); color.setStroke(); color.setFill()
            if model.border { let edge = NSBezierPath(rect: bounds.insetBy(dx: 4,dy: 4)); edge.lineWidth = CGFloat(model.thickness); edge.stroke() }
            for stroke in model.strokes {
                guard let first = stroke.first else { continue }
                let path = NSBezierPath(); path.lineWidth = CGFloat(model.thickness); path.lineCapStyle = .round; path.lineJoinStyle = .round
                path.move(to: CGPoint(x: first.x*bounds.width, y: first.y*bounds.height))
                if stroke.count == 1 { NSBezierPath(ovalIn: CGRect(x: first.x*bounds.width-model.thickness/2, y: first.y*bounds.height-model.thickness/2, width: model.thickness, height: model.thickness)).fill() }
                for point in stroke.dropFirst() { path.line(to: CGPoint(x: point.x*bounds.width, y: point.y*bounds.height)) }; path.stroke()
            }
        }
        private func normalized(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: min(1,max(0,p.x/max(1,bounds.width))), y: min(1,max(0,p.y/max(1,bounds.height))))
        }
        override func mouseDown(with event: NSEvent) { if (model?.strokes.count ?? 0) < 1000 { model?.strokes.append([normalized(event)]) } }
        override func mouseDragged(with event: NSEvent) {
            guard let model, !model.strokes.isEmpty else { return }
            let index = model.strokes.count-1
            if model.strokes.reduce(0, { $0+$1.count }) < 100000 && model.strokes[index].count < 10000 { model.strokes[index].append(normalized(event)) }
        }
    }
}
