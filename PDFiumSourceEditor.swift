import AppKit
import CoreText
import CPDFium

/// Content changes happen in an independent PDFium snapshot. The visible
/// PDFDocument is replaced only after the complete block has been serialized.
enum PDFSourceError: Error {
    case document, page, textNotFound, font, content, save, alreadyUsed, permission, unsupportedGlyph
    var english: String {
        switch self {
        case .document: "Could not open this PDF for content editing."
        case .page: "The PDF page is unavailable."
        case .textNotFound: "No editable text block was found here. Scanned image text requires OCR."
        case .font: "A suitable system font could not be loaded."
        case .content: "This text block could not be changed safely. The original is intact."
        case .save: "Could not serialize the modified PDF."
        case .alreadyUsed: "The text selection has changed. Select the text again."
        case .permission: "The document does not permit content editing."
        case .unsupportedGlyph: "The selected font cannot represent all entered characters. The original text has been kept."
        }
    }
    var russian: String {
        switch self {
        case .document: "Не удалось открыть PDF для редактирования содержимого."
        case .page: "Страница PDF недоступна."
        case .textNotFound: "Здесь нет редактируемого текстового блока. Для текста на скане требуется OCR."
        case .font: "Не удалось загрузить подходящий системный шрифт."
        case .content: "Не удалось безопасно изменить текстовый блок. Оригинал сохранён."
        case .save: "Не удалось сохранить изменённое содержимое PDF."
        case .alreadyUsed: "Выделение изменилось. Выберите текст заново."
        case .permission: "Документ не разрешает редактирование содержимого."
        case .unsupportedGlyph: "Выбранный шрифт не поддерживает все введённые символы. Исходный текст сохранён."
        }
    }
}

@MainActor private enum PDFiumRuntime {
    static let ready: Void = { FPDF_InitLibrary() }()
}
private final class PDFiumDocumentHandle {
    let data: NSData
    let originalData: Data
    let document: FPDF_DOCUMENT
    let page: FPDF_PAGE
    var textPage: FPDF_TEXTPAGE?
    var fonts: [FPDF_FONT] = []
    @MainActor init(data: Data, pageIndex: Int) throws {
        _ = PDFiumRuntime.ready
        self.originalData = data
        self.data = try PDFContentNormalizer.prepare(data,pageIndex: pageIndex) as NSData
        guard let document = FPDF_LoadMemDocument64(self.data.bytes, self.data.length, nil) else { throw PDFSourceError.document }
        guard FPDF_GetDocPermissions(document) & (1 << 3) != 0 else { FPDF_CloseDocument(document); throw PDFSourceError.permission }
        guard let page = FPDF_LoadPage(document, Int32(pageIndex)) else { FPDF_CloseDocument(document); throw PDFSourceError.page }
        self.document = document; self.page = page; textPage = FPDFText_LoadPage(page)
    }
    func closeTextPage() { if let textPage { FPDFText_ClosePage(textPage) }; textPage = nil }
    deinit {
        if let textPage { FPDFText_ClosePage(textPage) }
        FPDF_ClosePage(page)
        for font in fonts { FPDFFont_Close(font) }
        FPDF_CloseDocument(document)
    }
}

struct PDFTextGeometry: Equatable {
    var origin: CGPoint
    var xAxis: CGPoint
    var yAxis: CGPoint
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x+xAxis.x*x+yAxis.x*y,y: origin.y+xAxis.y*x+yAxis.y*y)
    }
    func local(_ point: CGPoint) -> CGPoint {
        let determinant = xAxis.x*yAxis.y-xAxis.y*yAxis.x
        guard abs(determinant) > 0.00001 else { return .zero }
        let x = point.x-origin.x, y = point.y-origin.y
        return CGPoint(x: (yAxis.y*x-yAxis.x*y)/determinant,y: (-xAxis.y*x+xAxis.x*y)/determinant)
    }
    var angle: CGFloat { atan2(xAxis.y,xAxis.x) }
    func rotated(by radians: CGFloat, around center: CGPoint) -> Self {
        let cosine = cos(radians), sine = sin(radians)
        func rotate(_ p: CGPoint) -> CGPoint { CGPoint(x: cosine*p.x-sine*p.y,y: sine*p.x+cosine*p.y) }
        let offset = rotate(CGPoint(x: origin.x-center.x,y: origin.y-center.y))
        return Self(origin: CGPoint(x: center.x+offset.x,y: center.y+offset.y),xAxis: rotate(xAxis),yAxis: rotate(yAxis))
    }
}

