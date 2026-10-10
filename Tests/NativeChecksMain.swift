

extension PDFViewerView {
    fileprivate func checkMagnify(_ delta: CGFloat, anchor: CGPoint) { applyMagnification(delta, at: anchor) }
    fileprivate func checkQueuedMagnify(_ delta: CGFloat, anchor: CGPoint) { queueMagnification(delta,at: anchor) }
    fileprivate func checkFlushMagnify() { flushMagnification() }
    fileprivate func checkDraw(page: PDFPage, start: CGPoint, end: CGPoint, tool: PDFTool) {
        commitDrawing(Preview(page: page, start: start, end: end, tool: tool))
    }
}
extension PDFViewer.Coordinator {
    fileprivate func checkCommand(_ command: ViewerCommand, view: PDFViewerView) { perform(command, on: view) }
    fileprivate func checkSync(view: PDFViewerView) { observeScroll(in: view); syncPage(); syncMetrics(for: view) }
}

@main
struct NativeChecks {
    @MainActor static func main() throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError("CHECK FAILED: \(message)") }
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.setBounds(CGRect(x: 12, y: 20, width: 588, height: 752), for: .cropBox)
        document.insert(page, at: 0)
        document.insert(PDFPage(), at: 1)
        document.page(at: 1)?.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let initial = root.appendingPathComponent("native-checks.pdf")
        expect(document.write(to: initial), "initial PDF writes")
        let manager = DocumentManager()
        manager.open(initial)
        let item = manager.selected!
        let pdf = PDFViewerView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pdf
        let coordinator = PDFViewer.Coordinator(manager: manager)
        coordinator.attach(pdf); coordinator.update(pdf)
        expect(pdf.hitTest(CGPoint(x: -1,y: 10)) == nil,"offscreen text editors never hit-test outside the viewport")
        pdf.displayBox = .cropBox; pdf.displayMode = .singlePageContinuous; pdf.scaleFactor = 1.5
        pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
        let activePage = item.document.page(at: 0)!
        pdf.go(to: activePage)

        for rotation in [0, 90, 180, 270] {
            activePage.rotation = rotation
            pdf.document = nil; pdf.document = item.document; pdf.scaleFactor = 1.5
            pdf.go(to: activePage); pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
            let sample = CGPoint(x: 110, y: 240)
            let mapped = pdf.convert(sample, from: activePage)
            let roundTrip = pdf.convert(mapped, to: activePage)
            expect(hypot(roundTrip.x - sample.x, roundTrip.y - sample.y) < 0.001, "rotated PDF conversion round-trip \(rotation)")
            coordinator.checkSync(view: pdf)
            expect(manager.rulerMetrics.valid, "ruler metrics valid for \(rotation)")
            expect(abs(manager.rulerMetrics.horizontalPointsPerPixel) > 0.001, "horizontal ruler has a real PDF-space derivative")
            expect(abs(manager.rulerMetrics.verticalPointsPerPixel) > 0.001, "vertical ruler has a real PDF-space derivative")
        }
        activePage.rotation = 0; pdf.document = nil; pdf.document = item.document; pdf.scaleFactor = 1.5
        pdf.go(to: activePage); pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
        coordinator.checkSync(view: pdf)
        let beforePan = manager.rulerMetrics
        let clip = pdf.internalScrollView!.contentView
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: CGPoint(x: clip.bounds.minX + 35, y: clip.bounds.minY + 45), size: clip.bounds.size)).origin)
        pdf.internalScrollView!.reflectScrolledClipView(clip)
        coordinator.checkSync(view: pdf)
        expect(manager.rulerMetrics != beforePan, "clip-view pan updates ruler offset")
        let beforeZoom = manager.rulerMetrics
        pdf.scaleFactor = 2
        coordinator.checkSync(view: pdf)
        expect(manager.rulerMetrics != beforeZoom, "PDF scale updates ruler derivative")
        expect(abs(RulerUnit.millimeters.pointsPerUnit * 25.4 - 72) < 0.00001, "mm conversion")
        expect(RulerUnit.inches.pointsPerUnit == 72, "inch conversion")
        for _ in 0..<1104 {
            expect(RulerLabelFormatter.label(value: 0,minorInterval: 1,digits: 0,language: .en) == "0","ruler zero label")
            expect(RulerLabelFormatter.label(value: 1.25,minorInterval: 0.01,digits: 2,language: .en) == "1.25","ruler fractional label")
        }
        expect(RulerLabelFormatter.label(value: -0.00001,minorInterval: 0.1,digits: 2,language: .en) == "0.00","ruler suppresses negative zero")
        expect(RulerLabelFormatter.label(value: 1.25,minorInterval: 0.01,digits: 2,language: .ru) == "1,25","ruler follows selected Russian locale")
        expect(RulerLabelFormatter.label(value: -1000,minorInterval: 1,digits: 0,language: .en) == "-1000","ruler negative coordinate has no group separator")
        expect(RulerLabelFormatter.label(value: .infinity,minorInterval: 1,digits: 0,language: .en).isEmpty,"invalid ruler geometry is not formatted")
        let blankText = try PDFSourceTextReader.pages(data: Data(contentsOf: initial))
        expect(blankText == ["",""],"embedded-text reader keeps blank pages empty without OCR")
        var canRenderOffscreen = true
        #if arch(x86_64)
        // macos-15-intel is a headless VM: SwiftUI's offscreen renderer can
        // abort inside MTLLoader after returning its image. Real Intel Macs
        // still run this check; all numeric/PDF checks always run in CI.
        canRenderOffscreen = ProcessInfo.processInfo.environment["CI"] != "true"
        #endif
        if canRenderOffscreen {
            let rulerImage = ImageRenderer(content: RulerBar(axis: .horizontal,manager: manager).frame(width: 500,height: 24))
            expect(rulerImage.cgImage != nil,"ruler Canvas renders numeric labels")
            print("PASS: real ruler Canvas rendering")
        } else { print("SKIP: offscreen SwiftUI Canvas on the Intel CI VM without a supported Metal device") }
        print("PASS: 1104 typed ruler label passes and RU/EN numbers")
        let scrollBefore = clip.bounds.origin
        let wheelCG = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0)!
        wheelCG.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let wheel = NSEvent(cgEvent: wheelCG)!
        pdf.scrollWheel(with: wheel)
        expect(clip.bounds.origin != scrollBefore, "two-finger scrolling changes the internal clip origin")
        let downwardDelta = clip.bounds.minY - scrollBefore.y
        expect(downwardDelta * (clip.isFlipped ? 1 : -1) > 0, "downward scrolling follows native document direction")
        coordinator.checkSync(view: pdf)
        let zoomBeforeGesture = pdf.scaleFactor
        let anchor = CGPoint(x: pdf.bounds.midX, y: pdf.bounds.midY)
        let anchorPage = pdf.page(for: anchor, nearest: true)!
        let anchorPDFPoint = pdf.convert(anchor, to: anchorPage)
        pdf.checkMagnify(0.15, anchor: anchor)
        expect(pdf.scaleFactor > zoomBeforeGesture, "trackpad gesture increases zoom")
        let afterAnchor = pdf.convert(anchorPDFPoint, from: anchorPage)
        let anchorError = hypot(afterAnchor.x - anchor.x, afterAnchor.y - anchor.y)
        let oneClipUnit = pdf.convert(CGPoint(x: 1, y: 1), from: clip) - pdf.convert(.zero, from: clip)
        let toleranceX = max(1, abs(oneClipUnit.x) * 0.5 + 0.05)
        let toleranceY = max(1, abs(oneClipUnit.y) * 0.5 + 0.05)
        let aligned = abs(afterAnchor.x - anchor.x) < toleranceX && abs(afterAnchor.y - anchor.y) < toleranceY
        if !aligned { FileHandle.standardError.write(Data("Anchor error \(anchorError), native tolerances \(toleranceX), \(toleranceY)\n".utf8)) }
        expect(aligned, "gesture zoom retains its anchor within native clip alignment")
        pdf.checkMagnify(-0.15, anchor: anchor)
        expect(abs(pdf.scaleFactor - zoomBeforeGesture) < 0.001, "reverse trackpad gesture restores zoom")
        let responderBefore = window.firstResponder
        let queuedZoom = pdf.scaleFactor
        pdf.checkQueuedMagnify(0.04,anchor: anchor); pdf.checkQueuedMagnify(0.06,anchor: anchor)
        pdf.checkFlushMagnify()
        expect(abs(pdf.scaleFactor - queuedZoom*exp(0.10)) < 0.001,"queued zoom preserves accumulated gesture deltas")
        expect(window.firstResponder === responderBefore,"gesture zoom does not require a click or change focus")
        pdf.checkMagnify(-0.10,anchor: anchor)

        // These run the same native drawing entry point used when a drag ends.
        pdf.strokeColor = NSColor.red.withAlphaComponent(0.45); pdf.strokeWidth = 3
        pdf.checkDraw(page: activePage, start: CGPoint(x: 60, y: 80), end: CGPoint(x: 140, y: 130), tool: .rectangle)
        let rectangle = activePage.annotations.last!
        pdf.checkDraw(page: activePage, start: CGPoint(x: 160, y: 90), end: CGPoint(x: 230, y: 150), tool: .arrow)
        let arrow = activePage.annotations.last!
        expect(arrow.endLineStyle == .openArrow, "arrow ornament")
        expect(rectangle.border?.lineWidth == 3, "configured vector stroke")

        pdf.onCreateText = { page, point, leader in
            let text = PDFAnnotation(bounds: CGRect(x: point.x, y: point.y - 60, width: 140, height: 60), forType: .freeText, withProperties: nil)
            text.contents = "Grouped callout"; text.color = .clear; text.font = NSFont.systemFont(ofSize: 16); text.fontColor = .blue
            if let leader, let group = AnnotationMetadata.group(of: leader) { AnnotationMetadata.setOpacity(1, on: text); AnnotationMetadata.setGroup(group, on: text) }
            page.addAnnotation(text); pdf.selectAnnotation(text)
        }
        pdf.checkDraw(page: activePage, start: CGPoint(x: 300, y: 650), end: CGPoint(x: 420, y: 560), tool: .callout)
        let calloutText = pdf.selectedAnnotation!
        let leader = activePage.annotations.first { $0.type == "Line" && AnnotationMetadata.group(of: $0) == AnnotationMetadata.group(of: calloutText) }!
        pdf.selectAnnotation(leader)
        expect(pdf.selectedAnnotation === calloutText, "callout leader selects text component")
        calloutText.bounds = calloutText.bounds.offsetBy(dx: 15, dy: 15)
        pdf.updateCalloutLeader(for: calloutText)
        expect(abs(leader.bounds.minX + leader.endPoint.x - calloutText.bounds.minX) < 0.001, "callout leader follows its text box")

        let freeText = PDFAnnotation(bounds: CGRect(x: 70, y: 300, width: 260, height: 60), forType: .freeText, withProperties: nil)
        freeText.contents = "Before"; freeText.font = NSFont.systemFont(ofSize: 18); freeText.fontColor = .red
        freeText.color = .red; let border = PDFBorder(); border.lineWidth = 2; freeText.border = border
        activePage.addAnnotation(freeText)
        let editor = FreeTextEditorController(annotation: freeText, language: .en)
        _ = editor.view
        editor.textView.string = "BotPlus live typing\nSecond line"
        editor.textDidChange(Notification(name: NSText.didChangeNotification))
        expect(freeText.contents == editor.textView.string, "live typing updates PDF annotation before commit")
        editor.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        expect(freeText.font?.pointSize == 18, "editor font setting persists")

        // Use real mouse events to select and translate an annotation, then delete it.
        pdf.activeTool = .selectComments
        func mouse(_ type: NSEvent.EventType, point: CGPoint) -> NSEvent {
            let screen = pdf.convert(pdf.convert(point, from: activePage), to: nil)
            return NSEvent.mouseEvent(with: type, location: screen, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let originalBounds = rectangle.bounds
        let center = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        pdf.mouseDown(with: mouse(.leftMouseDown, point: center))
        pdf.mouseDragged(with: mouse(.leftMouseDragged, point: CGPoint(x: center.x + 20, y: center.y + 15)))
        pdf.mouseUp(with: mouse(.leftMouseUp, point: CGPoint(x: center.x + 20, y: center.y + 15)))
        expect(abs(rectangle.bounds.minX - originalBounds.minX - 20) < 0.01, "annotation moves in page coordinates")
        let corner = CGPoint(x: rectangle.bounds.maxX, y: rectangle.bounds.maxY)
        let originalWidth = rectangle.bounds.width
        pdf.mouseDown(with: mouse(.leftMouseDown, point: corner))
        pdf.mouseDragged(with: mouse(.leftMouseDragged, point: CGPoint(x: corner.x + 25, y: corner.y + 25)))
        pdf.mouseUp(with: mouse(.leftMouseUp, point: CGPoint(x: corner.x + 25, y: corner.y + 25)))
        expect(abs(rectangle.bounds.width - originalWidth - 25) < 0.01, "resize handle changes annotation bounds")
        let deletion = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        pdf.keyDown(with: deletion)
        expect(!activePage.annotations.contains(rectangle), "Delete removes selected annotation")

        let image = activePage.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: root.appendingPathComponent("annotation-render.png"))
        manager.saveDocument()
        let reopened = PDFDocument(url: initial)!
        let metadataContainers = reopened.page(at: 0)!.annotations.filter { AnnotationMetadata.isContainer($0) }
        expect(!metadataContainers.isEmpty && metadataContainers.allSatisfy { !$0.shouldDisplay && !$0.shouldPrint }, "metadata is invisible and non-printing in saved PDF")
        AnnotationMetadata.restore(reopened)
        let savedText = reopened.page(at: 0)!.annotations.first { $0.contents == freeText.contents }!
        expect(savedText.contents == freeText.contents, "FreeText contents round-trip through real PDF file")
        let savedArrow = reopened.page(at: 0)!.annotations.first { $0.type == "Line" }!
        expect(savedArrow.endLineStyle == .openArrow, "arrow survives PDF reopening")
        expect(savedArrow.border?.lineWidth == 3, "stroke width survives reopening")
        expect(abs(AnnotationMetadata.alpha(of: savedArrow) - 0.45) < 0.001, "opacity survives PDF reopening")
        expect(reopened.page(at: 0)!.annotations.filter { AnnotationMetadata.group(of: $0) != nil }.count == 2, "callout association survives PDF reopening")
        pdf.go(to: activePage)
        coordinator.checkSync(view: pdf)
        expect(pdf.currentPage === activePage, "duplicate targets the active page")
        coordinator.checkCommand(.duplicatePage, view: pdf)
        expect(item.pageCount == 3, "duplicate current page")
        expect(item.document.page(at: 1)!.annotations.filter { !AnnotationMetadata.isContainer($0) }.count == activePage.annotations.filter { !AnnotationMetadata.isContainer($0) }.count, "duplicate preserves annotations")
        coordinator.checkCommand(.insertBlankPage, view: pdf)
        expect(item.pageCount == 4 && pdf.currentPage!.annotations.isEmpty, "insert clean blank page")
        coordinator.checkCommand(.deletePage, view: pdf)
        expect(item.pageCount == 3, "delete active page")
        manager.saveDocument()
        expect(PDFDocument(url: initial)!.pageCount == 3, "page edits survive reopening")

        let panels = PanelWorkspaceModel()
        panels.setDock(.left, for: .bookmarks); panels.select(.bookmarks)
        expect(panels.activePanel(on: .left) == .bookmarks, "tab selects drawer")
        panels.toggleDrawer(.bookmarks)
        expect(panels.activePanel(on: .left) == nil, "icon collapses entire tabbed drawer")
        panels.select(.bookmarks); panels.setPinned(false, for: .bookmarks); panels.collapseAutoHiddenPanels()
        expect(panels.activePanel(on: .left) == nil, "auto-hide collapses unpinned drawer")
        panels.select(.bookmarks); panels.setPinned(true, for: .bookmarks); panels.collapseAutoHiddenPanels()
        expect(panels.activePanel(on: .left) == .bookmarks, "pinned drawer survives viewport click")
        panels.setWidth(900, for: .bookmarks); expect(panels.configuration(for: .bookmarks).width == 600, "panel maximum width")
        panels.setWidth(20, for: .bookmarks); expect(panels.configuration(for: .bookmarks).width == 200, "panel minimum width")
        try runPDFiumChecks(root: root)
        try runTextBlockChecks()
        try runInlineTextChecks()
        try runRibbonFeatureChecks(root: root)
        let originalPages = item.pageCount
        coordinator.checkCommand(.duplicatePageAt(0),view: pdf)
        expect(item.pageCount == originalPages+1,"thumbnail menu duplicates the requested page")
        coordinator.checkCommand(.deletePageAt(1),view: pdf)
        expect(item.pageCount == originalPages,"thumbnail menu deletes the requested page")
        coordinator.checkCommand(.blankPageAt(1),view: pdf)
        expect(item.pageCount == originalPages+1,"thumbnail menu inserts a blank page at the requested index")
        coordinator.checkCommand(.deletePageAt(1),view: pdf)
        pdf.scaleFactor = 0.3
        coordinator.checkCommand(.page(0),view: pdf)
        let centeredRect = pdf.convert(item.document.page(at: 0)!.bounds(for: .cropBox),from: item.document.page(at: 0)!)
        expect(abs(centeredRect.midY-pdf.bounds.midY) < 2,"thumbnail navigation centers a short page vertically")

        // Use an isolated pasteboard, preserving the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        pdf.go(to: activePage)
        let pasteTarget = pdf.currentPage!
        let existingCount = pasteTarget.annotations.filter { !AnnotationMetadata.isContainer($0) }.count
        let copiedData = coordinator.checkClipboardData(arrow)
        expect(copiedData != nil, "serializes a copied annotation object")
        if !board.name.rawValue.isEmpty {
            expect(coordinator.checkCopy(arrow,board: board), "copies an annotation object to the system pasteboard")
            coordinator.checkPaste(view: pdf,board: board)
        } else {
            print("SKIP: system pasteboard unavailable in this execution sandbox; object data round-trip still checked")
            expect(coordinator.checkPasteData(copiedData!,view: pdf), "pastes serialized annotation data")
        }
        let afterPasteCount = pasteTarget.annotations.filter { !AnnotationMetadata.isContainer($0) }.count
        expect(afterPasteCount == existingCount + 1, "pastes the copied annotation onto the current page")
        let pasted = pdf.selectedAnnotation!
        expect(pasted !== arrow && pasted.type == "Line", "paste creates an independent object")
        expect(abs(AnnotationMetadata.alpha(of: pasted) - 0.45) < 0.001, "clipboard preserves opacity")
        expect(pdf.deleteSelectedAnnotation(), "Object Delete removes the pasted annotation")
        let light = NSAppearance(named: .aqua)!
        var lightValue: CGFloat = 0
        light.performAsCurrentDrawingAppearance { lightValue = NSColor(Palette.ribbon).usingColorSpace(.deviceRGB)!.redComponent }
        let dark = NSAppearance(named: .darkAqua)!
        var darkValue: CGFloat = 0
        dark.performAsCurrentDrawingAppearance { darkValue = NSColor(Palette.ribbon).usingColorSpace(.deviceRGB)!.redComponent }
        expect(lightValue > 0.8 && darkValue < 0.3, "theme palette resolves both light and dark appearances")
        coordinator.detach(); pdf.stopEventMonitoring(); window.close()
        print("PASS: rulers, two-finger scrolling, anchored gesture zoom, live text, opacity and callout persistence, drag/resize/delete, page edits, panel invariants")
    }
}

