// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus
import SwiftUI
import AppKit
import PDFKit
import ImageIO

struct PDFPageWorkflowOptions {
    var range = "all"
    var splitMode = 0
    var groupSize = 1
}
@MainActor
struct PDFPageWorkflowRequest: Identifiable {
    let id = UUID()
    let kind: String
    let russian: Bool
    let count: Int
    let current: Int
    let bookmarkStarts: [Int]
    let apply: (PDFPageWorkflowOptions) -> String?
    var title: String { kind == "extract" ? (russian ? "Извлечь страницы" : "Extract pages") : kind == "split" ? (russian ? "Разделить PDF" : "Split PDF") : (russian ? "Порядок страниц" : "Page order") }
}

enum PDFPagePlan {
    static func order(_ text: String, count: Int) -> [Int]? {
        guard count > 0, text.count <= 200_000 else { return nil }
        if ["all","все","*"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) { return Array(0..<count) }
        let parts = text.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: ";", with: ",").components(separatedBy: ",")
        var result: [Int] = []; var seen = Set<Int>()
        for part in parts {
            let ends = part.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "-")
            guard ends.count <= 2, let first = Int(ends[0].trimmingCharacters(in: .whitespaces)), (1...count).contains(first) else { return nil }
            let last = ends.count == 1 ? first : Int(ends[1].trimmingCharacters(in: .whitespaces)) ?? 0
            guard (1...count).contains(last) else { return nil }
            for value in stride(from: first, through: last, by: first <= last ? 1 : -1) {
                guard seen.insert(value-1).inserted else { return nil }; result.append(value-1)
            }
        }
        return result.isEmpty ? nil : result
    }
    static func groups(indices: [Int], size: Int, starts: [Int]?) -> [[Int]] {
        guard !indices.isEmpty else { return [] }
        if let starts {
            let boundaries = starts.sorted(); var result: [[Int]] = []; var current: [Int] = []; var previousSection: Int?
            for index in indices {
                let section = boundaries.lastIndex(where: { $0 <= index }) ?? -1
                if previousSection != nil && previousSection != section { result.append(current); current = [] }
                current.append(index); previousSection = section
            }
            if !current.isEmpty { result.append(current) }; return result
        }
        guard size > 0 else { return [] }
        return stride(from: 0, to: indices.count, by: size).map { Array(indices[$0..<min(indices.count,$0+size)]) }
    }
}

@MainActor
private final class PDFPageWorkflowModel: ObservableObject {
    @Published var options = PDFPageWorkflowOptions()
    @Published var error = ""
    let request: PDFPageWorkflowRequest
    init(_ request: PDFPageWorkflowRequest) { self.request = request; if request.kind == "extract" { options.range = String(request.current+1) } }
    var indices: [Int]? { request.kind == "swap" ? PDFPagePlan.order(options.range, count: request.count) : PDFPageRange.parse(options.range, count: request.count) }
    var summary: String {
        guard let indices else { return request.russian ? "Некорректный диапазон" : "Invalid page range" }
        if request.kind == "swap" { return indices.count == request.count ? (request.russian ? "Все страницы указаны один раз" : "Every page appears once") : (request.russian ? "Укажите все страницы ровно один раз" : "Include every page exactly once") }
        let groups = request.kind == "split" ? PDFPagePlan.groups(indices: indices, size: options.groupSize, starts: options.splitMode == 1 ? request.bookmarkStarts : nil).count : 1
        return request.russian ? "Страниц: \(indices.count). Файлов: \(groups)." : "Pages: \(indices.count). Files: \(groups)."
    }
}

