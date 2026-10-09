

extension PDFViewerView {
    fileprivate func checkMagnify(_ delta: CGFloat, anchor: CGPoint) { applyMagnification(delta, at: anchor) }
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
        coordinator.detach(); pdf.stopEventMonitoring(); window.close()
        print("PASS: rulers, two-finger scrolling, anchored gesture zoom, live text, opacity and callout persistence, drag/resize/delete, page edits, panel invariants")
    }
}