extension PDFViewer.Coordinator {
    fileprivate func checkCopy(_ annotation: PDFAnnotation, board: NSPasteboard) -> Bool { copyAnnotationObjects(annotation, board: board) }
    fileprivate func checkPaste(view: PDFViewerView, board: NSPasteboard) { pasteObjects(on: view, board: board) }
    fileprivate func checkClipboardData(_ annotation: PDFAnnotation) -> Data? { annotationClipboardData(annotation) }
    fileprivate func checkPasteData(_ data: Data, view: PDFViewerView) -> Bool { pasteAnnotationData(data,on: view) }
}

@MainActor
private func runPDFiumChecks(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("PDFIUM CHECK FAILED: \(message)") }
    }
    // Initialize through the same document-session path before calling fixture APIs.
    let seed = PDFDocument(); let seedPage = PDFPage(); seedPage.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); seed.insert(seedPage,at: 0)
    let initialize = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 16,color: .black)
    _ = try initialize.applying(text: "Seed",fontSize: 16,color: .black)
    let document = FPDF_CreateNewDocument()!
    let page = FPDFPage_New(document,0,612,792)!
    let object = "Helvetica".withCString { FPDFPageObj_NewTextObj(document,$0,16) }!
    let original = "Original PDF content"
    let utf16 = Array(original.utf16) + [0]
    expect(utf16.withUnsafeBufferPointer { FPDFText_SetText(object,$0.baseAddress) } != 0, "fixture text")
    var matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 72,f: 700)
    expect(FPDFPageObj_SetMatrix(object,&matrix) != 0, "fixture matrix")
    expect(FPDFPage_InsertObject(page,object) != 0, "fixture insertion")
    let rectangle = FPDFPageObj_CreateNewRect(400,400,60,60)!
    _ = FPDFPageObj_SetFillColor(rectangle,255,255,0,255); _ = FPDFPath_SetDrawMode(rectangle,FPDF_FILLMODE_WINDING,0)
    expect(FPDFPage_InsertObject(page,rectangle) != 0, "fixture vector")
    expect(FPDFPage_GenerateContent(page) != 0, "fixture content")
    var length = 0
    let bytes = BotPlusPDFium_SaveDocument(document,&length)!
    let data = Data(bytes: bytes,count: length); BotPlusPDFium_Free(bytes)
    FPDF_ClosePage(page); FPDF_CloseDocument(document)
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    expect(session.snapshot.text.contains(original), "reads the original content object")
    let replacement = "Новый исходный текст"
    let edited = try session.applying(text: replacement,fontSize: 18,color: .systemBlue,width: 400)
    let pdf = PDFDocument(data: edited)!
    expect(pdf.page(at: 0)!.string?.contains(replacement) == true, "replacement is searchable PDF page text")
    expect(pdf.page(at: 0)!.string?.contains(original) != true, "old original text is removed, not covered by an annotation")
    expect(pdf.page(at: 0)!.annotations.filter { $0.shouldDisplay || $0.shouldPrint }.isEmpty, "source editing creates no visible or printable overlay annotation")
    let path = root.appendingPathComponent("edited-content.pdf")
    expect(pdf.write(to: path), "modified content saves")
    let reopenedText = PDFDocument(url: path)?.page(at: 0)?.string ?? ""
    if !reopenedText.contains(replacement) {
        FileHandle.standardError.write(Data("PDFKit saved text extraction: \(reopenedText.debugDescription)\n".utf8))
    }
    expect(reopenedText.filter { !$0.isWhitespace }.contains(replacement.filter { !$0.isWhitespace }), "all modified characters survive reopening")
    let memory = edited as NSData
    let checkDoc = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil)!
    let checkPage = FPDF_LoadPage(checkDoc,0)!
    expect(FPDFPage_CountObjects(checkPage) == 2, "editing preserves the vector object")
    FPDF_ClosePage(checkPage); FPDF_CloseDocument(checkDoc)
    let removing = try PDFSourceSession.editing(data: edited,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    let deleted = try removing.applying(text: "",fontSize: 18,color: .black)
    expect(PDFDocument(data: deleted)?.page(at: 0)?.string?.contains(replacement) != true, "source Delete removes the text layer object")
    let adding = try PDFSourceSession.adding(data: deleted,pageIndex: 0,point: CGPoint(x: 72,y: 600),fontSize: 16,color: .black)
    let added = try adding.applying(text: "Вставленный текст\nВторая строка",fontSize: 16,color: .black)
    expect(PDFDocument(data: added)?.page(at: 0)?.string?.contains("Вставленный текст") == true, "native add/paste creates searchable text")
    expect(PDFDocument(data: added)?.page(at: 0)?.string?.contains("Вторая строка") == true, "multiline content text")

    // Quartz commonly wraps imported PDF pages inside a Form XObject.
    let wrapped = NSMutableData()
    let consumer = CGDataConsumer(data: wrapped)!
    var media = CGRect(x: 0,y: 0,width: 612,height: 792)
    let context = CGContext(consumer: consumer,mediaBox: &media,nil)!
    context.beginPDFPage(nil); context.drawPDFPage(PDFDocument(data: data)!.page(at: 0)!.pageRef!); context.endPDFPage(); context.closePDF()
    let formSession = try PDFSourceSession.editing(data: wrapped as Data,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    let changedForm = try formSession.applying(text: "Form text replaced",fontSize: 16,color: .black)
    expect(PDFDocument(data: changedForm)?.page(at: 0)?.string?.contains("Form text replaced") == true, "imported/Form text editing")
    expect(PDFDocument(data: changedForm)?.page(at: 0)?.string?.contains(original) != true, "imported original text removed")
    print("PASS: PDFium original text replacement, Cyrillic, deletion, searchable insertion, vector preservation, and imported PDF content")
}

@MainActor
private func runTextBlockChecks() throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("BLOCK CHECK FAILED: \(message)") }
    }
    // Deliberately continue BT/ET and its font state across /Contents streams,
    // as CAD producers do. Also keep a neighboring column and a vector path.
    let first = "BT /F1 14 Tf 1 0 0 1 72 700 Tm (Fragmented) Tj 1 0 0 1 156 700 Tm (text) Tj\n"
    let second = "1 0 0 1 72 682 Tm (continues here.) Tj 1 0 0 1 380 700 Tm (Neighbor column) Tj ET\n0 0 0 RG 400 400 40 40 re S\n"
    let bold = "BT /F1 14 Tf 1 0 0 1 72 500 Tm (Duplicated) Tj 1 0 0 1 72.01 500 Tm (Duplicated) Tj ET\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 6 0 R >> >> /Contents [4 0 R 5 0 R 7 0 R] >>",
        "<< /Length \(first.utf8.count) >>\nstream\n"+first+"endstream",
        "<< /Length \(second.utf8.count) >>\nstream\n"+second+"endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length \(bold.utf8.count) >>\nstream\n"+bold+"endstream"
    ]
    var data = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (index,object) in objects.enumerated() {
        offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    var ending = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { ending += String(format: "%010lld 00000 n \n",Int64(offset)) }
    ending += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(ending.utf8))
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    expect(session.snapshot.fragmentCount >= 3,"word fragments and the next line belong to one paragraph")
    expect(session.snapshot.text.contains("Fragmented text continues here."),"complete paragraph reconstruction")
    expect(!session.snapshot.text.contains("Neighbor"),"adjacent column stays separate")
    let original = try session.applying(text: session.snapshot.text,fontSize: session.snapshot.fontSize,color: session.snapshot.color)
    expect(original == data,"no-op leaves the original PDF byte-for-byte unchanged")
    let editing = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    let replacement = "Fragmented edited text continues here -; Cyrillic: Привет."
    let changed = try editing.applying(text: replacement,fontSize: 14,color: .black,width: 110)
    let page = PDFDocument(data: changed)!.page(at: 0)!
    let text = page.string ?? ""
    let withoutWhitespace = text.filter { !$0.isWhitespace }
    if !withoutWhitespace.contains(replacement.filter { !$0.isWhitespace }) {
        FileHandle.standardError.write(Data("PDFKit column reading order: \(text.debugDescription)\n".utf8))
    }
    let scopedBlock = try PDFSourceSession.editing(data: changed,pageIndex: 0,point: CGPoint(x: 80,y: 705))
    expect(scopedBlock.snapshot.text.filter { !$0.isWhitespace } == replacement.filter { !$0.isWhitespace },"wrapped block retains every character, punctuation and Cyrillic")
    expect(withoutWhitespace.contains("Привет"),"PDFKit also extracts the new Cyrillic word")
    let serialized = PDFDocument(data: changed)!.dataRepresentation()!
    let afterPDFKit = try PDFSourceSession.editing(data: serialized,pageIndex: 0,point: editing.resultingPoint!)
    expect(afterPDFKit.snapshot.text.filter { !$0.isWhitespace } == replacement.filter { !$0.isWhitespace },"block text survives PDFKit serialization")
    expect(abs(afterPDFKit.snapshot.width-110) < 0.01,"block width persists through PDFKit serialization")
    expect(text.contains("Neighbor column"),"text in the following content stream survives save/reopen")
    expect((editing.resultingBounds?.height ?? 0) > editing.snapshot.bounds.height,"block grows vertically instead of clipping new text")
    let memory = changed as NSData
    let doc = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil)!, nativePage = FPDF_LoadPage(doc,0)!
    let paths = (0..<FPDFPage_CountObjects(nativePage)).filter { FPDFPageObj_GetType(FPDFPage_GetObject(nativePage,$0)) == FPDF_PAGEOBJ_PATH }.count
    expect(paths == 1,"preserves unrelated vector content")
    FPDF_ClosePage(nativePage); FPDF_CloseDocument(doc)
    let duplicate = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 100,y: 505))
    expect(duplicate.snapshot.text == "Duplicated","coincident CAD drawing passes become one editable word")
    let duplicateAfterSave = try PDFSourceSession.editing(data: changed,pageIndex: 0,point: CGPoint(x: 100,y: 505))
    expect(duplicateAfterSave.snapshot.text == "Duplicated","duplicate detection also works after page regeneration")
    let invalid = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    do {
        _ = try invalid.applying(text: "Unsupported 🦄",fontSize: 14,color: .black)
        fatalError("BLOCK CHECK FAILED: unsupported glyph must be rejected")
    } catch PDFSourceError.unsupportedGlyph { }
    print("PASS: paragraph blocks, separate columns, cross-stream text scopes, wrapping, Unicode punctuation, CAD duplicates, and unsupported glyph protection")
}

