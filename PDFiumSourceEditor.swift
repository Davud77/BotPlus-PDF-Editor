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

final class PDFSourceSession {
    struct Snapshot {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let fontName: String
        let color: NSColor
        let width: CGFloat
        let fragmentCount: Int
    }
    private struct Style {
        let url: URL
        let size: CGFloat
        let color: NSColor
        var font: CTFont { CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary), size, nil) }
    }
    private struct BlockInfo { let id: String; let text: String?; let width: CGFloat? }
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
    private struct EmbeddedFont { let handle: FPDF_FONT; let codes: [UInt32: UInt32] }
    private struct Glyph { let unicode: UInt32; let origin: CGPoint }
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
        let handle = try PDFiumDocumentHandle(data: data, pageIndex: pageIndex)
        guard let textPage = handle.textPage else { throw PDFSourceError.textNotFound }
        let readings = indexedText(textPage)
        var all: [Fragment] = []
        for index in 0..<max(0,Int(FPDFPage_CountObjects(handle.page))) {
            if let object = FPDFPage_GetObject(handle.page,Int32(index)) {
                collect(object,parent: nil,parentMatrix: identity,rootIndex: index,depth: 0,textPage: textPage,readings: readings,into: &all)
            }
        }
        guard let seed = all.reversed().first(where: { $0.bounds.insetBy(dx: -3,dy: -3).contains(point) }) else { throw PDFSourceError.textNotFound }
        let basis = seed.matrix
        guard let inverse = inverse(basis) else { throw PDFSourceError.content }
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
        let container = transformed(CGRect(x: startX,y: localBox.minY,width: width,height: localBox.height),by: basis).union(bounds)
        let snapshot = Snapshot(text: text,bounds: container,fontSize: seed.style.size,fontName: seed.style.url.deletingPathExtension().lastPathComponent,color: seed.style.color,width: width,fragmentCount: selectedFragments.count)
        return PDFSourceSession(handle: handle,fragments: selectedFragments,matrix: placement,styles: styles,leading: leading,selectionPoint: point,snapshot: snapshot)
    }
    @MainActor static func adding(data: Data, pageIndex: Int, point: CGPoint, fontSize: CGFloat, color: NSColor, fontName: String = "Arial") throws -> PDFSourceSession {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let url = try systemFontURL(fontName)
        let matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: Float(point.x),f: Float(point.y))
        let snapshot = Snapshot(text: "",bounds: CGRect(x: point.x,y: point.y,width: 240,height: max(20,fontSize*1.2)),fontSize: fontSize,fontName: url.deletingPathExtension().lastPathComponent,color: color,width: 240,fragmentCount: 0)
        return PDFSourceSession(handle: handle,fragments: [],matrix: matrix,styles: [Style(url: url,size: fontSize,color: color)],leading: fontSize*1.2,selectionPoint: point,snapshot: snapshot)
    }
    private init(handle: PDFiumDocumentHandle, fragments: [Fragment], matrix: FS_MATRIX, styles: [Style], leading: CGFloat, selectionPoint: CGPoint, snapshot: Snapshot) {
        self.handle = handle; self.fragments = fragments; self.matrix = matrix; self.styles = styles; self.leading = leading; self.selectionPoint = selectionPoint; self.snapshot = snapshot
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

    @MainActor func applying(text: String, fontSize: CGFloat, color: NSColor, width: CGFloat? = nil) throws -> Data {
        guard !used else { throw PDFSourceError.alreadyUsed }; used = true
        guard !text.contains("\0"), fontSize.isFinite, fontSize > 0 else { throw PDFSourceError.content }
        let normalized = text.replacingOccurrences(of: "\r\n",with: "\n").replacingOccurrences(of: "\r",with: "\n")
        let blockWidth = width ?? snapshot.width
        guard blockWidth.isFinite, blockWidth >= 10, blockWidth <= 20_000 else { throw PDFSourceError.content }
        if normalized == snapshot.text && abs(fontSize-snapshot.fontSize) < 0.01 && color.isEqual(snapshot.color) && abs(blockWidth-snapshot.width) < 0.01 {
            resultingBounds = snapshot.bounds; resultingPoint = selectionPoint; return handle.originalData
        }
        let characterStyles = editedStyles(normalized,size: fontSize,color: color)
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
        handle.closeTextPage()
        var loadedFonts: [URL: EmbeddedFont] = [:]
        func load(_ url: URL) throws -> EmbeddedFont {
            if let existing = loadedFonts[url] { return existing }
            let data = try Data(contentsOf: url)
            guard data.count <= Int(UInt32.max) else { throw PDFSourceError.font }
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
            let embedded = EmbeddedFont(handle: loaded,codes: codes)
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
                    guard let url = CTFontCopyAttribute(ctFont,kCTFontURLAttribute) as? URL else { throw PDFSourceError.font }
                    let font = try load(url)
                    guard let object = FPDFPageObj_CreateTextObj(handle.document,font.handle,Float(CTFontGetSize(ctFont))) else { throw PDFSourceError.font }
                    let codes = substring.unicodeScalars.compactMap { font.codes[$0.value] }
                    guard codes.count == substring.unicodeScalars.count,
                          codes.withUnsafeBufferPointer({ FPDFText_SetCharcodes(object,$0.baseAddress,$0.count) }) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    var position = CGPoint.zero
                    CTRunGetPositions(run,CFRange(location: 0,length: 1),&position)
                    if codes.count > 1 {
                        var positions: [Float] = [], utf16Index = range.location
                        for (index,scalar) in substring.unicodeScalars.enumerated() {
                            if index > 0 { positions.append(Float(CTLineGetOffsetForStringIndex(line,utf16Index,nil)-position.x)) }
                            utf16Index += scalar.value > 0xFFFF ? 2 : 1
                        }
                        guard positions.withUnsafeBufferPointer({ FPDFText_SetPositions(object,$0.baseAddress,$0.count) }) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    }
                    var placement = matrix
                    placement.e += matrix.a*Float(position.x)+matrix.c*Float(baseline+position.y)
                    placement.f += matrix.b*Float(position.x)+matrix.d*Float(baseline+position.y)
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
                              FPDFPageObjMark_SetFloatParam(handle.document,object,mark,"Width",Float(blockWidth)) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
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
        let container = Self.transformed(CGRect(x: 0,y: baseline+max(leading*fontSize/snapshot.fontSize,fontSize*1.2)-fontSize*0.3,width: blockWidth,height: max(fontSize,abs(baseline))),by: matrix)
        resultingBounds = union.isNull ? nil : union.union(container)
        if let first = objects.compactMap({ Self.bounds($0) }).first(where: { !$0.isEmpty }) {
            resultingPoint = CGPoint(x: first.midX,y: first.midY)
        }
        // Validate each generated object's text, not a clipped/partial page selection.
        if let check = FPDFText_LoadPage(handle.page) {
            defer { FPDFText_ClosePage(check) }
            let actual = objects.compactMap { try? Self.text(of: $0,in: check) }.joined()
            let expected = normalized.filter { !$0.isWhitespace }
            guard actual.filter({ !$0.isWhitespace }) == expected else { throw PDFSourceError.content }
        } else if !objects.isEmpty { throw PDFSourceError.content }
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length), length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        return Data(bytes: bytes,count: length)
    }

    private static func collect(_ object: FPDF_PAGEOBJECT, parent: FPDF_PAGEOBJECT?, parentMatrix: FS_MATRIX, rootIndex: Int, depth: Int, textPage: FPDF_TEXTPAGE, readings: [UInt: [Glyph]]? = nil, into result: inout [Fragment]) {
        guard depth < 32 else { return }
        if FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_FORM {
            var local = identity
            guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return }
            for index in 0..<max(0,Int(FPDFFormObj_CountObjects(object))) {
                if let child = FPDFFormObj_GetObject(object,UInt(index)) { collect(child,parent: object,parentMatrix: multiply(parentMatrix,local),rootIndex: rootIndex,depth: depth+1,textPage: textPage,readings: readings,into: &result) }
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
        result.append(Fragment(object: object,parent: parent,rootIndex: rootIndex,matrix: effective,bounds: transformed(rect,by: parentMatrix),text: text,style: Style(url: url,size: max(1,physicalSize),color: color),block: blockInfo(object)))
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
            return BlockInfo(id: name,text: body,width: validWidth ? CGFloat(width) : nil)
        }
        return nil
    }
    private static func indexedText(_ page: FPDF_TEXTPAGE) -> [UInt: [Glyph]] {
        var result: [UInt: [Glyph]] = [:]
        for index in 0..<max(0,FPDFText_CountChars(page)) {
            guard let object = FPDFText_GetTextObject(page,index), FPDFText_IsGenerated(page,index) != 1 else { continue }
            let unicode = FPDFText_GetUnicode(page,index)
            var x: Double = 0, y: Double = 0
            guard unicode != 0, FPDFText_GetCharOrigin(page,index,&x,&y) != 0 else { continue }
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