@MainActor
final class PDFSourceSession {
    struct Snapshot {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let fontName: String
        let color: NSColor
        let width: CGFloat
        let height: CGFloat
        let fragmentCount: Int
        let geometry: PDFTextGeometry
        let leading: CGFloat
        let attributedText: NSAttributedString
    }
    static func documentFonts(data: Data) throws -> [String] { try PDFFontCatalog.names(in: data) }
    struct BlockDescriptor {
        let snapshot: Snapshot
        let point: CGPoint
    }
    private struct Style {
        let url: URL
        let size: CGFloat
        let color: NSColor
        var font: CTFont { CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary), size, nil) }
    }
    private struct BlockInfo { let id: String; let text: String?; let width: CGFloat?; let height: CGFloat? }
    private struct Fragment {
        let object: FPDF_PAGEOBJECT
        let parent: FPDF_PAGEOBJECT?
        let rootIndex: Int
        let matrix: FS_MATRIX
        let bounds: CGRect
        let text: String
        let style: Style
        let block: BlockInfo?
    }
    private struct EmbeddedFont { let handle: FPDF_FONT; let codes: [UInt32: UInt32]; let unicode: Bool }
    private struct Glyph: Codable { let unicode: UInt32; let origin: CGPoint }
    private struct LayoutRecord: Codable {
        let id: String
        let text: String
        let width: CGFloat
        let height: CGFloat?
        let glyphs: [Glyph]
    }
    private struct GlyphKey: Hashable { let unicode: UInt32; let x: Int; let y: Int }
    private struct LayoutIndex {
        let records: [LayoutRecord]
        let points: [String: [GlyphKey: [CGPoint]]]
        let candidates: [GlyphKey: Set<String>]
        static func key(_ glyph: Glyph) -> GlyphKey { GlyphKey(unicode: glyph.unicode,x: Int(floor(glyph.origin.x*4)),y: Int(floor(glyph.origin.y*4))) }
        static func matches(_ glyph: Glyph,in table: [GlyphKey:[CGPoint]]) -> Bool {
            let key = key(glyph)
            for x in (key.x-1)...(key.x+1) {
                for y in (key.y-1)...(key.y+1) {
                    if table[GlyphKey(unicode: key.unicode,x: x,y: y)]?.contains(where: { hypot($0.x-glyph.origin.x,$0.y-glyph.origin.y) < 0.2 }) == true { return true }
                }
            }
            return false
        }
        init(records: [LayoutRecord], readings: [UInt:[Glyph]]) {
            var live: [GlyphKey:[CGPoint]] = [:]
            for glyph in readings.values.joined() { live[Self.key(glyph),default: []].append(glyph.origin) }
            var accepted: [LayoutRecord] = [], points: [String:[GlyphKey:[CGPoint]]] = [:], candidates: [GlyphKey:Set<String>] = [:]
            for record in records where !record.glyphs.isEmpty && record.width.isFinite && record.width >= 10 && record.width <= 20000 {
                guard record.glyphs.count <= 2_000_000, record.glyphs.allSatisfy({ $0.origin.x.isFinite && $0.origin.y.isFinite && abs($0.origin.x) <= 1_000_000_000 && abs($0.origin.y) <= 1_000_000_000 && Self.matches($0,in: live) }) else { continue }
                accepted.append(record)
                for glyph in record.glyphs {
                    let key = Self.key(glyph)
                    points[record.id,default: [:]][key,default: []].append(glyph.origin)
                    candidates[key,default: []].insert(record.id)
                }
            }
            self.records = accepted; self.points = points; self.candidates = candidates
        }
        func block(for glyphs: [Glyph]) -> BlockInfo? {
            let visible = glyphs.filter { $0.unicode > 32 && UnicodeScalar($0.unicode).map({ !Character(String($0)).isWhitespace }) == true }
            guard let first = visible.first else { return nil }
            let key = Self.key(first); var ids = Set<String>()
            for x in (key.x-1)...(key.x+1) {
                for y in (key.y-1)...(key.y+1) { ids.formUnion(candidates[GlyphKey(unicode: key.unicode,x: x,y: y)] ?? []) }
            }
            for id in ids {
                guard let table = points[id], visible.allSatisfy({ Self.matches($0,in: table) }), let record = records.first(where: { $0.id == id }) else { continue }
                return BlockInfo(id: id,text: record.text,width: record.width,height: record.height)
            }
            return nil
        }
    }
    private static let layoutPrefix = "BotPlus source text blocks v1:"
    static func isLayoutMetadata(_ contents: String) -> Bool { contents.hasPrefix(layoutPrefix) }
    private struct Positioned {
        let fragment: Fragment
        let box: CGRect
        let baseline: CGPoint
    }
    private struct Line {
        var runs: [Positioned]
        var baseline: CGFloat { runs.map { $0.baseline.y }.reduce(0,+) / CGFloat(runs.count) }
        var box: CGRect { runs.reduce(CGRect.null) { $0.union($1.box) } }
        var size: CGFloat { runs.map { $0.fragment.style.size }.max() ?? 12 }
    }
    let snapshot: Snapshot
    private let handle: PDFiumDocumentHandle
    private let fragments: [Fragment]
    private let matrix: FS_MATRIX
    private let styles: [Style] // One style per Swift Character in snapshot.text.
    private let leading: CGFloat
    private let selectionPoint: CGPoint
    private var used = false
    private(set) var resultingBounds: CGRect?
    private(set) var resultingPoint: CGPoint?
    private static let identity = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 0,f: 0)

    @MainActor static func editing(data: Data, pageIndex: Int, point: CGPoint) throws -> PDFSourceSession {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let all = collectPage(handle)
        guard let seed = all.reversed().first(where: { $0.bounds.insetBy(dx: -3,dy: -3).contains(point) }) else { throw PDFSourceError.textNotFound }
        return try makeSession(handle: handle,all: all,seed: seed,point: point)
    }
    static func blocks(data: Data,pageIndex: Int) throws -> [BlockDescriptor] {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let all = collectPage(handle)
        var consumed = Set<UInt>(), result: [BlockDescriptor] = []
        var groups: [String:[Fragment]] = [:]
        for fragment in all {
            let matrix = fragment.matrix
            let orientation = [matrix.a,matrix.b,matrix.c,matrix.d].map { String(Int(($0*50).rounded())) }.joined(separator: ":")
            let parent = fragment.parent.map { String(UInt(bitPattern: $0)) } ?? "page"
            let size = fragment.block.map { "block:"+$0.id } ?? "size:"+String(Int((fragment.style.size*2).rounded()))
            groups[parent+":"+orientation+":"+size,default: []].append(fragment)
        }
        for group in groups.values {
            guard let first = group.first else { continue }
            let basis = first.matrix, lines = buildLines(all: group,seed: first,basis: basis)
            for seed in group where !consumed.contains(UInt(bitPattern: seed.object)) {
                let point = CGPoint(x: seed.bounds.midX,y: seed.bounds.midY)
                guard let session = try? makeSession(handle: handle,all: group,seed: seed,point: point,reference: basis,cachedLines: lines) else { continue }
                for fragment in session.fragments { consumed.insert(UInt(bitPattern: fragment.object)) }
                result.append(BlockDescriptor(snapshot: session.snapshot,point: point))
            }
        }
        return result
    }
    private static func collectPage(_ handle: PDFiumDocumentHandle) -> [Fragment] {
        guard let textPage = handle.textPage else { return [] }
        let readings = indexedText(textPage)
        let layoutIndex = LayoutIndex(records: readLayouts(handle.page),readings: readings)
        var all: [Fragment] = []
        for index in 0..<max(0,Int(FPDFPage_CountObjects(handle.page))) {
            if let object = FPDFPage_GetObject(handle.page,Int32(index)) {
                collect(object,parent: nil,parentMatrix: identity,rootIndex: index,depth: 0,textPage: textPage,readings: readings,layouts: layoutIndex,into: &all)
            }
        }
        return all
    }
    private static func buildLines(all: [Fragment],seed: Fragment,basis: FS_MATRIX) -> [Line] {
        guard let inverse = inverse(basis) else { return [] }
        let positioned: [Positioned] = all.compactMap { fragment in
            // Separate transformed objects and form instances; never sweep a whole page.
            guard fragment.parent == seed.parent,
                  abs(fragment.matrix.a-basis.a) < 0.02, abs(fragment.matrix.b-basis.b) < 0.02,
                  abs(fragment.matrix.c-basis.c) < 0.02, abs(fragment.matrix.d-basis.d) < 0.02,
                  (seed.block == nil ? (fragment.block == nil && fragment.style.size >= seed.style.size*0.6 && fragment.style.size <= seed.style.size*1.6) : fragment.block?.id == seed.block?.id) else { return nil }
            return Positioned(fragment: fragment,box: transformed(fragment.bounds,by: inverse),baseline: transform(CGPoint(x: CGFloat(fragment.matrix.e),y: CGFloat(fragment.matrix.f)),by: inverse))
        }
        // PDF producers may emit one object per word or per glyph. Cluster by
        // baseline, then split at large gaps so columns/table cells stay separate.
        var rows: [[Positioned]] = []
        for run in positioned.sorted(by: { $0.baseline.y > $1.baseline.y }) {
            if let index = rows.firstIndex(where: { abs($0[0].baseline.y-run.baseline.y) <= min($0[0].fragment.style.size,run.fragment.style.size)*0.28 }) { rows[index].append(run) }
            else { rows.append([run]) }
        }
        var lines: [Line] = []
        for row in rows {
            var current: [Positioned] = []
            for run in row.sorted(by: { $0.baseline.x < $1.baseline.x }) {
                if let previous = current.last, run.box.minX-previous.box.maxX > max(previous.fragment.style.size,run.fragment.style.size)*1.0 {
                    lines.append(Line(runs: current)); current = []
                }
                current.append(run)
            }
            if !current.isEmpty { lines.append(Line(runs: current)) }
        }
        return lines
    }
    private static func makeSession(handle: PDFiumDocumentHandle,all: [Fragment],seed: Fragment,point: CGPoint,reference: FS_MATRIX? = nil,cachedLines: [Line]? = nil) throws -> PDFSourceSession {
        let basis = reference ?? seed.matrix
        let lines = cachedLines ?? buildLines(all: all,seed: seed,basis: basis)
        guard let selected = lines.firstIndex(where: { $0.runs.contains { $0.fragment.object == seed.object } }) else { throw PDFSourceError.textNotFound }
        var chosen = seed.block == nil ? Set([selected]) : Set(lines.indices)
        func adjacent(_ a: Line, _ b: Line) -> Bool {
            let gap = abs(a.baseline-b.baseline), size = max(a.size,b.size)
            guard abs(a.size-b.size) <= size*0.12 else { return false }
            let lower = a.baseline < b.baseline ? a : b
            let lowerText = lower.runs.map { $0.fragment.text }.joined().trimmingCharacters(in: .whitespaces)
            if lowerText.range(of: #"^([•\-–—]|\d+[\).])"#,options: .regularExpression) != nil { return false }
            let aligned = abs(a.box.minX-b.box.minX) <= size*0.75
            let overlap = min(a.box.maxX,b.box.maxX)-max(a.box.minX,b.box.minX)
            return gap >= size*0.75 && gap <= size*1.65 && aligned && overlap >= min(a.box.width,b.box.width)*0.6
        }
        // Walk only nearest aligned lines above/below, not every nearby object.
        var changed = true
        while changed && seed.block == nil {
            changed = false
            for index in Array(chosen) {
                for direction: CGFloat in [-1,1] {
                    let candidate = lines.indices.filter { !chosen.contains($0) && (lines[$0].baseline-lines[index].baseline)*direction > 0 && adjacent(lines[index],lines[$0]) }
                        .min { abs(lines[$0].baseline-lines[index].baseline) < abs(lines[$1].baseline-lines[index].baseline) }
                    if let candidate { chosen.insert(candidate); changed = true }
                }
            }
        }
        let block = chosen.map { lines[$0] }.sorted { $0.baseline > $1.baseline }
        var text = "", styles: [Style] = [], selectedFragments: [Fragment] = []
        for (lineIndex,line) in block.enumerated() {
            if lineIndex > 0 { text += " "; styles.append(line.runs[0].fragment.style) }
            var previous: Positioned?
            var visualRuns: [Positioned] = []
            for run in line.runs {
                selectedFragments.append(run.fragment)
                if visualRuns.contains(where: {
                    $0.fragment.text == run.fragment.text && $0.fragment.style.color.isEqual(run.fragment.style.color) &&
                    abs($0.fragment.style.size-run.fragment.style.size) < 0.01 &&
                    hypot($0.baseline.x-run.baseline.x,$0.baseline.y-run.baseline.y) < 0.05
                }) { continue }
                visualRuns.append(run)
                if let previous, !text.hasSuffix(" "), !run.fragment.text.hasPrefix(" "),
                   !",.;:!?)]}".contains(run.fragment.text.first ?? " "),
                   !"([{“".contains(text.last ?? " "),
                   run.box.minX-previous.box.maxX > min(previous.fragment.style.size,run.fragment.style.size)*0.18 {
                    text += " "; styles.append(run.fragment.style)
                }
                text += run.fragment.text
                styles.append(contentsOf: Array(repeating: run.fragment.style,count: run.fragment.text.count))
                previous = run
            }
        }
        let localBox = block.reduce(CGRect.null) { $0.union($1.box) }
        var placement = basis
        let startX = block[0].runs.map { $0.baseline.x }.min() ?? localBox.minX
        let start = transform(CGPoint(x: startX,y: block[0].baseline),by: basis)
        placement.e = Float(start.x); placement.f = Float(start.y)
        let bounds = selectedFragments.reduce(CGRect.null) { $0.union($1.bounds) }
        let gaps = zip(block,block.dropFirst()).map { $0.baseline-$1.baseline }.sorted()
        let leading = gaps.isEmpty ? seed.style.size*1.2 : gaps[gaps.count/2]
        if let logical = seed.block?.text,
           logical.filter({ !$0.isWhitespace }) == text.filter({ !$0.isWhitespace }) {
            styles = remapStyles(from: text,styles: styles,to: logical); text = logical
        }
        if styles.isEmpty { styles = [seed.style] }
        let width = seed.block?.width ?? max(20,localBox.maxX-startX+1)
        let fieldHeight = max(seed.style.size*1.3,seed.block?.height ?? localBox.height)
        let container = transformed(CGRect(x: startX,y: block[0].baseline+seed.style.size*0.85-fieldHeight,width: width,height: fieldHeight),by: basis).union(bounds)
        let snapshot = Snapshot(text: text,bounds: container,fontSize: seed.style.size,fontName: seed.style.url.deletingPathExtension().lastPathComponent,color: seed.style.color,width: width,height: fieldHeight,fragmentCount: selectedFragments.count,geometry: geometry(placement),leading: leading,attributedText: attributed(text,styles: styles,leading: leading))
        return PDFSourceSession(handle: handle,fragments: selectedFragments,matrix: placement,styles: styles,leading: leading,selectionPoint: point,snapshot: snapshot)
    }
    @MainActor static func adding(data: Data, pageIndex: Int, point: CGPoint, fontSize: CGFloat, color: NSColor, fontName: String = "Arial") throws -> PDFSourceSession {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let url = try systemFontURL(fontName)
        let matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: Float(point.x),f: Float(point.y))
        let snapshot = Snapshot(text: "",bounds: CGRect(x: point.x,y: point.y,width: 240,height: max(20,fontSize*1.2)),fontSize: fontSize,fontName: url.deletingPathExtension().lastPathComponent,color: color,width: 240,height: fontSize*1.3,fragmentCount: 0,geometry: geometry(matrix),leading: fontSize*1.2,attributedText: NSAttributedString(string: ""))
        return PDFSourceSession(handle: handle,fragments: [],matrix: matrix,styles: [Style(url: url,size: fontSize,color: color)],leading: fontSize*1.2,selectionPoint: point,snapshot: snapshot)
    }
    private init(handle: PDFiumDocumentHandle, fragments: [Fragment], matrix: FS_MATRIX, styles: [Style], leading: CGFloat, selectionPoint: CGPoint, snapshot: Snapshot) {
        self.handle = handle; self.fragments = fragments; self.matrix = matrix; self.styles = styles; self.leading = leading; self.selectionPoint = selectionPoint; self.snapshot = snapshot
    }

    private static func geometry(_ matrix: FS_MATRIX) -> PDFTextGeometry {
        PDFTextGeometry(origin: CGPoint(x: CGFloat(matrix.e),y: CGFloat(matrix.f)),xAxis: CGPoint(x: CGFloat(matrix.a),y: CGFloat(matrix.b)),yAxis: CGPoint(x: CGFloat(matrix.c),y: CGFloat(matrix.d)))
    }
    private static func attributed(_ text: String,styles: [Style],leading: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        var offset = 0
        for (character,style) in zip(text,styles) {
            let name = CTFontCopyPostScriptName(style.font) as String
            let font = NSFont(name: name,size: style.size) ?? NSFont.systemFont(ofSize: style.size)
            let length = String(character).utf16.count
            result.addAttributes([.font: font,.foregroundColor: style.color],range: NSRange(location: offset,length: length)); offset += length
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = leading
        result.addAttribute(.paragraphStyle,value: paragraph,range: NSRange(location: 0,length: result.length))
        return result
    }
    private func styles(from attributed: NSAttributedString, text: String) throws -> [Style] {
        guard attributed.string == text else { throw PDFSourceError.content }
        var result: [Style] = [], offset = 0
        for character in text {
            let attributes = attributed.attributes(at: offset,effectiveRange: nil)
            let font = attributes[.font] as? NSFont ?? NSFont(name: snapshot.fontName,size: snapshot.fontSize) ?? NSFont.systemFont(ofSize: snapshot.fontSize)
            let color = attributes[.foregroundColor] as? NSColor ?? snapshot.color
            result.append(Style(url: try Self.systemFontURL(font.fontName),size: min(2000,max(1,font.pointSize)),color: color))
            offset += String(character).utf16.count
        }
        return result
    }

    func previewWithoutSelectedText() throws -> Data {
        handle.closeTextPage()
        for fragment in fragments {
            guard FPDFPageObj_SetIsActive(fragment.object,0) != 0 else { throw PDFSourceError.content }
        }
        // PDFium may serialize /Contents [] after hiding the last page object.
        // PDFKit diagnoses that empty stream array. A transparent path keeps
        // the preview content stream valid without painting a text-field mask.
        guard let spacer = FPDFPageObj_CreateNewRect(0,0,0.01,0.01) else { throw PDFSourceError.content }
        _ = FPDFPageObj_SetFillColor(spacer,0,0,0,0)
        _ = FPDFPath_SetDrawMode(spacer,FPDF_FILLMODE_WINDING,0)
        FPDFPage_InsertObject(handle.page,spacer)
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length),length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        return Data(bytes: bytes,count: length)
    }
    struct ContentObject {
        let kind: String
        let bounds: CGRect
        let pixelSize: CGSize?
    }
    static func objectInfo(data: Data,pageIndex: Int,point: CGPoint) throws -> ContentObject? {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        @MainActor func find(_ object: FPDF_PAGEOBJECT,transform parent: FS_MATRIX,depth: Int) -> ContentObject? {
            guard depth < 32 else { return nil }
            let type = FPDFPageObj_GetType(object)
            if type == FPDF_PAGEOBJ_FORM {
                var local = identity; guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return nil }
                let transform = multiply(parent,local)
                for i in (0..<max(0,Int(FPDFFormObj_CountObjects(object)))).reversed() {
                    if let child = FPDFFormObj_GetObject(object,UInt(i)),let found = find(child,transform: transform,depth: depth+1) { return found }
                }
                return nil
            }
            guard type == FPDF_PAGEOBJ_IMAGE || type == FPDF_PAGEOBJ_PATH,let bounds = bounds(object) else { return nil }
            let world = transformed(bounds,by: parent)
            guard !world.isEmpty,world.insetBy(dx: -2,dy: -2).contains(point) else { return nil }
            if type == FPDF_PAGEOBJ_IMAGE {
                var width: UInt32 = 0,height: UInt32 = 0
                _ = FPDFImageObj_GetImagePixelSize(object,&width,&height)
                return ContentObject(kind: "image",bounds: world,pixelSize: CGSize(width: Int(width),height: Int(height)))
            }
            // A large rectangle enclosing a page is not a selectable object on
            // every empty click. Paths require a click close to their edges.
            let nearEdge = min(abs(point.x-world.minX),abs(point.x-world.maxX),abs(point.y-world.minY),abs(point.y-world.maxY)) < 3
            return nearEdge ? ContentObject(kind: "path",bounds: world,pixelSize: nil) : nil
        }
        for i in (0..<max(0,Int(FPDFPage_CountObjects(handle.page)))).reversed() {
            if let object = FPDFPage_GetObject(handle.page,Int32(i)),let found = find(object,transform: identity,depth: 0) { return found }
        }
        return nil
    }

    /// Preserve styles on unchanged characters. Insertions inherit their neighbor;
    /// explicit size/color controls apply to the entire selected block.
    private func editedStyles(_ text: String, size: CGFloat, color: NSColor) -> [Style] {
        let result = Self.remapStyles(from: snapshot.text,styles: styles,to: text)
        return result.map { Style(url: $0.url,size: abs(size-snapshot.fontSize) < 0.01 ? $0.size : size,color: color.isEqual(snapshot.color) ? $0.color : color) }
    }

    private static func remapStyles(from originalText: String, styles originalStyles: [Style], to text: String) -> [Style] {
        let old = Array(originalText), new = Array(text)
        var result = Array(originalStyles.prefix(old.count))
        let fallback = originalStyles.first!
        let difference = new.difference(from: old)
        let removed = difference.removals.compactMap { change -> Int? in
            if case let .remove(offset,_,_) = change { return offset }; return nil
        }.sorted(by: >)
        for offset in removed { result.remove(at: offset) }
        let inserted = difference.insertions.compactMap { change -> Int? in
            if case let .insert(offset,_,_) = change { return offset }; return nil
        }.sorted()
        for offset in inserted {
            let inherited = result.isEmpty ? fallback : result[min(max(0,offset-1),result.count-1)]
            result.insert(inherited,at: offset)
        }
        return result
    }

    @MainActor func applying(text: String, fontSize: CGFloat, color: NSColor, width: CGFloat? = nil, height: CGFloat? = nil, richText: NSAttributedString? = nil, geometry: PDFTextGeometry? = nil) throws -> Data {
        guard !used else { throw PDFSourceError.alreadyUsed }; used = true
        guard !text.contains("\0"), fontSize.isFinite, fontSize > 0 else { throw PDFSourceError.content }
        let normalized = text.replacingOccurrences(of: "\r\n",with: "\n").replacingOccurrences(of: "\r",with: "\n")
        let blockWidth = width ?? snapshot.width
        let blockHeight = height ?? snapshot.height
        guard blockWidth.isFinite, blockWidth >= 10, blockWidth <= 20_000, blockHeight.isFinite, blockHeight >= 1, blockHeight <= 20_000 else { throw PDFSourceError.content }
        if richText == nil && geometry == nil && normalized == snapshot.text && abs(fontSize-snapshot.fontSize) < 0.01 && color.isEqual(snapshot.color) && abs(blockWidth-snapshot.width) < 0.01 && abs(blockHeight-snapshot.height) < 0.01 {
            resultingBounds = snapshot.bounds; resultingPoint = selectionPoint; return handle.originalData
        }
        let characterStyles = try richText.map { try styles(from: $0,text: normalized) } ?? editedStyles(normalized,size: fontSize,color: color)
        let pose = geometry ?? snapshot.geometry
        guard [pose.origin.x,pose.origin.y,pose.xAxis.x,pose.xAxis.y,pose.yAxis.x,pose.yAxis.y].allSatisfy({ $0.isFinite }), abs(pose.xAxis.x*pose.yAxis.y-pose.xAxis.y*pose.yAxis.x) > 0.00001 else { throw PDFSourceError.content }
        let placementMatrix = FS_MATRIX(a: Float(pose.xAxis.x),b: Float(pose.xAxis.y),c: Float(pose.yAxis.x),d: Float(pose.yAxis.y),e: Float(pose.origin.x),f: Float(pose.origin.y))
        let attributed = NSMutableAttributedString(string: normalized)
        var offset = 0
        for (character,style) in zip(normalized,characterStyles) {
            let units = Array(String(character).utf16)
            if !character.isWhitespace {
                var glyphs = [CGGlyph](repeating: 0,count: units.count)
                guard CTFontGetGlyphsForCharacters(style.font,units,&glyphs,units.count) else { throw PDFSourceError.unsupportedGlyph }
            }
            attributed.addAttributes([NSAttributedString.Key(kCTFontAttributeName as String): style.font,NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,NSAttributedString.Key(kCTLigatureAttributeName as String): 0],range: NSRange(location: offset,length: units.count))
            offset += units.count
        }
        let originalReadings = handle.textPage.map(Self.indexedText) ?? [:]
        var layoutRecords = LayoutIndex(records: Self.readLayouts(handle.page),readings: originalReadings).records
        let replacedIDs = Set(fragments.compactMap { $0.block?.id })
        layoutRecords.removeAll { replacedIDs.contains($0.id) }
        handle.closeTextPage()
        var loadedFonts: [URL: EmbeddedFont] = [:]
        @MainActor func load(_ url: URL) throws -> EmbeddedFont {
            if let existing = loadedFonts[url] { return existing }
            let data = try Data(contentsOf: url)
            guard data.count <= Int(UInt32.max) else { throw PDFSourceError.font }
            if data.starts(with: [0x4f,0x54,0x54,0x4f]) {
                let loaded = data.withUnsafeBytes { FPDFText_LoadFont(handle.document,$0.bindMemory(to: UInt8.self).baseAddress,UInt32(data.count),FPDF_FONT_TYPE1,1) }
                guard let loaded else { throw PDFSourceError.font }
                let embedded = EmbeddedFont(handle: loaded,codes: [:],unicode: true)
                loadedFonts[url] = embedded; handle.fonts.append(loaded); return embedded
            }
            let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary),12,nil)
            // Keep CID == glyph ID for PDFKit's save path on macOS 14/15.
            // The explicit ToUnicode map still prevents automatic cmap aliases
            // from turning '-' into soft hyphen or ';' into Greek question mark.
            let scalars = Array(Set(zip(normalized,characterStyles).filter { $0.1.url == url }.flatMap { String($0.0).unicodeScalars.filter { $0 != "\n" }.map(\.value) })).sorted()
            guard scalars.count < 65_535 else { throw PDFSourceError.content }
            var glyphMap: [UInt8] = [0,0], codes: [UInt32: UInt32] = [:], mappings: [String] = []
            var unicodeForGlyph: [CGGlyph: UInt32] = [:]
            for scalar in scalars {
                let unicode = UnicodeScalar(scalar)!
                let units = Array(String(unicode).utf16)
                var glyphs = [CGGlyph](repeating: 0,count: units.count)
                let supported = CTFontGetGlyphsForCharacters(font,units,&glyphs,units.count)
                guard supported || Character(String(unicode)).isWhitespace else { throw PDFSourceError.unsupportedGlyph }
                let glyph = glyphs[0], cid = UInt32(glyph)
                if let previous = unicodeForGlyph[glyph], previous != scalar {
                    guard Character(String(UnicodeScalar(previous)!)).isWhitespace && Character(String(unicode)).isWhitespace else { throw PDFSourceError.unsupportedGlyph }
                    codes[scalar] = cid; continue
                }
                unicodeForGlyph[glyph] = scalar
                codes[scalar] = cid
                while glyphMap.count < (Int(glyph)+1)*2 { glyphMap.append(0) }
                glyphMap[Int(glyph)*2] = UInt8(glyph >> 8); glyphMap[Int(glyph)*2+1] = UInt8(glyph & 255)
                mappings.append(String(format: "<%04X> <%@>",cid,units.map { String(format: "%04X",$0) }.joined()))
            }
            var cmap = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def\n/CMapName /BotPlusUnicode def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
            for start in stride(from: 0,to: mappings.count,by: 100) {
                let chunk = mappings[start..<min(start+100,mappings.count)]
                cmap += "\(chunk.count) beginbfchar\n"+chunk.joined(separator: "\n")+"\nendbfchar\n"
            }
            cmap += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
            let loaded = data.withUnsafeBytes { bytes in
                cmap.withCString { cmapBytes in
                    glyphMap.withUnsafeBufferPointer { map in
                        FPDFText_LoadCidType2Font(handle.document,bytes.bindMemory(to: UInt8.self).baseAddress,UInt32(data.count),cmapBytes,map.baseAddress,UInt32(glyphMap.count))
                    }
                }
            }
            guard let loaded else { throw PDFSourceError.font }
            let embedded = EmbeddedFont(handle: loaded,codes: codes,unicode: false)
            loadedFonts[url] = embedded; handle.fonts.append(loaded); return embedded
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var objects: [FPDF_PAGEOBJECT] = [], cursor = 0, baseline: CGFloat = 0
        let blockName = "BotPlusTextBlock_"+UUID().uuidString.replacingOccurrences(of: "-",with: "")
        var sharedMark: FPDF_PAGEOBJECTMARK?
        let nsText = normalized as NSString
        do {
            while cursor < attributed.length {
                let count = max(1,CTTypesetterSuggestLineBreak(typesetter,cursor,Double(blockWidth)))
                let line = CTTypesetterCreateLine(typesetter,CFRange(location: cursor,length: count))
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                for run in runs {
                    let range = CTRunGetStringRange(run)
                    let substring = nsText.substring(with: NSRange(location: range.location,length: range.length)).trimmingCharacters(in: .newlines)
                    guard !substring.isEmpty else { continue }
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let ctFont = attributes[kCTFontAttributeName] as! CTFont
                    let postScriptName = CTFontCopyPostScriptName(ctFont) as String
                    let url = try characterStyles.first(where: { CTFontCopyPostScriptName($0.font) as String == postScriptName })?.url ?? Self.systemFontURL(postScriptName)
                    let font = try load(url)
                    guard let object = FPDFPageObj_CreateTextObj(handle.document,font.handle,Float(CTFontGetSize(ctFont))) else { throw PDFSourceError.font }
                    let codes = substring.unicodeScalars.compactMap { font.codes[$0.value] }
                    let success: Bool
                    if font.unicode {
                        let units = Array(substring.utf16)+[0]
                        success = units.withUnsafeBufferPointer { FPDFText_SetText(object,$0.baseAddress) } != 0
                    } else {
                        success = codes.count == substring.unicodeScalars.count && codes.withUnsafeBufferPointer { FPDFText_SetCharcodes(object,$0.baseAddress,$0.count) } != 0
                    }
                    guard success else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    var position = CGPoint.zero
                    CTRunGetPositions(run,CFRange(location: 0,length: 1),&position)
                    if substring.unicodeScalars.count > 1 {
                        var positions: [Float] = [], utf16Index = range.location
                        for (index,scalar) in substring.unicodeScalars.enumerated() {
                            if index > 0 { positions.append(Float(CTLineGetOffsetForStringIndex(line,utf16Index,nil)-position.x)) }
                            utf16Index += scalar.value > 0xFFFF ? 2 : 1
                        }
                        guard positions.withUnsafeBufferPointer({ FPDFText_SetPositions(object,$0.baseAddress,$0.count) }) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    }
                    var placement = placementMatrix
                    placement.e += placementMatrix.a*Float(position.x)+placementMatrix.c*Float(baseline+position.y)
                    placement.f += placementMatrix.b*Float(position.x)+placementMatrix.d*Float(baseline+position.y)
                    guard FPDFPageObj_SetMatrix(object,&placement) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    let cgColor = attributes[kCTForegroundColorAttributeName] as! CGColor
                    let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) ?? .black
                    _ = FPDFPageObj_SetFillColor(object,UInt32((rgb.redComponent*255).rounded()),UInt32((rgb.greenComponent*255).rounded()),UInt32((rgb.blueComponent*255).rounded()),UInt32((rgb.alphaComponent*255).rounded()))
                    if let sharedMark {
                        guard FPDFPageObj_AddExistingMark(object,sharedMark) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    } else {
                        let mark = blockName.withCString { FPDFPageObj_AddMark(object,$0) }
                        guard let mark else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                        let body = Data(normalized.utf8).base64EncodedString()
                        guard body.withCString({ FPDFPageObjMark_SetStringParam(handle.document,object,mark,"Body",$0) }) != 0,
                              FPDFPageObjMark_SetFloatParam(handle.document,object,mark,"Width",Float(blockWidth)) != 0,
                              FPDFPageObjMark_SetFloatParam(handle.document,object,mark,"Height",Float(blockHeight)) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                        sharedMark = mark
                    }
                    objects.append(object)
                }
                var ascent: CGFloat = 0, descent: CGFloat = 0, lineLeading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line,&ascent,&descent,&lineLeading)
                baseline -= max(leading*fontSize/snapshot.fontSize,ascent+descent+lineLeading)
                cursor += count
            }
        } catch { for object in objects { FPDFPageObj_Destroy(object) }; throw error }
        // All replacement glyphs and objects exist before removing anything.
        let firstRoot = fragments.map(\.rootIndex).min() ?? Int(FPDFPage_CountObjects(handle.page))
        let insertion = firstRoot + (fragments.first?.parent == nil ? 0 : 1)
        for fragment in fragments {
            let removed = fragment.parent.map { FPDFFormObj_RemoveObject($0,fragment.object) } ?? FPDFPage_RemoveObject(handle.page,fragment.object)
            guard removed != 0 else { for object in objects { FPDFPageObj_Destroy(object) }; throw PDFSourceError.content }
            FPDFPageObj_Destroy(fragment.object)
        }
        for (index,object) in objects.enumerated() {
            if FPDFPage_InsertObjectAtIndex(handle.page,object,insertion+index) == 0 {
                for remaining in objects[index...] { FPDFPageObj_Destroy(remaining) }; throw PDFSourceError.content
            }
        }
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        var union = CGRect.null
        for object in objects { if let rect = Self.bounds(object) { union = union.union(rect) } }
        let maximumSize = characterStyles.map(\.size).max() ?? fontSize
        let finalHeight = max(blockHeight,maximumSize*1.3,abs(baseline))
        let container = Self.transformed(CGRect(x: 0,y: maximumSize*0.85-finalHeight,width: blockWidth,height: finalHeight),by: placementMatrix)
        resultingBounds = union.isNull ? nil : union.union(container)
        if let first = objects.compactMap({ Self.bounds($0) }).first(where: { !$0.isEmpty }) {
            resultingPoint = CGPoint(x: first.midX,y: first.midY)
        }
        // Validate each generated object's text, not a clipped/partial page selection.
        if let check = FPDFText_LoadPage(handle.page) {
            defer { FPDFText_ClosePage(check) }
            let actual = objects.compactMap { try? Self.text(of: $0,in: check) }.joined()
            let index = Self.indexedText(check)
            let glyphs = objects.flatMap { index[UInt(bitPattern: $0)] ?? [] }.filter { $0.unicode > 32 && UnicodeScalar($0.unicode).map({ !Character(String($0)).isWhitespace }) == true }
            if !glyphs.isEmpty { layoutRecords.append(LayoutRecord(id: blockName,text: normalized,width: blockWidth,height: finalHeight,glyphs: glyphs)) }
            let expected = normalized.filter { !$0.isWhitespace }
            guard actual.filter({ !$0.isWhitespace }) == expected else { throw PDFSourceError.content }
        } else if !objects.isEmpty { throw PDFSourceError.content }
        try Self.writeLayouts(layoutRecords,page: handle.page)
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length), length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        return Data(bytes: bytes,count: length)
    }

    private static func collect(_ object: FPDF_PAGEOBJECT, parent: FPDF_PAGEOBJECT?, parentMatrix: FS_MATRIX, rootIndex: Int, depth: Int, textPage: FPDF_TEXTPAGE, readings: [UInt: [Glyph]]? = nil, layouts: LayoutIndex? = nil, into result: inout [Fragment]) {
        guard depth < 32 else { return }
        if FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_FORM {
            var local = identity
            guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return }
            for index in 0..<max(0,Int(FPDFFormObj_CountObjects(object))) {
                if let child = FPDFFormObj_GetObject(object,UInt(index)) { collect(child,parent: object,parentMatrix: multiply(parentMatrix,local),rootIndex: rootIndex,depth: depth+1,textPage: textPage,readings: readings,layouts: layouts,into: &result) }
            }
            return
        }
        guard FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT else { return }
        let mode = FPDFTextObj_GetTextRenderMode(object)
        // Clipping text also controls other artwork; do not destructively rewrite it.
        guard mode == FPDF_TEXTRENDERMODE_FILL || mode == FPDF_TEXTRENDERMODE_STROKE || mode == FPDF_TEXTRENDERMODE_FILL_STROKE else { return }
        guard let rect = bounds(object), let rawText = try? text(of: object,in: textPage), !rawText.isEmpty else { return }
        let text = readings?[UInt(bitPattern: object)].map(uniqueText) ?? rawText
        guard !text.isEmpty else { return }
        var local = identity
        guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return }
        var effective = multiply(parentMatrix,local)
        let scale = max(0.0001,hypot(effective.c,effective.d))
        var size: Float = 12; _ = FPDFTextObj_GetFontSize(object,&size)
        let physicalSize = CGFloat(size*scale)
        effective.a /= scale; effective.b /= scale; effective.c /= scale; effective.d /= scale
        guard let url = try? systemFontURL(fontName(of: object)) else { return }
        var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 255
        _ = FPDFPageObj_GetFillColor(object,&r,&g,&b,&a)
        let color = NSColor(calibratedRed: CGFloat(r)/255,green: CGFloat(g)/255,blue: CGFloat(b)/255,alpha: CGFloat(a)/255)
        result.append(Fragment(object: object,parent: parent,rootIndex: rootIndex,matrix: effective,bounds: transformed(rect,by: parentMatrix),text: text,style: Style(url: url,size: max(1,physicalSize),color: color),block: blockInfo(object) ?? layouts?.block(for: readings?[UInt(bitPattern: object)] ?? [])))
    }
    private static func annotationContents(_ annotation: FPDF_ANNOTATION) -> String? {
        let length = FPDFAnnot_GetStringValue(annotation,"Contents",nil,0)
        guard length >= 2 && length < 32_000_000 else { return nil }
        var units = [UInt16](repeating: 0,count: Int(length/2))
        _ = units.withUnsafeMutableBufferPointer { FPDFAnnot_GetStringValue(annotation,"Contents",$0.baseAddress,length) }
        return String(decoding: units.prefix { $0 != 0 },as: UTF16.self)
    }
    private static func readLayouts(_ page: FPDF_PAGE) -> [LayoutRecord] {
        for index in 0..<max(0,FPDFPage_GetAnnotCount(page)) {
            guard let annotation = FPDFPage_GetAnnot(page,index) else { continue }
            defer { FPDFPage_CloseAnnot(annotation) }
            guard let contents = annotationContents(annotation), contents.hasPrefix(layoutPrefix),
                  let data = Data(base64Encoded: String(contents.dropFirst(layoutPrefix.count))),
                  let records = try? JSONDecoder().decode([LayoutRecord].self,from: data) else { continue }
            return records
        }
        return []
    }
    private static func writeLayouts(_ records: [LayoutRecord], page: FPDF_PAGE) throws {
        let count = max(0,FPDFPage_GetAnnotCount(page))
        if count > 0 {
            for index in (0..<count).reversed() {
                guard let annotation = FPDFPage_GetAnnot(page,index) else { continue }
                let metadata = annotationContents(annotation).map(isLayoutMetadata) ?? false
                FPDFPage_CloseAnnot(annotation)
                if metadata && FPDFPage_RemoveAnnot(page,index) == 0 { throw PDFSourceError.content }
            }
        }
        guard !records.isEmpty else { return }
        let body = layoutPrefix+(try JSONEncoder().encode(records)).base64EncodedString()
        let units = Array(body.utf16)+[0]
        guard let annotation = FPDFPage_CreateAnnot(page,FPDF_ANNOT_FREETEXT) else { throw PDFSourceError.content }
        defer { FPDFPage_CloseAnnot(annotation) }
        var rect = FS_RECTF(left: 0,top: 1,right: 1,bottom: 0)
        guard units.withUnsafeBufferPointer({ FPDFAnnot_SetStringValue(annotation,"Contents",$0.baseAddress) }) != 0,
              FPDFAnnot_SetFlags(annotation,FPDF_ANNOT_FLAG_HIDDEN | FPDF_ANNOT_FLAG_NOVIEW) != 0,
              FPDFAnnot_SetRect(annotation,&rect) != 0 else { throw PDFSourceError.content }
    }

    private static func blockInfo(_ object: FPDF_PAGEOBJECT) -> BlockInfo? {
        for index in 0..<max(0,FPDFPageObj_CountMarks(object)) {
            guard let mark = FPDFPageObj_GetMark(object,UInt(index)) else { continue }
            var length: UInt = 0
            guard FPDFPageObjMark_GetName(mark,nil,0,&length) != 0, length > 0, length < 4096 else { continue }
            var buffer = [UInt16](repeating: 0,count: Int(length/2))
            _ = buffer.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetName(mark,$0.baseAddress,length,&length) }
            let name = String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
            guard name.hasPrefix("BotPlusTextBlock_") else { continue }
            var body: String?
            if FPDFPageObjMark_GetParamStringValue(mark,"Body",nil,0,&length) != 0, length > 0, length < 12_000_000 {
                buffer = [UInt16](repeating: 0,count: Int(length/2))
                _ = buffer.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetParamStringValue(mark,"Body",$0.baseAddress,length,&length) }
                let encoded = String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
                if let data = Data(base64Encoded: encoded) { body = String(data: data,encoding: .utf8) }
            }
            var width: Float = 0
            let validWidth = FPDFPageObjMark_GetParamFloatValue(mark,"Width",&width) != 0 && width.isFinite && width >= 10 && width <= 20000
            var height: Float = 0
            let validHeight = FPDFPageObjMark_GetParamFloatValue(mark,"Height",&height) != 0 && height.isFinite && height > 0 && height <= 20000
            return BlockInfo(id: name,text: body,width: validWidth ? CGFloat(width) : nil,height: validHeight ? CGFloat(height) : nil)
        }
        return nil
    }
    private static func indexedText(_ page: FPDF_TEXTPAGE) -> [UInt: [Glyph]] {
        var result: [UInt: [Glyph]] = [:]
        for index in 0..<max(0,FPDFText_CountChars(page)) {
            guard let object = FPDFText_GetTextObject(page,index), FPDFText_IsGenerated(page,index) != 1 else { continue }
            let unicode = FPDFText_GetUnicode(page,index)
            var x: Double = 0, y: Double = 0
            guard unicode != 0, FPDFText_GetCharOrigin(page,index,&x,&y) != 0, x.isFinite, y.isFinite, abs(x) <= 1_000_000_000, abs(y) <= 1_000_000_000 else { continue }
            result[UInt(bitPattern: object),default: []].append(Glyph(unicode: unicode,origin: CGPoint(x: x,y: y)))
        }
        return result
    }
    /// CAD exporters often draw an identical string twice at coincident positions
    /// (synthetic weight). Remove repeated drawing passes, not repeated letters.
    private static func uniqueText(_ glyphs: [Glyph]) -> String {
        func same(_ a: Glyph, _ b: Glyph) -> Bool {
            a.unicode == b.unicode && hypot(a.origin.x-b.origin.x,a.origin.y-b.origin.y) < 0.05
        }
        var accepted: [Glyph] = [], index = 0
        while index < glyphs.count {
            var duplicate = 0
            for start in accepted.indices where same(accepted[start],glyphs[index]) {
                let length = accepted.count-start
                if length >= 2, index+length <= glyphs.count,
                   (0..<length).allSatisfy({ same(accepted[start+$0],glyphs[index+$0]) }) {
                    duplicate = length; break
                }
            }
            if duplicate > 0 { index += duplicate }
            else { accepted.append(glyphs[index]); index += 1 }
        }
        return String(String.UnicodeScalarView(accepted.compactMap { UnicodeScalar($0.unicode) }))
    }
    private static func bounds(_ object: FPDF_PAGEOBJECT) -> CGRect? {
        var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
        guard FPDFPageObj_GetBounds(object,&l,&b,&r,&t) != 0 else { return nil }
        return CGRect(x: Double(l),y: Double(b),width: Double(r-l),height: Double(t-b))
    }
    private static func text(of object: FPDF_PAGEOBJECT, in page: FPDF_TEXTPAGE) throws -> String {
        let length = FPDFTextObj_GetText(object,page,nil,0)
        guard length > 0 && length <= 4_194_304 else { throw PDFSourceError.textNotFound }
        var buffer = [UInt16](repeating: 0,count: Int(length/2))
        _ = buffer.withUnsafeMutableBufferPointer { FPDFTextObj_GetText(object,page,$0.baseAddress,length) }
        return String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
    }
    private static func fontName(of object: FPDF_PAGEOBJECT) -> String {
        guard let font = FPDFTextObj_GetFont(object) else { return "Arial" }
        let count = FPDFFont_GetBaseFontName(font,nil,0)
        guard count > 0 && count < 16_384 else { return "Arial" }
        var buffer = [CChar](repeating: 0,count: count)
        _ = buffer.withUnsafeMutableBufferPointer { FPDFFont_GetBaseFontName(font,$0.baseAddress,count) }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },as: UTF8.self)
        return name.split(separator: "+").last.map(String.init) ?? "Arial"
    }
    private static func systemFontURL(_ name: String) throws -> URL {
        if let extracted = try? PDFFontCatalog.url(for: name) { return extracted }
        let font = CTFontCreateWithName(name as CFString,12,nil)
        if let url = CTFontCopyAttribute(font,kCTFontURLAttribute) as? URL, url.pathExtension.lowercased() == "ttf", FileManager.default.isReadableFile(atPath: url.path) { return url }
        let lower = name.lowercased()
        let style = lower.contains("bold") ? (lower.contains("italic") || lower.contains("oblique") ? " Bold Italic" : " Bold") : (lower.contains("italic") || lower.contains("oblique") ? " Italic" : "")
        let family = lower.contains("times") ? "Times New Roman" : (lower.contains("courier") ? "Courier New" : "Arial")
        for candidate in [family+style,"Arial"+style,"Arial"] {
            let url = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/"+candidate+".ttf")
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        throw PDFSourceError.font
    }
    private static func multiply(_ p: FS_MATRIX, _ q: FS_MATRIX) -> FS_MATRIX {
        FS_MATRIX(a: p.a*q.a+p.c*q.b,b: p.b*q.a+p.d*q.b,c: p.a*q.c+p.c*q.d,d: p.b*q.c+p.d*q.d,e: p.a*q.e+p.c*q.f+p.e,f: p.b*q.e+p.d*q.f+p.f)
    }
    private static func inverse(_ m: FS_MATRIX) -> FS_MATRIX? {
        let determinant = m.a*m.d-m.b*m.c
        guard abs(determinant) > 0.00001 else { return nil }
        return FS_MATRIX(a: m.d/determinant,b: -m.b/determinant,c: -m.c/determinant,d: m.a/determinant,e: (m.c*m.f-m.d*m.e)/determinant,f: (m.b*m.e-m.a*m.f)/determinant)
    }
    private static func transform(_ point: CGPoint, by m: FS_MATRIX) -> CGPoint {
        CGPoint(x: CGFloat(m.a)*point.x+CGFloat(m.c)*point.y+CGFloat(m.e),y: CGFloat(m.b)*point.x+CGFloat(m.d)*point.y+CGFloat(m.f))
    }
    private static func transformed(_ rect: CGRect, by matrix: FS_MATRIX) -> CGRect {
        [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),CGPoint(x: rect.minX,y: rect.maxY),CGPoint(x: rect.maxX,y: rect.maxY)]
            .map { transform($0,by: matrix) }.reduce(CGRect.null) { $0.union(CGRect(origin: $1,size: .zero)) }
    }
}