@MainActor
private func runInlineTextChecks() throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("INLINE CHECK FAILED: \(message)") } }
    let seed = PDFDocument(), blank = PDFPage(); blank.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); seed.insert(blank,at: 0)
    let adding = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 14,color: .black)
    let data = try adding.applying(text: "Alpha Beta Gamma",fontSize: 14,color: .black,width: 260)
    let previewSession = try PDFSourceSession.editing(data: data,pageIndex: 0,point: adding.resultingPoint!)
    let suppressed = try previewSession.previewWithoutSelectedText()
    expect(PDFDocument(data: suppressed)?.page(at: 0)?.string?.contains("Alpha") != true,"vector preview suppresses the original selected text without a field background")
    expect(PDFDocument(data: data)?.page(at: 0)?.string?.contains("Alpha") == true,"vector preview leaves the real document unchanged")
    let fonts = try PDFSourceSession.documentFonts(data: data)
    expect(Set(NSFontManager.shared.availableFontFamilies).isSubset(of: Set(fonts)),"font catalog contains all system families")
    expect(fonts.contains { $0.contains("Arial") },"font catalog includes embedded PDF font names")
    for name in ["Helvetica","Menlo-Regular","AmericanTypewriter"] {
        guard PDFFontCatalog.font(named: name,size: 14) != nil else { continue }
        let source = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 14,color: .black,fontName: name)
        let changed = try source.applying(text: "System font; 123-ABC",fontSize: 14,color: .black)
        let saved = PDFDocument(data: changed)!.dataRepresentation()!
        expect(PDFDocument(data: saved)?.page(at: 0)?.string?.contains("System font; 123-ABC") == true,"system collection/CFF font persists searchable text: \(name)")
    }
    let blocks = try PDFSourceSession.blocks(data: data,pageIndex: 0)
    expect(blocks.count == 1,"catalog shows one frame around the complete text block")
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: adding.resultingPoint!)
    let document = PDFDocument(data: data)!, page = document.page(at: 0)!
    let pdf = PDFView(frame: CGRect(x: 0,y: 0,width: 600,height: 760))
    let window = NSWindow(contentRect: pdf.frame,styleMask: [.titled],backing: .buffered,defer: false)
    window.isReleasedWhenClosed = false; window.contentView = pdf
    pdf.document = document; pdf.scaleFactor = 1; pdf.go(to: page); pdf.layoutDocumentView()
    let model = PDFTextPropertiesModel()
    let inline = PDFInlineTextEditor(snapshot: session.snapshot,page: page,pdfView: pdf,model: model)
    expect(inline.isAttached && model.active,"editor and inspector are active directly on the PDF page")
    expect(pdf.clipsToBounds && inline.editor.clipsToBounds,"PDF editor clips page, text, and overlays to the viewport")
    expect(!inline.editor.drawsBackground,"in-place editor has no white field background")
    expect(inline.quad().count == 4,"selected frame has a real quadrilateral")
    let beta = (inline.editor.string as NSString).range(of: "Beta")
    inline.editor.setSelectedRange(beta)
    inline.apply(.size(24)); inline.apply(.color(.red)); inline.apply(.bold(true))
    let before = inline.attributedText.attributes(at: 0,effectiveRange: nil)
    let selected = inline.attributedText.attributes(at: beta.location,effectiveRange: nil)
    expect((before[.font] as! NSFont).pointSize == 14,"partial formatting leaves neighboring text unchanged")
    expect((selected[.font] as! NSFont).pointSize == 24,"partial selection receives the requested size")
    expect(NSFontManager.shared.traits(of: selected[.font] as! NSFont).contains(.boldFontMask),"partial selection receives bold")
    let numeric = NSTextField(frame: CGRect(x: 5,y: 5,width: 80,height: 24)); pdf.addSubview(numeric)
    _ = window.makeFirstResponder(numeric)
    let numberResponder = window.firstResponder
    let textBeforeGeometry = inline.editor.string
    inline.apply(.angle(12))
    expect(window.firstResponder === numberResponder,"geometry input must not steal focus from its text field")
    expect(inline.editor.string == textBeforeGeometry,"geometry controls must not replace selected document text")
    inline.apply(.angle(0)); numeric.removeFromSuperview()
    inline.editor.setSelectedRange(NSRange(location: 0,length: 0)); inline.apply(.width(300))
    let originalPose = inline.geometry
    inline.beginDrag(.move,at: CGPoint(x: 72,y: 700)); inline.drag(to: CGPoint(x: 102,y: 680)); inline.endDrag()
    expect(abs(inline.geometry.origin.x-originalPose.origin.x-30) < 0.001,"move handle changes PDF coordinates")
    let center = inline.geometry.point(x: inline.width/2,y: inline.ascent-inline.height/2)
    inline.beginDrag(.rotate,at: CGPoint(x: center.x+100,y: center.y)); inline.drag(to: CGPoint(x: center.x+cos(.pi/6)*100,y: center.y+sin(.pi/6)*100)); inline.endDrag()
    expect(abs(inline.geometry.angle-originalPose.angle - .pi/6) < 0.001,"rotation handle changes the text block angle")
    let widthBefore = inline.width
    let first = inline.geometry.point(x: inline.width,y: 0)
    inline.beginDrag(.width(1),at: first); inline.drag(to: inline.geometry.point(x: inline.width+40,y: 0)); inline.endDrag()
    expect(abs(inline.width-widthBefore-40) < 0.001,"side handle stretches the field without changing font size")
    expect((inline.attributedText.attribute(.font,at: 0,effectiveRange: nil) as! NSFont).pointSize == 14,"field stretching preserves font size")
    let edited = try session.applying(text: inline.attributedText.string,fontSize: 14,color: .black,width: inline.width,richText: inline.attributedText,geometry: inline.geometry)
    let reload = try PDFSourceSession.editing(data: edited,pageIndex: 0,point: session.resultingPoint!)
    expect(reload.snapshot.text == "Alpha Beta Gamma","inline edits preserve complete searchable text")
    expect(abs(reload.snapshot.geometry.angle - .pi/6) < 0.001,"rotation persists in the original PDF content")
    let reloadedBeta = (reload.snapshot.attributedText.string as NSString).range(of: "Beta")
    let reloadedFont = reload.snapshot.attributedText.attribute(.font,at: reloadedBeta.location,effectiveRange: nil) as! NSFont
    expect(abs(reloadedFont.pointSize-24) < 0.01,"partial font size persists after saving")
    inline.cancel(); expect(!inline.isAttached && !model.active,"cancel removes the in-place editor and its temporary mask")
    window.close()
    print("PASS: inline text editor, block catalog, partial formatting, move, rotation, field stretching, source save, and cleanup")
}

