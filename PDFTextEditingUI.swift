import SwiftUI
import AppKit
import PDFKit
import CoreText

@MainActor
final class PDFTextPropertiesModel: ObservableObject {
    enum Change { case family(String), size(CGFloat), color(NSColor), bold(Bool), italic(Bool), width(CGFloat), height(CGFloat), angle(CGFloat), x(CGFloat), y(CGFloat) }
    @Published var active = false
    @Published var selectionLength = 0
    @Published var family = "Arial"
    @Published var fonts: [String] = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    @Published var size: CGFloat = 14
    @Published var color = NSColor.black
    @Published var fontWarning = false
    @Published var bold = false
    @Published var italic = false
    @Published var width: CGFloat = 240
    @Published var height: CGFloat = 30
    @Published var angle: CGFloat = 0
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0
    var change: ((Change) -> Void)?
    var apply: (() -> Void)?
    var cancel: (() -> Void)?
    func reset() { active = false; fontWarning = false; change = nil; apply = nil; cancel = nil }
}

struct PDFTextPropertiesView: View {
    @ObservedObject var model: PDFTextPropertiesModel
    let russian: Bool
    private func label(_ en: String,_ ru: String) -> String { russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("PDF text","Текст PDF")).font(.system(size: 12,weight: .semibold))
            Text(model.selectionLength > 0 ? label("Selected: \(model.selectionLength) characters","Выделено: \(model.selectionLength) знаков") : label("Entire text block","Весь текстовый блок"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Picker(label("Font","Шрифт"),selection: Binding(get: { model.family },set: { model.change?(.family($0)) })) {
                ForEach(Array(Set(model.fonts+[model.family])).sorted { $0.localizedStandardCompare($1) == .orderedAscending },id: \.self) { Text($0).tag($0) }
            }
            if model.fontWarning { Text(label("This PDF font has no usable Unicode program. Install its full font or choose another face.","Шрифт PDF не содержит пригодной Unicode-программы. Установите полную версию шрифта или выберите другой." )).font(.system(size: 10)).foregroundStyle(.orange) }
            HStack {
                Text(label("Size, pt","Размер, pt"))
                TextField("",value: Binding(get: { Double(model.size) },set: { model.change?(.size(CGFloat($0))) }),format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder).frame(width: 72)
            }
            HStack {
                Toggle(label("Bold","Жирный"),isOn: Binding(get: { model.bold },set: { model.change?(.bold($0)) }))
                Toggle(label("Italic","Курсив"),isOn: Binding(get: { model.italic },set: { model.change?(.italic($0)) }))
            }.toggleStyle(.button)
            ColorPicker(label("Text color","Цвет текста"),selection: Binding(get: { Color(nsColor: model.color) },set: { model.change?(.color(NSColor($0))) }),supportsOpacity: false)
            Divider()
            Text(label("Block geometry","Геометрия блока")).font(.system(size: 11,weight: .semibold))
            metric(label("Width, pt","Ширина, pt"),model.width) { model.change?(.width($0)) }
            metric(label("Height, pt","Высота, pt"),model.height) { model.change?(.height($0)) }
            metric(label("Rotation, °","Поворот, °"),model.angle) { model.change?(.angle($0)) }
            metric("X, pt",model.x) { model.change?(.x($0)) }
            metric("Y, pt",model.y) { model.change?(.y($0)) }
            HStack {
                Button(label("Apply","Применить")) { model.apply?() }
                Button(label("Cancel","Отмена")) { model.cancel?() }
            }
            Text(label("Edit directly on the page. Drag the cross to move, corners to scale, side handles to change the text field, and the circular handle to rotate.","Редактируйте прямо на странице. Крестик — перемещение; углы — масштаб; боковые ручки — размер поля; круглая ручка — поворот."))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.font(.system(size: 11))
    }
    private func metric(_ title: String,_ value: CGFloat,action: @escaping (CGFloat) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("",value: Binding(get: { Double(value) },set: { action(CGFloat($0)) }),format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 85)
        }
    }
}