/// CAD producers may split one BT/ET text scope across several /Contents
/// streams. Regenerating just one such stream breaks the text state of the
/// others. Coalesce the selected page before PDFium marks any stream dirty.
@MainActor
private enum PDFContentNormalizer {
    static func prepare(_ input: Data, pageIndex: Int) throws -> Data {
        guard let provider = CGDataProvider(data: input as CFData), let cgDocument = CGPDFDocument(provider),
              let page = cgDocument.page(at: pageIndex+1), let dictionary = page.dictionary else { return input }
        var contents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary,"Contents",&contents), let contents,
              CGPDFArrayGetCount(contents) > 1 else { return input }
        var joined = Data()
        for index in 0..<CGPDFArrayGetCount(contents) {
            var stream: CGPDFStreamRef?
            guard CGPDFArrayGetStream(contents,index,&stream), let stream else { throw PDFSourceError.content }
            var format = CGPDFDataFormat.raw
            guard let decoded = CGPDFStreamCopyData(stream,&format), format == .raw else { throw PDFSourceError.content }
            joined.append(decoded as Data); joined.append(10)
        }
        let memory = input as NSData
        guard let document = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document) }
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(document,&length), length > 0 else { throw PDFSourceError.save }
        let normalized = Data(bytes: bytes,count: length); BotPlusPDFium_Free(bytes)
        var syntax = Syntax(bytes: Array(normalized))
        let start = try syntax.lastXref()
        let objects = try syntax.objectOffsets(xref: start)
        let trailer = try syntax.trailer(xref: start)
        guard trailer["Encrypt"] == nil else { throw PDFSourceError.permission }
        guard let rootValue = trailer["Root"], let root = syntax.reference(rootValue),
              let rootOffset = objects[root.0] else { throw PDFSourceError.content }
        let catalog = try syntax.objectDictionary(at: rootOffset)
        guard let pagesValue = catalog.values["Pages"], let pagesRoot = syntax.reference(pagesValue) else { throw PDFSourceError.content }
        var pageObjects: [(Int,Int)] = [], visited = Set<Int>()
        func visit(_ reference: (Int,Int), depth: Int) throws {
            guard depth < 128, visited.insert(reference.0).inserted, let offset = objects[reference.0] else { throw PDFSourceError.content }
            let object = try syntax.objectDictionary(at: offset)
            if let type = object.values["Type"], syntax.string(type) == "/Page" { pageObjects.append(reference); return }
            guard let kids = object.values["Kids"] else { throw PDFSourceError.content }
            for child in syntax.references(kids) { try visit(child,depth: depth+1) }
        }
        try visit(pagesRoot,depth: 0)
        guard pageObjects.indices.contains(pageIndex) else { throw PDFSourceError.page }
        let pageReference = pageObjects[pageIndex]
        guard let offset = objects[pageReference.0] else { throw PDFSourceError.content }
        let pageObject = try syntax.objectDictionary(at: offset)
        guard let oldContents = pageObject.values["Contents"], let sizeValue = trailer["Size"],
              let size = Int(syntax.string(sizeValue)) else { throw PDFSourceError.content }
        let streamID = max(size,(objects.keys.max() ?? 0)+1)
        var output = normalized
        output.append(Data("\n".utf8))
        let pageOffset = output.count
        output.append(Data("\(pageReference.0) \(pageReference.1) obj\n".utf8))
        output.append(contentsOf: syntax.bytes[pageObject.range.lowerBound..<oldContents.lowerBound])
        output.append(Data(" \(streamID) 0 R ".utf8))
        output.append(contentsOf: syntax.bytes[oldContents.upperBound..<pageObject.range.upperBound])
        output.append(Data("\nendobj\n".utf8))
        let streamOffset = output.count
        output.append(Data("\(streamID) 0 obj\n<< /Length \(joined.count) >>\nstream\n".utf8)); output.append(joined)
        output.append(Data("\nendstream\nendobj\n".utf8))
        let xrefOffset = output.count
        var xref = "xref\n\(pageReference.0) 1\n"+String(format: "%010lld %05d n \n",Int64(pageOffset),pageReference.1)
        xref += "\(streamID) 1\n"+String(format: "%010lld 00000 n \n",Int64(streamOffset))
        xref += "trailer\n<< /Size \(streamID+1) /Root \(root.0) \(root.1) R /Prev \(start)"
        output.append(Data(xref.utf8))
        for key in ["Info","ID"] {
            if let value = trailer[key] {
                output.append(Data(" /\(key) ".utf8)); output.append(contentsOf: syntax.bytes[value])
            }
        }
        output.append(Data(" >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return output
    }

    /// This reader handles the conventional xref/dictionaries emitted by
    /// FPDF_SaveAsCopy, including nested dictionaries, strings and references.
    /// It never scans binary stream data looking for object-like byte patterns.
    private struct Syntax {
        let bytes: [UInt8]
        var cursor = 0
        func string(_ range: Range<Int>) -> String { String(decoding: bytes[range],as: UTF8.self) }
        mutating func whitespace() {
            while cursor < bytes.count {
                if [0,9,10,12,13,32].contains(bytes[cursor]) { cursor += 1 }
                else if bytes[cursor] == 37 { while cursor < bytes.count && bytes[cursor] != 10 && bytes[cursor] != 13 { cursor += 1 } }
                else { break }
            }
        }
        mutating func token() -> String {
            whitespace(); let start = cursor
            while cursor < bytes.count && ![0,9,10,12,13,32,40,41,60,62,91,93,123,125,47,37].contains(bytes[cursor]) { cursor += 1 }
            return string(start..<cursor)
        }
        mutating func value(depth: Int = 0) throws -> Range<Int> {
            guard depth < 128 else { throw PDFSourceError.content }
            whitespace(); let start = cursor
            guard cursor < bytes.count else { throw PDFSourceError.content }
            switch bytes[cursor] {
            case 60:
                if cursor+1 < bytes.count && bytes[cursor+1] == 60 { _ = try dictionary(depth: depth+1) }
                else { cursor += 1; while cursor < bytes.count && bytes[cursor] != 62 { cursor += 1 }; guard cursor < bytes.count else { throw PDFSourceError.content }; cursor += 1 }
            case 40:
                cursor += 1; var depth = 1
                while cursor < bytes.count && depth > 0 {
                    if bytes[cursor] == 92 { cursor += min(2,bytes.count-cursor); continue }
                    if bytes[cursor] == 40 { depth += 1 }; if bytes[cursor] == 41 { depth -= 1 }; cursor += 1
                }
                guard depth == 0 else { throw PDFSourceError.content }
            case 91:
                cursor += 1; whitespace()
                while cursor < bytes.count && bytes[cursor] != 93 { _ = try value(depth: depth+1); whitespace() }
                guard cursor < bytes.count else { throw PDFSourceError.content }; cursor += 1
            case 47:
                cursor += 1; _ = token()
            default:
                let first = token(); guard !first.isEmpty else { throw PDFSourceError.content }
                let end = cursor
                if Int(first) != nil { let second = token(); if Int(second) == nil || token() != "R" { cursor = end } }
            }
            return start..<cursor
        }
        mutating func dictionary(depth: Int = 0) throws -> [String: Range<Int>] {
            guard depth < 128 else { throw PDFSourceError.content }
            whitespace()
            guard cursor+1 < bytes.count && bytes[cursor] == 60 && bytes[cursor+1] == 60 else { throw PDFSourceError.content }
            cursor += 2; var values: [String: Range<Int>] = [:]
            while true {
                whitespace(); guard cursor+1 < bytes.count else { throw PDFSourceError.content }
                if bytes[cursor] == 62 && bytes[cursor+1] == 62 { cursor += 2; return values }
                guard bytes[cursor] == 47 else { throw PDFSourceError.content }; cursor += 1
                let key = token(); values[key] = try value(depth: depth+1)
            }
        }
        mutating func lastXref() throws -> Int {
            // startxref is the final ASCII trailer marker, after all streams.
            let tailStart = max(0,bytes.count-1024), tail = string(tailStart..<bytes.count)
            guard let range = tail.range(of: "startxref",options: .backwards) else { throw PDFSourceError.content }
            let after = tail[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first
            guard let after, let offset = Int(after), offset >= 0 && offset < bytes.count else { throw PDFSourceError.content }; return offset
        }
        mutating func objectOffsets(xref: Int) throws -> [Int:Int] {
            cursor = xref; guard token() == "xref" else { throw PDFSourceError.content }
            var offsets: [Int:Int] = [:]
            while true {
                let first = token(); if first == "trailer" { return offsets }
                guard let start = Int(first), let count = Int(token()), count >= 0 && count <= bytes.count else { throw PDFSourceError.content }
                for index in 0..<count {
                    guard let offset = Int(token()), Int(token()) != nil else { throw PDFSourceError.content }
                    let state = token(); if state == "n" { offsets[start+index] = offset }
                }
            }
        }
        mutating func trailer(xref: Int) throws -> [String:Range<Int>] { _ = try objectOffsets(xref: xref); return try dictionary() }
        mutating func objectDictionary(at offset: Int) throws -> (range: Range<Int>,values: [String:Range<Int>]) {
            guard offset >= 0 && offset < bytes.count else { throw PDFSourceError.content }; cursor = offset
            guard Int(token()) != nil, Int(token()) != nil, token() == "obj" else { throw PDFSourceError.content }
            whitespace(); let start = cursor; let values = try dictionary(); return (start..<cursor,values)
        }
        func reference(_ range: Range<Int>) -> (Int,Int)? {
            let tokens = string(range).split(whereSeparator: { $0.isWhitespace })
            guard tokens.count == 3, tokens[2] == "R", let id = Int(tokens[0]), let generation = Int(tokens[1]) else { return nil }; return (id,generation)
        }
        func references(_ range: Range<Int>) -> [(Int,Int)] {
            let text = string(range)
            let regex = try! NSRegularExpression(pattern: #"(\d+)\s+(\d+)\s+R"#)
            let ns = text as NSString
            return regex.matches(in: text,range: NSRange(location: 0,length: ns.length)).compactMap { match in
                guard let id = Int(ns.substring(with: match.range(at: 1))), let generation = Int(ns.substring(with: match.range(at: 2))) else { return nil }; return (id,generation)
            }
        }
    }
}

/// Process-scoped fonts; extracted programs stay alive while an editor can use them.
/// Unusable PDF subsets are listed but never silently chosen as another font.
@MainActor
enum PDFFontCatalog {
    private static var embedded: [String: URL] = [:]
    private static var programs: [String: URL] = [:]
    private static var directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlusFonts-"+UUID().uuidString,isDirectory: true)
    static func font(named name: String,size: CGFloat) -> NSFont? {
        if let url = embedded[name] {
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor,size,nil)
            guard CTFontCopyTable(font,0x636d6170,CTFontTableOptions(rawValue: 0)) != nil else { return nil }
            return NSFont(name: CTFontCopyPostScriptName(font) as String,size: size)
        }
        if let exact = NSFont(name: name,size: size) { return exact }
        return NSFontManager.shared.font(withFamily: name,traits: [],weight: 5,size: size)
    }
    static func names(in data: Data) throws -> [String] {
        _ = PDFiumRuntime.ready
        let storage = data as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document) }
        var names = Set(NSFontManager.shared.availableFontFamilies+NSFontManager.shared.availableFonts)
        var seen = Set<String>()
        @MainActor func scan(_ object: FPDF_PAGEOBJECT,depth: Int) {
            guard depth < 32 else { return }
            if FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_FORM {
                for index in 0..<max(0,FPDFFormObj_CountObjects(object)) {
                    if let child = FPDFFormObj_GetObject(object,UInt(index)) { scan(child,depth: depth+1) }
                }
            }
            guard let font = FPDFTextObj_GetFont(object) else { return }
            let count = FPDFFont_GetBaseFontName(font,nil,0)
            guard count > 1 && count < 16_384 else { return }
            var buffer = [CChar](repeating: 0,count: count)
            _ = buffer.withUnsafeMutableBufferPointer { FPDFFont_GetBaseFontName(font,$0.baseAddress,count) }
            let full = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },as: UTF8.self)
            let name = full.split(separator: "+").last.map(String.init) ?? full
            names.insert(name)
            guard seen.insert(full).inserted,FPDFFont_GetIsEmbedded(font) == 1 else { return }
            var size = 0
            guard FPDFFont_GetFontData(font,nil,0,&size) != 0,size > 0,size < 64_000_000 else { return }
            var bytes = [UInt8](repeating: 0,count: size)
            guard bytes.withUnsafeMutableBufferPointer({ FPDFFont_GetFontData(font,$0.baseAddress,size,&size) }) != 0,
                  let provider = CGDataProvider(data: Data(bytes) as CFData),let graphics = CGFont(provider) else { return }
            // Some CAD subset fonts contain glyphs but no Unicode cmap. They
            // remain visible in the list; glyph validation prevents data loss.
            try? FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString+".otf")
            guard (try? Data(bytes).write(to: url)) != nil else { return }
            var error: Unmanaged<CFError>?
            if NSFont(name: name,size: 12) == nil { embedded[name] = url }
            if let ps = graphics.postScriptName as String? {
                if NSFont(name: ps,size: 12) == nil { embedded[ps] = url }
                names.insert(ps)
            }
            _ = CTFontManagerRegisterGraphicsFont(graphics,&error)
        }
        for index in 0..<max(0,FPDF_GetPageCount(document)) {
            guard let page = FPDF_LoadPage(document,index) else { continue }
            for objectIndex in 0..<max(0,FPDFPage_CountObjects(page)) {
                if let object = FPDFPage_GetObject(page,objectIndex) { scan(object,depth: 0) }
            }
            FPDF_ClosePage(page)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    /// Export a single face from TTC/OTF/system fonts using public CoreText tables.
    static func url(for name: String) throws -> URL {
        if let cached = programs[name] { return cached }
        guard let nsFont = font(named: name,size: 12) else { throw PDFSourceError.font }
        let font = nsFont as CTFont
        guard let rawTags = CTFontCopyAvailableTables(font,CTFontTableOptions(rawValue: 0)),CFArrayGetCount(rawTags) > 0 else { throw PDFSourceError.font }
        // CoreText returns raw integer tags in this CFArray, not NSNumbers.
        let tags = (0..<CFArrayGetCount(rawTags)).map { UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(rawTags,$0))) }
        let tables: [(UInt32,Data)] = tags.compactMap { value in
            guard value != 0x44534947 else { return nil }
            guard let table = CTFontCopyTable(font,value,CTFontTableOptions(rawValue: 0)) else { return nil }
            var data = Data(Array(table as Data))
            if value == 0x68656164,data.count >= 12 { data.replaceSubrange(8..<12,with: [0,0,0,0]) }
            return (value,data)
        }.sorted { $0.0 < $1.0 }
        guard tables.count <= 4095 else { throw PDFSourceError.font }
        let cff = tables.contains { $0.0 == 0x43464620 || $0.0 == 0x43464632 }
        func u16(_ n: Int) -> [UInt8] { [UInt8((n >> 8)&255),UInt8(n&255)] }
        func u32(_ n: UInt32) -> [UInt8] { [UInt8((n >> 24)&255),UInt8((n >> 16)&255),UInt8((n >> 8)&255),UInt8(n&255)] }
        func checksum(_ data: Data) -> UInt32 {
            let b = Array(data); var sum: UInt32 = 0
            for i in stride(from: 0,to: b.count,by: 4) {
                var word: UInt32 = 0
                for j in 0..<4 { word = (word << 8) | (i+j < b.count ? UInt32(b[i+j]) : 0) }
                sum = sum &+ word
            }
            return sum
        }
        var power = 1,selector = 0
        while power*2 <= tables.count { power *= 2; selector += 1 }
        var result = Data(u32(cff ? 0x4f54544f : 0x00010000)+u16(tables.count)+u16(power*16)+u16(selector)+u16(tables.count*16-power*16))
        var payload = Data(),headOffset: Int?
        for (tag,data) in tables {
            let offset = 12+16*tables.count+payload.count
            result.append(contentsOf: u32(tag)+u32(checksum(data))+u32(UInt32(offset))+u32(UInt32(data.count)))
            if tag == 0x68656164 { headOffset = offset }
            payload.append(data)
            while payload.count%4 != 0 { payload.append(0) }
        }
        result.append(payload)
        if let offset = headOffset,offset+12 <= result.count {
            result.replaceSubrange(offset+8..<offset+12,with: u32(0xb1b0afba &- checksum(result)))
        }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString+(cff ? ".otf" : ".ttf"))
        try result.write(to: url); programs[name] = url; programs[nsFont.fontName] = url
        // Keep CoreText family/face lookup consistent with the PDF embedding.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        return url
    }
}