@MainActor
private func runRibbonFeatureChecks(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("FEATURE CHECK FAILED: "+message) } }
    let document = PDFDocument()
    let first = PDFRasterizer.textPage("Hello annotation tools\nSecond line for markup")!
    document.insert(first,at: 0); document.insert(PDFRasterizer.textPage("Second page")!,at: 1)
    let url = root.appendingPathComponent("ribbon-features.pdf"); expect(document.write(to: url),"create searchable source page")
    let manager = DocumentManager(); manager.open(url); let item = manager.selected!,page = item.document.page(at: 0)!
    let textOnly = try PDFSourceTextReader.pages(data: Data(contentsOf: url),indices: [0])
    expect(textOnly[0].contains("Hello annotation tools"),"embedded-text reader preserves source text without Vision")
    expect(manager.embeddedText(in: item,indices: [0])?.contains("Hello annotation tools") == true,"document text commands use the existing text layer")
    let pdf = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 800))
    let featureWindow = NSWindow(contentRect: pdf.frame,styleMask: [.titled],backing: .buffered,defer: false)
    featureWindow.isReleasedWhenClosed = false; featureWindow.contentView = pdf
    defer { featureWindow.close() }
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(pdf); coordinator.update(pdf)
    pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded(); pdf.go(to: page)
    manager.annotationColor = .purple; manager.annotationOpacity = 0.37
    for (command,type) in [(ViewerCommand.highlight,"Highlight"),(.underline,"Underline"),(.strike,"StrikeOut")] {
        pdf.setCurrentSelection(page.selection(for: page.bounds(for: .cropBox)),animate: false)
        coordinator.checkCommand(command,view: pdf)
        let markup = page.annotations.filter { $0.type == type }
        if markup.isEmpty { print("MARKUP DIAGNOSTIC",page.string ?? "nil",pdf.currentSelection?.string ?? "nil",pdf.document === item.document); fflush(nil) }
        expect(!markup.isEmpty,"working "+type); expect(abs(Double(AnnotationMetadata.alpha(of: markup[0]))-0.37) < 0.01,"markup uses selected opacity")
        expect(AnnotationMetadata.group(of: markup[0]) != nil,"multiline markup is grouped for property changes")
    }
    for tool in [PDFTool.rectangle,.ellipse,.line,.arrow,.cloud,.pencil] {
        let count = page.annotations.count
        pdf.checkDraw(page: page,start: CGPoint(x: 70,y: 400),end: CGPoint(x: 180,y: 480),tool: tool)
        expect(page.annotations.count == count+1,"draw tool creates a real annotation: "+String(describing: tool))
        if tool == .pencil || tool == .cloud { expect(!(page.annotations.last!.paths ?? []).isEmpty,"ink annotation has vector paths") }
    }
    let stamp = PDFAnnotation(bounds: CGRect(x: 200,y: 250,width: 180,height: 44),forType: .freeText,withProperties: nil)
    stamp.contents = "APPROVED"; stamp.font = .boldSystemFont(ofSize: 18); stamp.fontColor = .red; stamp.color = .clear
    let border = PDFBorder(); border.lineWidth = 2; stamp.border = border; page.addAnnotation(stamp)
    let note = PDFAnnotation(bounds: CGRect(x: 240,y: 220,width: 24,height: 24),forType: .text,withProperties: nil); note.contents = "Persistent note"; note.iconType = .note; page.addAnnotation(note)
    let link = PDFAnnotation(bounds: CGRect(x: 250,y: 180,width: 80,height: 20),forType: .link,withProperties: nil); link.action = PDFActionURL(url: URL(string: "https://github.com/Davud77/BotPlus-PDF-Editor")!); page.addAnnotation(link)
    for (offset,tool) in [PDFTool.formText,.formCheckbox,.formRadio,.formChoice,.formButton].enumerated() {
        let widget = PDFWidgetFactory.make(tool,bounds: CGRect(x: 300,y: 400-offset*36,width: 180,height: 28),name: "Field\(offset)",choices: ["Yes","No"])
        if tool == .formText { widget.widgetStringValue = "Filled text" }
        if tool == .formCheckbox { widget.buttonWidgetState = .onState }
        page.addAnnotation(widget)
    }
    manager.addBookmark(title: "Zebra",page: page); manager.addBookmark(title: "Alpha",page: item.document.page(at: 1)!)
    manager.addBookmark(title: "Alpha",page: item.document.page(at: 1)!)
    let initialOutline = manager.bookmarkRoot()!; coordinator.sortBookmarks(initialOutline); coordinator.mergeBookmarks(initialOutline,document: item.document)
    expect(initialOutline.numberOfChildren == 2 && initialOutline.child(at: 0)?.label == "Alpha","bookmarks sort and merge duplicates")
    manager.selectedOutline = nil
    let beforeUndo = item.pageCount
    item.historyDate = .distantPast
    coordinator.checkCommand(.duplicatePageAt(1),view: pdf)
    manager.undoDocument(redo: false); expect(item.pageCount == beforeUndo,"undo restores document pages")
    manager.undoDocument(redo: true); expect(item.pageCount == beforeUndo+1,"redo restores page operation")
    manager.undoDocument(redo: false); coordinator.update(pdf)
    coordinator.createTOC(item: item,view: pdf)
    expect(item.pageCount == 3 && (item.document.page(at: 0)?.string ?? "").contains("СОДЕРЖАНИЕ"),"TOC creates a searchable PDF page")
    expect(ThumbnailGestureView.zoom(0.5,delta: 0.2) > 0.5,"pinch-out increases thumbnail size")
    expect(ThumbnailGestureView.zoom(0.5,delta: -0.2) < 0.5,"pinch-in decreases thumbnail size")
    expect(ThumbnailGestureView.zoom(0.99,delta: 2) == 1 && ThumbnailGestureView.zoom(0.01,delta: -2) == 0,"thumbnail gesture range is clamped")
    let gesture = ThumbnailGestureView(frame: .zero); gesture.manager = manager
    manager.thumbnailZoom = 0.5
    gesture.adjust(0.1); gesture.adjust(0.1)
    gesture.flush()
    expect(abs(manager.thumbnailZoom-0.65) < 0.00001,"thumbnail gesture deltas coalesce without a focused thumbnail")
    let cache = PDFThumbnailCache(),key = UUID()
    let one = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 100,ratio: 792/612)
    let two = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 101,ratio: 792/612)
    let enlarged = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 600,ratio: 792/612,interactive: true)
    expect(one === two && two === enlarged && cache.renderCount == 1,"thumbnail gestures reuse the current raster through the whole width range")
    _ = cache.image(page: page,documentID: key,index: 0,revision: 2,width: 100,ratio: 792/612)
    expect(cache.renderCount == 2,"document edits invalidate thumbnail content")
    _ = cache.image(page: page,documentID: key,index: 0,revision: 2,width: 600,ratio: 792/612)
    expect(cache.renderCount == 3,"thumbnail detail upgrades after interactive zoom")
    let panel = PanelWorkspaceModel(); panel.setWidth(380,for: .thumbnails); panel.select(.thumbnails); panel.select(.bookmarks)
    expect(panel.configuration(for: .bookmarks).width == 380,"switching left panels keeps the dock width")
    let output = root.appendingPathComponent("ribbon-features-saved.pdf"); AnnotationMetadata.prepareForSave(item.document)
    expect(item.document.write(to: output),"save all feature annotations")
    let reopened = PDFDocument(url: output)!; AnnotationMetadata.restore(reopened)
    let annotations = (0..<reopened.pageCount).flatMap { reopened.page(at: $0)?.annotations ?? [] }
    for type in ["Text","Link","Ink","Circle","Square","Highlight","Underline","StrikeOut","Widget"] { expect(annotations.contains { $0.type == type },"persist "+type) }
    expect(annotations.contains { $0.contents == "APPROVED" },"persist engineering text stamp")
    expect(annotations.contains { $0.fieldName == "Field0" && $0.widgetStringValue == "Filled text" },"persist form input")
    expect(reopened.outlineRoot?.numberOfChildren == 2,"persist outline hierarchy")
    let image = NSImage(size: CGSize(width: 16,height: 16),flipped: false) { rect in NSColor.red.setFill(); NSBezierPath(rect: rect).fill(); return true }
    let imageData = try PDFSourceSession.insertingImage(data: item.document.dataRepresentation()!,pageIndex: 1,image: image.cgImage(forProposedRect: nil,context: nil,hints: nil)!,bounds: CGRect(x: 80,y: 60,width: 100,height: 100))
    let imageInfo = try PDFSourceSession.objectInfo(data: imageData,pageIndex: 1,point: CGPoint(x: 120,y: 100))
    expect(imageInfo?.kind == "image" && imageInfo?.pixelSize?.width == 16,"inserted image is a real PDF content object")
    let imageDoc = PDFDocument(data: imageData)!
    expect((imageDoc.page(at: 1)?.string ?? "").contains("Hello annotation"),"image insertion preserves neighboring text")
    expect(imageDoc.dataRepresentation() != nil,"inserted image survives PDFKit persistence")
    coordinator.detach()
    print("PASS: colored markup, vector drawings, notes, stamps, links, forms, bookmarks/TOC, fixed dock widths, and PDF image insertion")
}