@MainActor
struct PDFPageWorkflowEditor: View {
    @StateObject private var model: PDFPageWorkflowModel
    @Environment(\.dismiss) private var dismiss
    init(request: PDFPageWorkflowRequest) { _model = StateObject(wrappedValue: PDFPageWorkflowModel(request)) }
    private func t(_ ru: String, _ en: String) -> String { model.request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.request.title).font(.title2)
            Text(t("Страниц в документе: \(model.request.count)", "Document pages: \(model.request.count)"))
            TextField(model.request.kind == "swap" ? t("Порядок: 3-1, 4-8", "Order: 3-1, 4-8") : t("Диапазон: 1-3, 7 или все", "Range: 1-3, 7 or all"), text: $model.options.range).textFieldStyle(.roundedBorder)
            if model.request.kind == "split" {
                Picker(t("Разделить", "Split by"), selection: $model.options.splitMode) {
                    Text(t("По числу страниц", "Page count")).tag(0)
                    Text(t("По закладкам первого уровня", "Top-level bookmarks")).tag(1)
                }.pickerStyle(.segmented)
                if model.options.splitMode == 0 { Stepper(t("Страниц в файле: \(model.options.groupSize)", "Pages per file: \(model.options.groupSize)"), value: $model.options.groupSize, in: 1...max(1,model.request.count)) }
                else { Text(t("Целей закладок: \(model.request.bookmarkStarts.count)", "Bookmark targets: \(model.request.bookmarkStarts.count)")) }
            }
            Text(model.summary).foregroundStyle(.secondary)
            Text(t("Закладки и прямые внутренние переходы сохраняются. При экспорте переходы за пределы выбранных страниц удаляются. Результат экспорта — отдельный PDF без шифрования исходника.", "Bookmarks and direct internal links are preserved. Export removes targets outside selected pages. Export creates a separate PDF without the source encryption.")).font(.caption).foregroundStyle(.secondary)
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            HStack {
                Spacer(); Button(t("Отмена", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.request.kind == "swap" ? t("Применить", "Apply") : t("Продолжить…", "Continue…")) {
                    if let error = model.request.apply(model.options) { model.error = error } else { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

enum PDFSubsetError: Error { case invalidPlan, copy, save }
// Only an independent worker PDFDocument enters this builder. Pages and the
// source owner stay alive until serialization, so resource references are valid.
enum PDFSubsetBuilder {
    static func build(_ source: PDFDocument, indices: [Int], progress: (Double) -> Void = { _ in }) throws -> Data {
        guard !indices.isEmpty, Set(indices).count == indices.count, indices.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) else { throw PDFSubsetError.invalidPlan }
        let output = PDFDocument(); output.documentAttributes = source.documentAttributes
        var mapping: [ObjectIdentifier: PDFPage] = [:]
        for (position,index) in indices.enumerated() {
            try Task.checkCancellation()
            guard let page = source.page(at: index), let copy = page.copy() as? PDFPage else { throw PDFSubsetError.copy }
            mapping[ObjectIdentifier(page)] = copy; output.insert(copy, at: output.pageCount)
            progress(Double(position+1)/Double(indices.count))
        }
        func mapped(_ destination: PDFDestination) -> PDFDestination? {
            guard let page = destination.page, let copy = mapping[ObjectIdentifier(page)] else { return nil }
            let next = PDFDestination(page: copy, at: destination.point); next.zoom = destination.zoom; return next
        }
        for index in 0..<output.pageCount { for annotation in output.page(at: index)?.annotations ?? [] {
            if let action = annotation.action as? PDFActionGoTo {
                let next = mapped(action.destination)
                annotation.removeValue(forAnnotationKey: .destination)
                annotation.removeValue(forAnnotationKey: .action)
                annotation.action = next.map(PDFActionGoTo.init(destination:))
            }
        } }
        func clone(_ node: PDFOutline) -> PDFOutline? {
            let copy = PDFOutline(); copy.label = node.label; copy.isOpen = node.isOpen
            if let destination = node.destination { copy.destination = mapped(destination) }
            if let action = node.action as? PDFActionGoTo { copy.action = mapped(action.destination).map(PDFActionGoTo.init(destination:)) }
            else if let action = node.action { copy.action = action }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index), let result = clone(child) { copy.insertChild(result, at: copy.numberOfChildren) } }
            return copy.destination != nil || copy.action != nil || copy.numberOfChildren > 0 ? copy : nil
        }
        if let root = source.outlineRoot {
            let next = PDFOutline()
            for index in 0..<root.numberOfChildren { if let child = root.child(at: index), let copy = clone(child) { next.insertChild(copy, at: next.numberOfChildren) } }
            if next.numberOfChildren > 0 { output.outlineRoot = next }
        }
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlusSubset-"+UUID().uuidString+".pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard output.write(to: temporary,withOptions: [PDFDocumentWriteOption.saveTextFromOCROption:false]) else { throw PDFSubsetError.save }
        let data = try Data(contentsOf: temporary)
        withExtendedLifetime(source) {}; return data
    }
    static func export(data: Data, groups: [[Int]], to url: URL, split: Bool, progress: @Sendable (Double) -> Void) throws -> Int {
        guard let source = PDFDocument(data: data), !source.isLocked, !groups.isEmpty else { throw PDFSubsetError.invalidPlan }
        var complete = false
        if split { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        defer { if split && !complete { try? FileManager.default.removeItem(at: url) } }
        let total = groups.reduce(0) { $0+$1.count }; var finished = 0
        var lastUpdate = -Double.infinity
        func report(_ value: Double) {
            let now = ProcessInfo.processInfo.systemUptime
            if value >= 1 || now-lastUpdate >= 1.0/30.0 { lastUpdate = now; progress(value) }
        }
        for (position,indices) in groups.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let bytes = try build(source, indices: indices) { value in report((Double(finished)+value*Double(indices.count))/Double(max(1,total))) }
                let destination = split ? url.appendingPathComponent(String(format: "Part-%03d.pdf",position+1)) : url
                try Task.checkCancellation(); try bytes.write(to: destination, options: .atomic)
            }
            finished += indices.count
        }
        complete = true; return groups.count
    }
}

enum PDFPageSpacing {
    static func clamp(_ value: Double) -> Double { value.isFinite ? min(40,max(0,value)) : 4 }
}

enum PDFSnapshotRenderer {
    static func preview(_ png: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 500, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let result = NSBitmapImageRep(cgImage: image).representation(using: .png,properties: [:]) else { throw PDFImageExportError.encode }
        return result
    }
    static func render(data: Data, index: Int, region: CGRect, dpi: Int, transparent: Bool = false) throws -> Data {
        guard let document = PDFDocument(data: data), let page = document.page(at: index), (72...600).contains(dpi),
              [region.minX,region.minY,region.width,region.height].allSatisfy({ $0.isFinite }) else { throw PDFImageExportError.invalidPDF }
        let crop = page.bounds(for: .cropBox), clipped = region.intersection(crop)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { throw PDFImageExportError.render }
        let factor = CGFloat(dpi)/72, rotated = abs(page.rotation%180) == 90
        let canvas = CGRect(x: 0,y: 0,width: (rotated ? crop.height : crop.width)*factor,height: (rotated ? crop.width : crop.height)*factor)
        let transform = PDFFormattingGeometry.transform(page, box: .cropBox, target: canvas)
        let target = clipped.applying(transform).standardized
        let w = ceil(target.width-0.0000001), h = ceil(target.height-0.0000001)
        guard w.isFinite, h.isFinite, w > 0, h > 0, w <= 20000, h <= 20000, w*h <= 40_000_000 else { throw PDFImageExportError.tooLarge }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PDFImageExportError.render }
        let context = graphics.cgContext; context.clear(CGRect(x: 0,y: 0,width: w,height: h))
        if !transparent { context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0,y: 0,width: w,height: h)) }
        context.translateBy(x: -target.minX,y: -target.minY); context.concatenate(transform)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        if let ref = page.pageRef { context.drawPDFPage(ref) }
        for annotation in page.annotations where annotation.shouldDisplay && !(annotation.contents ?? "").hasPrefix("BotPlus PDF Editor metadata v1:") { annotation.draw(with: .cropBox,in: context) }
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: w/factor,height: h/factor)
        try Task.checkCancellation()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PDFImageExportError.encode }
        withExtendedLifetime(document) {}; return png
    }
}