@MainActor
final class PDFInlineTextEditor: NSObject, NSTextViewDelegate {
    enum Handle: Equatable { case move, rotate, scale(Int), width(Int), height }
    private struct Drag {
        let handle: Handle
        let point: CGPoint
        let geometry: PDFTextGeometry
        let width: CGFloat
        let height: CGFloat
        let content: NSAttributedString
        let ascent: CGFloat
    }
    let snapshot: PDFSourceSession.Snapshot
    let page: PDFPage
    weak var pdfView: PDFView?
    let model: PDFTextPropertiesModel
    let editor = InlineTextView(frame: .zero)
    private let host = FlippedHost(frame: .zero)
    private let mask = OriginalTextMask(frame: .zero)
    private let previewDocument: PDFDocument?
    private(set) var geometry: PDFTextGeometry
    private(set) var width: CGFloat
    private(set) var height: CGFloat = 30
    private(set) var dirty = false
    private var minimumHeight: CGFloat = 0
    private var drag: Drag?
    private var suppressChanges = false
    private var propertiesPending = false
    private var baselineFromTop: CGFloat = 12
    var onApply: ((NSAttributedString,CGFloat,CGFloat,PDFTextGeometry) -> Bool)?
    var onCancel: (() -> Void)?
    var onRedraw: (() -> Void)?

    init(snapshot: PDFSourceSession.Snapshot,page: PDFPage,pdfView: PDFView,model: PDFTextPropertiesModel,previewPage: PDFPage? = nil) {
        self.snapshot = snapshot; self.page = page; self.pdfView = pdfView; self.model = model
        self.previewDocument = previewPage?.document
        geometry = snapshot.geometry; width = snapshot.width; minimumHeight = snapshot.height; baselineFromTop = snapshot.fontSize*0.85
        super.init()
        host.clipsToBounds = true; mask.clipsToBounds = true; editor.clipsToBounds = true
        host.addSubview(editor)
        editor.delegate = self; editor.isRichText = true; editor.importsGraphics = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.allowsUndo = true
        editor.drawsBackground = false; editor.backgroundColor = .clear; editor.insertionPointColor = .systemBlue
        editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        if #available(macOS 15.0,*) { editor.writingToolsBehavior = .none }
        editor.textStorage?.setAttributedString(snapshot.attributedText)
        if editor.string.isEmpty {
            let font = NSFont(name: snapshot.fontName,size: snapshot.fontSize) ?? NSFont.systemFont(ofSize: snapshot.fontSize)
            editor.typingAttributes = [.font: font,.foregroundColor: snapshot.color]
        }
        editor.escape = { [weak self] in self?.cancel() }
        editor.commit = { [weak self] in _ = self?.finish() }
        mask.pdfView = pdfView; mask.page = page; mask.previewPage = previewPage; mask.rect = snapshot.bounds
        mask.frame = pdfView.bounds; mask.autoresizingMask = [.width,.height]
        pdfView.addSubview(mask,positioned: .above,relativeTo: nil)
        pdfView.addSubview(host,positioned: .above,relativeTo: nil)
        model.active = true
        model.change = { [weak self] in self?.apply($0) }
        model.apply = { [weak self] in _ = self?.finish() }
        model.cancel = { [weak self] in self?.cancel() }
        updatePlacement(); updateProperties()
    }
    func focus(at point: CGPoint) {
        guard let pdfView else { return }
        pdfView.window?.makeFirstResponder(editor)
        let local = editor.convert(point,from: pdfView)
        let index = min((editor.string as NSString).length,max(0,editor.characterIndexForInsertion(at: local)))
        editor.setSelectedRange(NSRange(location: index,length: 0)); updateProperties()
    }
    var isAttached: Bool { host.superview != nil }
    func owns(_ view: NSView?) -> Bool { view?.isDescendant(of: host) == true || view === host }
    var attributedText: NSAttributedString { editor.attributedString().copy() as! NSAttributedString }
    var ascent: CGFloat { baselineFromTop }
    private var maximumFontSize: CGFloat {
        var size: CGFloat = 0
        editor.textStorage?.enumerateAttribute(.font,in: NSRange(location: 0,length: editor.textStorage?.length ?? 0)) { value,_,_ in
            if let font = value as? NSFont { size = max(size,font.pointSize) }
        }
        return size > 0 ? size : snapshot.fontSize
    }
    func updatePlacement() {
        guard let pdfView else { return }
        pdfView.clipsToBounds = true
        editor.frame = CGRect(x: 0,y: 0,width: width,height: max(30,height))
        editor.textContainer?.containerSize = CGSize(width: width,height: .greatestFiniteMagnitude)
        if let container = editor.textContainer {
            editor.layoutManager?.ensureLayout(for: container)
            height = max(minimumHeight,maximumFontSize*1.3,(editor.layoutManager?.usedRect(for: container).height ?? 0)+3)
            if let layout = editor.layoutManager,layout.numberOfGlyphs > 0 {
                baselineFromTop = layout.lineFragmentRect(forGlyphAt: 0,effectiveRange: nil).minY+layout.location(forGlyphAt: 0).y
            } else { baselineFromTop = (editor.typingAttributes[.font] as? NSFont)?.ascender ?? snapshot.fontSize*0.85 }
        }
        let top = geometry.point(x: 0,y: ascent)
        let origin = pdfView.convert(top,from: page)
        let x = pdfView.convert(geometry.point(x: 1,y: ascent),from: page)
        let y = pdfView.convert(geometry.point(x: 0,y: ascent-1),from: page)
        let scaleX = max(0.01,hypot(x.x-origin.x,x.y-origin.y)), scaleY = max(0.01,hypot(y.x-origin.x,y.y-origin.y))
        host.frameRotation = 0
        host.frame = CGRect(x: 0,y: 0,width: width*scaleX,height: height*scaleY)
        host.bounds = CGRect(x: 0,y: 0,width: width,height: height)
        host.frameRotation = atan2(x.y-origin.y,x.x-origin.x)*180 / .pi
        let current = host.convert(CGPoint.zero,to: pdfView)
        host.setFrameOrigin(CGPoint(x: host.frame.origin.x+origin.x-current.x,y: host.frame.origin.y+origin.y-current.y))
        editor.frame = CGRect(x: 0,y: 0,width: width,height: height)
        mask.frame = pdfView.bounds; mask.needsDisplay = true
        onRedraw?()
    }
    func quad() -> [CGPoint] {
        guard let pdfView else { return [] }
        return [geometry.point(x: 0,y: ascent),geometry.point(x: width,y: ascent),geometry.point(x: width,y: ascent-height),geometry.point(x: 0,y: ascent-height)].map { pdfView.convert($0,from: page) }
    }
    private func controls() -> [(Handle,CGPoint)] {
        let corners = quad(); guard corners.count == 4 else { return [] }
        func middle(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x: (a.x+b.x)/2,y: (a.y+b.y)/2) }
        let top = middle(corners[0],corners[1]), center = middle(corners[0],corners[2])
        let length = max(0.001,hypot(top.x-center.x,top.y-center.y))
        let normal = CGPoint(x: (top.x-center.x)/length,y: (top.y-center.y)/length)
        let rotate = CGPoint(x: top.x+normal.x*25,y: top.y+normal.y*25)
        let move = CGPoint(x: corners[0].x+normal.x*18,y: corners[0].y+normal.y*18)
        var result: [(Handle,CGPoint)] = corners.enumerated().map { (.scale($0.offset),$0.element) }
        result += [(.width(0),middle(corners[0],corners[3])),(.width(1),middle(corners[1],corners[2])),(.height,middle(corners[2],corners[3])),(.rotate,rotate),(.move,move)]
        return result
    }
    func handle(at point: CGPoint) -> Handle? {
        controls().reversed().first { hypot($0.1.x-point.x,$0.1.y-point.y) < 9 }?.0
    }
    func drawControls(in overlay: NSView) {
        guard let pdfView else { return }
        let corners = quad().map { overlay.convert($0,from: pdfView) }
        guard corners.count == 4 else { return }
        NSColor.systemBlue.setStroke(); let path = NSBezierPath(); path.move(to: corners[0])
        for point in corners.dropFirst() { path.line(to: point) }; path.close(); path.lineWidth = 1; path.stroke()
        for (handle,position) in controls() {
            let point = overlay.convert(position,from: pdfView)
            let rect = CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8)
            let mark = handle == .rotate ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            NSColor.white.setFill(); mark.fill(); NSColor.systemBlue.setStroke(); mark.lineWidth = 1; mark.stroke()
            if handle == .move {
                let cross = NSBezierPath(); cross.move(to: CGPoint(x: point.x-3,y: point.y)); cross.line(to: CGPoint(x: point.x+3,y: point.y)); cross.move(to: CGPoint(x: point.x,y: point.y-3)); cross.line(to: CGPoint(x: point.x,y: point.y+3)); cross.stroke()
            }
        }
    }
    func beginDrag(_ handle: Handle,at point: CGPoint) {
        drag = Drag(handle: handle,point: point,geometry: geometry,width: width,height: height,content: attributedText,ascent: ascent)
    }
    func drag(to point: CGPoint) {
        guard let start = drag else { return }
        suppressChanges = true
        geometry = start.geometry
        switch start.handle {
        case .move:
            geometry.origin.x += point.x-start.point.x; geometry.origin.y += point.y-start.point.y
        case .rotate:
            let center = start.geometry.point(x: start.width/2,y: start.ascent-start.height/2)
            let angle = atan2(point.y-center.y,point.x-center.x)-atan2(start.point.y-center.y,start.point.x-center.x)
            geometry = start.geometry.rotated(by: angle,around: center)
        case .width(let side):
            let local = start.geometry.local(point), first = start.geometry.local(start.point)
            let delta = local.x-first.x
            width = min(20000,max(20,start.width+(side == 0 ? -delta : delta)))
            if side == 0 { geometry.origin = start.geometry.point(x: start.width-width,y: 0) }
        case .height:
            let local = start.geometry.local(point), first = start.geometry.local(start.point)
            minimumHeight = max(10,start.height-(local.y-first.y))
        case .scale(let corner):
            let coordinates = [(CGFloat(0),start.ascent),(start.width,start.ascent),(start.width,start.ascent-start.height),(CGFloat(0),start.ascent-start.height)]
            let opposite = coordinates[(corner+2)%4], anchor = start.geometry.point(x: opposite.0,y: opposite.1)
            let before = max(1,hypot(start.point.x-anchor.x,start.point.y-anchor.y))
            let factor = min(10,max(0.1,hypot(point.x-anchor.x,point.y-anchor.y)/before))
            let scaled = NSMutableAttributedString(attributedString: start.content)
            scaled.enumerateAttribute(.font,in: NSRange(location: 0,length: scaled.length)) { value,range,_ in
                if let font = value as? NSFont { scaled.addAttribute(.font,value: NSFont(descriptor: font.fontDescriptor,size: min(2000,max(1,font.pointSize*factor))) ?? font,range: range) }
            }
            editor.textStorage?.setAttributedString(scaled)
            width = min(20000,max(20,start.width*factor)); minimumHeight = start.height*factor
            geometry.origin = CGPoint(x: anchor.x+(start.geometry.origin.x-anchor.x)*factor,y: anchor.y+(start.geometry.origin.y-anchor.y)*factor)
        }
        suppressChanges = false; dirty = true; updatePlacement(); updateProperties()
    }
    func endDrag() { drag = nil }
    func textDidChange(_ notification: Notification) {
        guard !suppressChanges else { return }; dirty = true; updatePlacement(); updateProperties()
    }
    func textViewDidChangeSelection(_ notification: Notification) { updateProperties() }
    func updateProperties() {
        guard !propertiesPending else { return }; propertiesPending = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }; self.propertiesPending = false
            guard self.host.superview != nil else { return }
            self.publishProperties()
        }
    }
    private func publishProperties() {
        let range = editor.selectedRange(), length = editor.textStorage?.length ?? 0
        let index = length == 0 ? 0 : min(range.location,length-1)
        let attributes = length == 0 ? editor.typingAttributes : editor.textStorage!.attributes(at: index,effectiveRange: nil)
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: snapshot.fontSize)
        model.selectionLength = range.length; model.family = font.familyName ?? "Arial"; model.size = font.pointSize
        model.color = attributes[.foregroundColor] as? NSColor ?? snapshot.color
        let traits = NSFontManager.shared.traits(of: font)
        model.bold = traits.contains(.boldFontMask); model.italic = traits.contains(.italicFontMask)
        model.width = width; model.height = height; model.angle = geometry.angle*180 / .pi
        model.x = geometry.origin.x; model.y = geometry.origin.y
    }
    func apply(_ change: PDFTextPropertiesModel.Change) {
        switch change {
        case .width(let value): width = min(20000,max(20,value))
        case .height(let value): minimumHeight = min(20000,max(10,value))
        case .angle(let value):
            let center = geometry.point(x: width/2,y: ascent-height/2)
            geometry = geometry.rotated(by: value * .pi/180-geometry.angle,around: center)
        case .x(let value): geometry.origin.x = value
        case .y(let value): geometry.origin.y = value
        default:
            guard let storage = editor.textStorage else { return }
            let selected = editor.selectedRange()
            let range = selected.length > 0 ? selected : NSRange(location: 0,length: storage.length)
            var typing = editor.typingAttributes
            @MainActor func changed(_ attributes: [NSAttributedString.Key:Any]) -> [NSAttributedString.Key:Any] {
                var result = attributes
                let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: snapshot.fontSize)
                switch change {
                case .family(let family):
                    if let exact = PDFFontCatalog.font(named: family,size: font.pointSize) { result[.font] = exact; model.fontWarning = false } else { model.fontWarning = true }
                case .size(let size): result[.font] = NSFont(descriptor: font.fontDescriptor,size: min(2000,max(1,size))) ?? font
                case .color(let color): result[.foregroundColor] = color
                case .bold(let enabled): result[.font] = enabled ? NSFontManager.shared.convert(font,toHaveTrait: .boldFontMask) : NSFontManager.shared.convert(font,toNotHaveTrait: .boldFontMask)
                case .italic(let enabled): result[.font] = enabled ? NSFontManager.shared.convert(font,toHaveTrait: .italicFontMask) : NSFontManager.shared.convert(font,toNotHaveTrait: .italicFontMask)
                default: break
                }
                return result
            }
            suppressChanges = true
            let existing = storage.copy() as! NSAttributedString
            existing.enumerateAttributes(in: range) { attributes,subrange,_ in storage.setAttributes(changed(attributes),range: subrange) }
            typing = changed(typing); editor.typingAttributes = typing
            editor.setSelectedRange(selected); suppressChanges = false
        }
        dirty = true; updatePlacement(); updateProperties()
    }
    @discardableResult func finish() -> Bool {
        guard !dirty || onApply?(attributedText,width,height,geometry) != false else { return false }
        remove(); return true
    }
    func cancel() { onCancel?(); remove() }
    func remove() {
        editor.delegate = nil; host.removeFromSuperview(); mask.removeFromSuperview(); model.reset(); onRedraw?()
    }
    final class FlippedHost: NSView { override var isFlipped: Bool { true } }
    final class InlineTextView: NSTextView {
        var escape: (() -> Void)?
        var commit: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { escape?(); return }
            if event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76) { commit?(); return }
            super.keyDown(with: event)
        }
    }
    final class OriginalTextMask: NSView {
        weak var pdfView: PDFView?
        weak var page: PDFPage?
        var rect = CGRect.zero
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var previewPage: PDFPage?
        override func draw(_ dirtyRect: NSRect) {
            guard let pdfView,let page,let previewPage,let reference = previewPage.pageRef,
                  let context = NSGraphicsContext.current?.cgContext else { return }
            NSBezierPath(rect: bounds).addClip()
            let target = convert(pdfView.convert(page.bounds(for: .cropBox),from: page),from: pdfView)
            // Redraw the entire unchanged page background as PDF vectors, with
            // only the selected text suppressed. No white text-field rectangle.
            NSColor.white.setFill(); NSBezierPath(rect: target).fill()
            context.saveGState()
            context.concatenate(reference.getDrawingTransform(.cropBox,rect: target,rotate: 0,preserveAspectRatio: false))
            context.drawPDFPage(reference)
            for annotation in previewPage.annotations where annotation.shouldDisplay { annotation.draw(with: .cropBox,in: context) }
            context.restoreGState()

        }
    }
}
