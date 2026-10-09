import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

private enum BotPlusBrand {
    static let name = "BotPlus PDF Editor"
    static let version = "1.0.0"
    static let copyright = "Copyright © 2026 BotPlus. All rights reserved."
    static let primaryWebsite = URL(string: "https://botplus.ru")!
    static let alternateWebsite = URL(string: "https://botplus.io")!
}

// Single-file macOS PDF workspace. Replace the template app entry point with this file.
// When App Sandbox is enabled, grant User Selected File Read/Write in Signing & Capabilities.

private struct Bilingual {
    let en: String
    let ru: String
    func value(_ language: AppLanguage) -> String { language == .ru ? ru : en }
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en
    var id: String { rawValue }
    var displayName: String { self == .ru ? "Русский" : "English" }
}

private enum Palette {
    static let ribbon = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let raised = Color(red: 0.205, green: 0.205, blue: 0.205)
    static let separator = Color(red: 0.25, green: 0.25, blue: 0.25)
    static let selected = Color(red: 0.29, green: 0.29, blue: 0.29)
    static let file = Color(red: 0.65, green: 0.18, blue: 0.20)
    static let text = Color(red: 0.88, green: 0.88, blue: 0.88)
    static let muted = Color(red: 0.68, green: 0.68, blue: 0.68)
    static let accent = Color(red: 0.30, green: 0.62, blue: 0.90)
}

private enum RibbonTab: CaseIterable, Identifiable {
    case file, home, view, comment, protect, form, organize, convert, mailings, review, accessibility, bookmarks, help
    var id: Self { self }
    var title: Bilingual {
        switch self {
        case .file: Bilingual(en: "File", ru: "Файл")
        case .home: Bilingual(en: "Home", ru: "Главная")
        case .view: Bilingual(en: "View", ru: "Вид")
        case .comment: Bilingual(en: "Comment", ru: "Комментарий")
        case .protect: Bilingual(en: "Protect", ru: "Защита")
        case .form: Bilingual(en: "Form", ru: "Форма")
        case .organize: Bilingual(en: "Organize", ru: "Организация")
        case .convert: Bilingual(en: "Convert", ru: "Преобразование")
        case .mailings: Bilingual(en: "Mailings", ru: "Рассылки")
        case .review: Bilingual(en: "Review", ru: "Рецензирование")
        case .accessibility: Bilingual(en: "Accessibility", ru: "Спец. возможности")
        case .bookmarks: Bilingual(en: "Bookmarks", ru: "Закладки")
        case .help: Bilingual(en: "Help", ru: "Помощь")
        }
    }
}

private enum PDFTool: Equatable {
    case hand, textSelection, selectComments, highlight, typewriter, rectangle, line, arrow, callout
    var title: Bilingual {
        switch self {
        case .hand: Bilingual(en: "Hand", ru: "Рука")
        case .textSelection: Bilingual(en: "Text Selection", ru: "Выделить текст")
        case .selectComments: Bilingual(en: "Select Comments", ru: "Выделить комментарии")
        case .highlight: Bilingual(en: "Highlight Text", ru: "Подсветить текст")
        case .typewriter: Bilingual(en: "Typewriter", ru: "Печатная машинка")
        case .rectangle: Bilingual(en: "Rectangle", ru: "Прямоугольник")
        case .line: Bilingual(en: "Line", ru: "Линия")
        case .arrow: Bilingual(en: "Arrow", ru: "Стрелка")
        case .callout: Bilingual(en: "Callout", ru: "Выноска")
        }
    }
}

private enum PageLayout: CaseIterable, Identifiable {
    case single, continuous, spread
    var id: Self { self }
    var title: Bilingual {
        switch self {
        case .single: Bilingual(en: "Single Page", ru: "Одна страница")
        case .continuous: Bilingual(en: "Continuous", ru: "Непрерывно")
        case .spread: Bilingual(en: "Two Pages", ru: "Две страницы")
        }
    }
    var pdfMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .continuous: .singlePageContinuous
        case .spread: .twoUpContinuous
        }
    }
}

private enum WorkspacePanel: String, CaseIterable, Identifiable, Codable {
    case thumbnails, bookmarks, properties, comments, layers, attachments
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .thumbnails: Bilingual(en: "Thumbnails", ru: "Миниатюры страниц")
        case .bookmarks: Bilingual(en: "Bookmarks", ru: "Закладки")
        case .properties: Bilingual(en: "Properties", ru: "Свойства")
        case .comments: Bilingual(en: "Comments / Annotations", ru: "Комментарии")
        case .layers: Bilingual(en: "Layers", ru: "Слои")
        case .attachments: Bilingual(en: "Attachments", ru: "Вложения")
        }
    }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .bookmarks: "bookmark"
        case .properties: "slider.horizontal.3"
        case .comments: "text.bubble"
        case .layers: "square.3.layers.3d"
        case .attachments: "paperclip"
        }
    }
}

private enum PanelDock: String, Codable, CaseIterable, Identifiable {
    case left, right, floating
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .left: Bilingual(en: "Dock Left", ru: "Закрепить слева")
        case .right: Bilingual(en: "Dock Right", ru: "Закрепить справа")
        case .floating: Bilingual(en: "Float", ru: "Плавающее окно")
        }
    }
}

private struct PanelConfiguration: Codable, Equatable {
    var isVisible: Bool
    var dock: PanelDock
    var width: Double
    var isPinned = true
    var isExpanded = true
    var lastDock: PanelDock = .left
    enum CodingKeys: String, CodingKey { case isVisible, dock, width, isPinned, isExpanded, lastDock }
    init(isVisible: Bool, dock: PanelDock, width: Double) {
        self.isVisible = isVisible; self.dock = dock; self.width = min(600, max(200, width))
        lastDock = dock == .floating ? .left : dock
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try v.decode(Bool.self, forKey: .isVisible)
        dock = try v.decode(PanelDock.self, forKey: .dock)
        width = min(600, max(200, try v.decode(Double.self, forKey: .width)))
        isPinned = try v.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        isExpanded = try v.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        lastDock = try v.decodeIfPresent(PanelDock.self, forKey: .lastDock) ?? (dock == .floating ? .left : dock)
    }
}
private enum RulerUnit: String, CaseIterable, Identifiable {
    case points = "pt", millimeters = "mm", inches = "in"
    var id: String { rawValue }
    var pointsPerUnit: CGFloat { switch self { case .points: 1; case .millimeters: 72 / 25.4; case .inches: 72 } }
}
private struct RulerMetrics: Equatable {
    var horizontalOrigin: CGFloat = 0
    var horizontalPointsPerPixel: CGFloat = 1
    var verticalOrigin: CGFloat = 0
    var verticalPointsPerPixel: CGFloat = -1
    var valid = false
}
@MainActor
private final class ViewportState: ObservableObject {
    @Published var metrics = RulerMetrics()
    @Published var cursorViewport: CGPoint?
    @Published var cursorPage: CGPoint?
}

@MainActor
private final class PanelWorkspaceModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var configurations: [WorkspacePanel: PanelConfiguration]
    @Published private(set) var activeLeft: WorkspacePanel = .thumbnails
    @Published private(set) var activeRight: WorkspacePanel = .properties
    private var floatingWindows: [WorkspacePanel: NSPanel] = [:]
    private var suppressedClose = Set<ObjectIdentifier>()
    private var resizeStarts: [WorkspacePanel: CGFloat] = [:]
    private let persistenceKey = "BotPlusPDFEditor.panelConfigurations.v1"
    override init() {
        let defaults: [WorkspacePanel: PanelConfiguration] = [
            .thumbnails: .init(isVisible: true, dock: .left, width: 230),
            .bookmarks: .init(isVisible: true, dock: .left, width: 240),
            .properties: .init(isVisible: true, dock: .right, width: 250),
            .comments: .init(isVisible: false, dock: .right, width: 260),
            .layers: .init(isVisible: false, dock: .left, width: 220),
            .attachments: .init(isVisible: false, dock: .right, width: 220)
        ]
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([WorkspacePanel: PanelConfiguration].self, from: data) {
            configurations = defaults.merging(saved) { _, value in value }
        } else { configurations = defaults }
        super.init()
        if let panel = activePanel(on: .left) { select(panel) }
        if let panel = activePanel(on: .right) { select(panel) }
    }
    func configuration(for panel: WorkspacePanel) -> PanelConfiguration {
        configurations[panel] ?? .init(isVisible: false, dock: .left, width: 230)
    }
    func panels(on side: PanelDock) -> [WorkspacePanel] {
        WorkspacePanel.allCases.filter { configuration(for: $0).dock == side && configuration(for: $0).isVisible }
    }
    func activePanel(on side: PanelDock) -> WorkspacePanel? {
        let candidates = panels(on: side).filter { configuration(for: $0).isExpanded }
        let preferred = side == .left ? activeLeft : activeRight
        return candidates.contains(preferred) ? preferred : candidates.first
    }
    func select(_ panel: WorkspacePanel) {
        let config = configuration(for: panel)
        if config.dock == .left { activeLeft = panel }
        if config.dock == .right { activeRight = panel }
        var next = configurations
        for candidate in WorkspacePanel.allCases where configuration(for: candidate).dock == config.dock && config.dock != .floating {
            next[candidate]?.isExpanded = candidate == panel
        }
        next[panel]?.isVisible = true; next[panel]?.isExpanded = true
        publish(next)
    }
    func toggleDrawer(_ panel: WorkspacePanel) {
        let config = configuration(for: panel)
        if config.dock == .floating { floatingWindows[panel]?.makeKeyAndOrderFront(nil); return }
        if activePanel(on: config.dock) == panel && config.isExpanded {
            update(panel) { $0.isExpanded = false }
        } else { select(panel) }
    }
    func collapseAutoHiddenPanels() {
        var next = configurations
        for panel in WorkspacePanel.allCases {
            if var config = next[panel], !config.isPinned, config.dock != .floating {
                config.isExpanded = false; next[panel] = config
            }
        }
        publish(next)
    }
    func setPinned(_ pinned: Bool, for panel: WorkspacePanel) { update(panel) { $0.isPinned = pinned; $0.isExpanded = true } }
    func setVisible(_ visible: Bool, for panel: WorkspacePanel) {
        update(panel) { $0.isVisible = visible; $0.isExpanded = visible }
        if visible { select(panel) }
    }
    func setDock(_ dock: PanelDock, for panel: WorkspacePanel) {
        update(panel) {
            if dock == .floating && $0.dock != .floating { $0.lastDock = $0.dock }
            if dock != .floating { $0.lastDock = dock }
            $0.dock = dock; $0.isExpanded = true; $0.isVisible = true
        }
        select(panel)
    }
    func setWidth(_ width: CGFloat, for panel: WorkspacePanel) { update(panel) { $0.width = Double(min(600, max(200, width))) } }
    func resize(_ panel: WorkspacePanel, translation: CGFloat, initialWidth: CGFloat? = nil) {
        let start = resizeStarts[panel] ?? initialWidth ?? CGFloat(configuration(for: panel).width)
        resizeStarts[panel] = start
        setWidth(start + translation, for: panel)
    }
    func endResize(_ panel: WorkspacePanel) { resizeStarts[panel] = nil }
    private func update(_ panel: WorkspacePanel, change: (inout PanelConfiguration) -> Void) {
        var next = configurations; var config = configuration(for: panel)
        change(&config); next[panel] = config; publish(next)
    }
    private func publish(_ next: [WorkspacePanel: PanelConfiguration]) {
        guard next != configurations else { return }
        configurations = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: persistenceKey) }
    }
    func synchronizeFloatingWindows(manager: DocumentManager) {
        for panel in WorkspacePanel.allCases {
            let config = configuration(for: panel)
            if config.isVisible && config.dock == .floating {
                if let window = floatingWindows[panel] { window.title = manager.text(panel.title); continue }
                let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: config.width, height: 420),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
                window.title = manager.text(panel.title)
                window.isReleasedWhenClosed = false; window.isFloatingPanel = true; window.level = .floating
                window.minSize = NSSize(width: 200, height: 180); window.maxSize = NSSize(width: 600, height: 1600)
                window.delegate = self
                window.contentView = NSHostingView(rootView: FloatingPanelContents(panel: panel, panels: self, manager: manager).preferredColorScheme(.dark))
                window.setFrameAutosaveName("BotPlusPDFEditor.\(panel.rawValue).floating")
                floatingWindows[panel] = window; window.makeKeyAndOrderFront(nil)
            } else if let window = floatingWindows[panel] {
                suppressedClose.insert(ObjectIdentifier(window)); floatingWindows[panel] = nil; window.close()
            }
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if suppressedClose.remove(ObjectIdentifier(window)) != nil { return }
        guard let panel = floatingWindows.first(where: { $0.value === window })?.key else { return }
        floatingWindows[panel] = nil; setDock(configuration(for: panel).lastDock, for: panel)
    }
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = floatingWindows.first(where: { $0.value === window })?.key else { return }
        setWidth(window.frame.width, for: panel)
    }
}

@MainActor
private final class PDFDocumentItem: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: URL
    let document: PDFDocument
    @Published var pageIndex = 0
    @Published var zoom: CGFloat = 1

    init(url: URL, document: PDFDocument) { self.url = url; self.document = document }
    var filename: String { url.lastPathComponent }
    var pageCount: Int { document.pageCount }
}

@MainActor
private final class DocumentManager: ObservableObject {
    let panels = PanelWorkspaceModel()
    @Published private(set) var documents: [PDFDocumentItem] = []
    @Published var selectedID: UUID?
    @Published var language: AppLanguage = .ru
    @Published var tab: RibbonTab = .home
    @Published var tool: PDFTool = .hand
    @Published var layout: PageLayout = .continuous
    @Published var rulersVisible = false
    @Published var rulerUnit: RulerUnit = .millimeters
    let viewport = ViewportState()
    var cursorViewport: CGPoint? { get { viewport.cursorViewport } set { viewport.cursorViewport = newValue } }
    var cursorPage: CGPoint? { get { viewport.cursorPage } set { viewport.cursorPage = newValue } }
    @Published var annotationColor: Color = .red
    @Published var annotationStrokeWidth: Double = 2
    @Published var annotationOpacity: Double = 1
    @Published var textFontSize: Double = 18
    @Published var textBorderEnabled = true
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var pageText = "1"
    @Published var searchText = ""
    @Published var notice: String?
    @Published var commandIndex = 0
    @Published var command: ViewerCommand = .refresh
    var rulerMetrics: RulerMetrics { get { viewport.metrics } set { viewport.metrics = newValue } }
    @Published var isAboutPresented = false

    var selected: PDFDocumentItem? { documents.first(where: { $0.id == selectedID }) }
    var title: String {
        guard let selected else { return BotPlusBrand.name }
        return "\(selected.filename) - \(BotPlusBrand.name)"
    }
    func text(_ value: Bilingual) -> String { value.value(language) }
    func say(_ en: String, _ ru: String) { notice = language == .ru ? ru : en }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { open(url) }
    }

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { say("Please choose a PDF file.", "Выберите файл PDF."); return }
        if let existing = documents.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            select(existing.id); return
        }
        guard let document = PDFDocument(url: url) else { say("The PDF could not be opened.", "Не удалось открыть PDF-файл."); return }
        AnnotationMetadata.restore(document)
        let item = PDFDocumentItem(url: url, document: document)
        documents.append(item)
        select(item.id)
    }

    func select(_ id: UUID) {
        selectedID = id
        pageText = String((documents.first(where: { $0.id == id })?.pageIndex ?? 0) + 1)
        send(.refresh)
    }

    func close(_ id: UUID) {
        let wasSelected = selectedID == id
        documents.removeAll(where: { $0.id == id })
        if wasSelected {
            selectedID = documents.last?.id
            pageText = String((selected?.pageIndex ?? 0) + 1)
            send(.refresh)
        }
    }

    func send(_ next: ViewerCommand) { command = next; commandIndex &+= 1 }
    func navigate(to index: Int) {
        guard let selected, selected.pageCount > 0 else { return }
        let safeIndex = min(max(index, 0), selected.pageCount - 1)
        selected.pageIndex = safeIndex
        pageText = String(safeIndex + 1)
        send(.page(safeIndex))
    }
    func commitPageField() {
        guard let number = Int(pageText) else { pageText = String((selected?.pageIndex ?? 0) + 1); return }
        navigate(to: number - 1)
    }

    func saveDocument() {
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        AnnotationMetadata.prepareForSave(selected.document)
        let saved = selected.document.write(to: selected.url)
        AnnotationMetadata.removeContainers(selected.document)
        guard saved else { say("Could not save the PDF.", "Не удалось сохранить PDF-файл."); return }
    }
    func saveDocumentAs() {
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = selected.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AnnotationMetadata.prepareForSave(selected.document)
        let saved = selected.document.write(to: url)
        AnnotationMetadata.removeContainers(selected.document)
        guard saved else { say("Could not save the PDF.", "Не удалось сохранить PDF-файл."); return }
        selected.url = url
        send(.refresh)
    }
    func printDocument() {
        guard selected?.document != nil else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        send(.print)
    }
    func perform(_ action: RibbonAction) {
        if selected == nil {
            switch action {
            case .open, .settings, .toggleLanguage, .toggleRulers, .panels, .languagePicker, .about, .development: break
            default: say("Open a PDF first.", "Сначала откройте PDF-файл."); return
            }
        }
        switch action {
        case .open: openPanel()
        case .save: saveDocument()
        case .saveAs: saveDocumentAs()
        case .close: if let selected { close(selected.id) }
        case .print: printDocument()
        case .settings: tab = .help
        case .tool(let next): tool = next; send(.refresh)
        case .layout(let next): layout = next; send(.refresh)
        case .zoomIn: send(.zoomIn)
        case .zoomOut: send(.zoomOut)
        case .actualSize: send(.actualSize)
        case .fitPage: send(.fitPage)
        case .fitWidth: send(.fitWidth)
        case .rotateLeft: send(.rotate(-90))
        case .rotateRight: send(.rotate(90))
        case .previous: navigate(to: (selected?.pageIndex ?? 0) - 1)
        case .next: navigate(to: (selected?.pageIndex ?? 0) + 1)
        case .first: navigate(to: 0)
        case .last: navigate(to: (selected?.pageCount ?? 1) - 1)
        case .highlight: send(.highlight)
        case .underline: send(.underline)
        case .insertBlankPage: send(.insertBlankPage)
        case .deletePage: send(.deletePage)
        case .duplicatePage: send(.duplicatePage)
        case .toggleLanguage: language = language == .ru ? .en : .ru
        case .toggleRulers: rulersVisible.toggle()
        case .panels: break
        case .languagePicker: break
        case .about: isAboutPresented = true
        case .development: say("Feature in development", "Функция в разработке")
        }
    }
}

@MainActor
private enum AnnotationMetadata {
    struct Record: Codable {
        var id = UUID().uuidString
        var opacity: Double
        var group: String?
    }
    private struct Entry: Codable {
        let index: Int
        let subtype: String
        let center: CGPoint
        let record: Record
    }
    private final class Box: NSObject {
        var record: Record
        init(_ record: Record) { self.record = record }
    }
    private static let records = NSMapTable<PDFAnnotation, Box>.weakToStrongObjects()
    private static let prefix = "BotPlus PDF Editor metadata v1:"
    static func alpha(of annotation: PDFAnnotation) -> CGFloat {
        if let record = records.object(forKey: annotation)?.record { return CGFloat(record.opacity) }
        return annotation.color.alphaComponent
    }
    static func group(of annotation: PDFAnnotation) -> String? { records.object(forKey: annotation)?.record.group }
    static func setOpacity(_ opacity: Double, on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: opacity)
        record.opacity = min(1, max(0, opacity)); records.setObject(Box(record), forKey: annotation)
    }
    static func setGroup(_ group: String, on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.group = group; records.setObject(Box(record), forKey: annotation)
    }
    static func isContainer(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == "Text" && (annotation.contents ?? "").hasPrefix(prefix)
    }
    // PDFKit's writer omits custom dictionary keys. A hidden, non-printing Text
    // annotation carries editor settings while standard visible annotations stay editable.
    static func prepareForSave(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isContainer(annotation) { page.removeAnnotation(annotation) }
            let entries = page.annotations.enumerated().compactMap { index, annotation -> Entry? in
                guard let record = records.object(forKey: annotation)?.record else { return nil }
                return Entry(index: index, subtype: annotation.type ?? "", center: CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), record: record)
            }
            guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { continue }
            let marker = PDFAnnotation(bounds: CGRect(x: page.bounds(for: .cropBox).minX, y: page.bounds(for: .cropBox).minY, width: 1, height: 1), forType: .text, withProperties: nil)
            marker.contents = prefix + data.base64EncodedString()
            marker.shouldDisplay = false; marker.shouldPrint = false
            marker.userName = BotPlusBrand.name
            page.addAnnotation(marker)
        }
    }
    static func removeContainers(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isContainer(annotation) { page.removeAnnotation(annotation) }
        }
    }
    static func restore(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let annotations = page.annotations.filter { !isContainer($0) }
            let containers = page.annotations.filter(isContainer)
            var used = Set<Int>()
            for marker in containers {
                guard let contents = marker.contents,
                      let data = Data(base64Encoded: String(contents.dropFirst(prefix.count))),
                      let entries = try? JSONDecoder().decode([Entry].self, from: data) else { continue }
                for entry in entries {
                    func matches(_ i: Int) -> Bool {
                        guard annotations.indices.contains(i), !used.contains(i), annotations[i].type == entry.subtype else { return false }
                        let bounds = annotations[i].bounds
                        return hypot(bounds.midX - entry.center.x, bounds.midY - entry.center.y) < 8
                    }
                    guard let match = matches(entry.index) ? entry.index : annotations.indices.first(where: matches) else { continue }
                    let annotation = annotations[match]; used.insert(match)
                    records.setObject(Box(entry.record), forKey: annotation)
                    annotation.removeValue(forAnnotationKey: .appearanceDictionary)
                    if annotation.type == "FreeText" {
                        annotation.color = .clear
                        annotation.fontColor = (annotation.fontColor ?? .black).withAlphaComponent(CGFloat(entry.record.opacity))
                    } else { annotation.color = annotation.color.withAlphaComponent(CGFloat(entry.record.opacity)) }
                }
                page.removeAnnotation(marker)
            }
        }
    }
    static func copy(from source: PDFPage, to destination: PDFPage) {
        let old = source.annotations.filter { !isContainer($0) }
        for marker in destination.annotations where isContainer(marker) { destination.removeAnnotation(marker) }
        let new = destination.annotations
        var groups: [String: String] = [:]
        for (original, duplicate) in zip(old, new) {
            guard var record = records.object(forKey: original)?.record else { continue }
            record.id = UUID().uuidString
            if let group = record.group {
                let copiedGroup = groups[group] ?? UUID().uuidString
                groups[group] = copiedGroup; record.group = copiedGroup
            }
            records.setObject(Box(record), forKey: duplicate)
        }
    }
}

private enum ViewerCommand: Equatable {
    case refresh, zoomIn, zoomOut, actualSize, fitPage, fitWidth, rotate(Int), page(Int), highlight, underline, insertBlankPage, deletePage, duplicatePage, print, applyAnnotationStyle
    case setZoom(CGFloat)
}

private enum RibbonAction {
    case open, save, saveAs, close, print, settings
    case tool(PDFTool), layout(PageLayout), zoomIn, zoomOut, actualSize, fitPage, fitWidth
    case rotateLeft, rotateRight, previous, next, first, last, highlight, toggleLanguage, toggleRulers
    case panels, languagePicker, about, underline, insertBlankPage, deletePage, duplicatePage, development
}

private struct RibbonCommand: Identifiable {
    let id: String
    let title: Bilingual
    let symbol: String
    let action: RibbonAction
    init(_ id: String, _ en: String, _ ru: String, _ symbol: String, _ action: RibbonAction = .development) {
        self.id = id; title = Bilingual(en: en, ru: ru); self.symbol = symbol; self.action = action
    }
}

private struct RibbonGroupSpec: Identifiable {
    let id: String
    let title: Bilingual
    let commands: [RibbonCommand]
    init(_ id: String, _ en: String, _ ru: String, _ commands: [RibbonCommand]) {
        self.id = id; title = Bilingual(en: en, ru: ru); self.commands = commands
    }
}

@main
struct BotPlusPDFEditorApp: App {
    var body: some Scene {
        WindowGroup(BotPlusBrand.name) {
            ContentView().frame(minWidth: 1060, minHeight: 700).preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open PDF…") { NotificationCenter.default.post(name: .requestOpenPDF, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

private extension Notification.Name {
    static let requestOpenPDF = Notification.Name("BotPlusPDFEditor.requestOpenPDF")
}

private struct ContentView: View {
    @StateObject private var manager = DocumentManager()

    var body: some View {
        VStack(spacing: 0) {
            QuickBar(manager: manager)
            RibbonView(manager: manager)
            DocumentTabs(manager: manager)
            WorkspaceArea(manager: manager).onDrop(of: [UTType.fileURL], isTargeted: nil, perform: receivePDFs)
            StatusBar(manager: manager)
        }
        .background(Palette.ribbon)
        .background(WindowTitleSynchronizer(title: manager.title).frame(width: 0, height: 0))
        .background(WindowChromeConfigurator().frame(width: 0, height: 0))
        .foregroundStyle(Palette.text)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenPDF)) { _ in manager.openPanel() }
        .onReceive(manager.panels.$configurations) { _ in
            Task { @MainActor in
                await Task.yield()
                manager.panels.synchronizeFloatingWindows(manager: manager)
            }
        }
        .onChange(of: manager.language) { _, _ in manager.panels.synchronizeFloatingWindows(manager: manager) }
        .sheet(isPresented: $manager.isAboutPresented) { AboutDialog(manager: manager) }
        .alert(manager.language == .ru ? "Сообщение" : "Notice", isPresented: Binding(
            get: { manager.notice != nil }, set: { if !$0 { manager.notice = nil } }
        )) {
            Button(manager.language == .ru ? "OK" : "OK", role: .cancel) { manager.notice = nil }
        } message: { Text(manager.notice ?? "") }
    }

    private func receivePDFs(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in manager.open(url) }
            }
        }
        return accepted
    }
}

private struct WindowTitleSynchronizer: NSViewRepresentable {
    let title: String
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let nextTitle = title
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, window.title != nextTitle else { return }
            window.title = nextTitle
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView { WindowChromeView(frame: .zero) }
    func updateNSView(_ view: WindowChromeView, context: Context) { view.configureWindow() }

    @MainActor
    final class WindowChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }
        func configureWindow() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(calibratedRed: 0.125, green: 0.125, blue: 0.125, alpha: 1)
        }
    }
}

/// Scalable, dependency-free rendering of the BotPlus application mark.
struct AppIconPreviewView: View {
    var body: some View {
        Canvas { context, size in
            var canvas = context
            canvas.scaleBy(x: size.width / 1024, y: size.height / 1024)
            let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)
            canvas.fill(Path(roundedRect: full.insetBy(dx: 14, dy: 14), cornerRadius: 210), with: .color(Color(red: 0.105, green: 0.115, blue: 0.135)))

            let document = Path(roundedRect: CGRect(x: 196, y: 112, width: 632, height: 800), cornerRadius: 76)
            canvas.fill(document, with: .linearGradient(Gradient(colors: [Color(red: 0.19, green: 0.21, blue: 0.24), Color(red: 0.115, green: 0.13, blue: 0.155)]), startPoint: CGPoint(x: 280, y: 120), endPoint: CGPoint(x: 750, y: 900)))
            canvas.stroke(document, with: .color(Color(red: 0.58, green: 0.62, blue: 0.69).opacity(0.72)), lineWidth: 18)
            let tab = Path(roundedRect: CGRect(x: 196, y: 112, width: 330, height: 112), cornerRadius: 44)
            canvas.fill(tab, with: .color(Color(red: 0.68, green: 0.16, blue: 0.20)))
            var accent = Path()
            accent.move(to: CGPoint(x: 264, y: 286)); accent.addLine(to: CGPoint(x: 524, y: 286))
            canvas.stroke(accent, with: .color(Color(red: 0.88, green: 0.27, blue: 0.30)), style: StrokeStyle(lineWidth: 12, lineCap: .round))

            // Drafting ticks across the lower-right corner of the sheet.
            for index in 0..<11 {
                let x = CGFloat(548 + index * 22)
                let top: CGFloat = index.isMultiple(of: 5) ? 650 : (index.isMultiple(of: 2) ? 666 : 680)
                var tick = Path(); tick.move(to: CGPoint(x: x, y: top)); tick.addLine(to: CGPoint(x: x, y: 728))
                canvas.stroke(tick, with: .color(Color(red: 0.72, green: 0.76, blue: 0.82).opacity(0.8)), lineWidth: index.isMultiple(of: 5) ? 7 : 4)
            }
            var baseline = Path(); baseline.move(to: CGPoint(x: 548, y: 728)); baseline.addLine(to: CGPoint(x: 782, y: 728))
            canvas.stroke(baseline, with: .color(Color(red: 0.72, green: 0.76, blue: 0.82).opacity(0.72)), lineWidth: 5)

            let badge = Path(roundedRect: CGRect(x: 270, y: 352, width: 484, height: 360), cornerRadius: 76)
            canvas.fill(badge.offsetBy(dx: 0, dy: 16), with: .color(.black.opacity(0.28)))
            canvas.fill(badge, with: .linearGradient(Gradient(colors: [Color(red: 0.28, green: 0.32, blue: 0.38), Color(red: 0.16, green: 0.19, blue: 0.24)]), startPoint: CGPoint(x: 300, y: 350), endPoint: CGPoint(x: 720, y: 720)))
            canvas.stroke(badge, with: .color(Color.white.opacity(0.14)), lineWidth: 5)
            let markColor = Color(red: 0.94, green: 0.95, blue: 0.97)
            var stem = Path(); stem.move(to: CGPoint(x: 414, y: 620)); stem.addLine(to: CGPoint(x: 414, y: 444))
            canvas.stroke(stem, with: .color(markColor), style: StrokeStyle(lineWidth: 44, lineCap: .round))
            let upperBowl = Path(roundedRect: CGRect(x: 414, y: 444, width: 94, height: 92), cornerRadius: 30)
            let lowerBowl = Path(roundedRect: CGRect(x: 414, y: 536, width: 84, height: 84), cornerRadius: 28)
            canvas.stroke(upperBowl, with: .color(markColor), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
            canvas.stroke(lowerBowl, with: .color(markColor), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
            var plus = Path(); plus.move(to: CGPoint(x: 608, y: 542)); plus.addLine(to: CGPoint(x: 704, y: 542))
            plus.move(to: CGPoint(x: 656, y: 494)); plus.addLine(to: CGPoint(x: 656, y: 590))
            canvas.stroke(plus, with: .color(markColor), style: StrokeStyle(lineWidth: 28, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("BotPlus PDF Editor app icon")
    }
}

private struct AboutDialog: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 14) {
            AppIconPreviewView().frame(width: 112, height: 112)
            Text(BotPlusBrand.name).font(.system(size: 20, weight: .semibold))
            Text("\(manager.language == .ru ? "Версия" : "Version") \(BotPlusBrand.version)").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(BotPlusBrand.copyright).font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                Link("botplus.ru", destination: BotPlusBrand.primaryWebsite)
                Link("botplus.io", destination: BotPlusBrand.alternateWebsite)
            }
            Button(manager.language == .ru ? "Закрыть" : "Close") { manager.isAboutPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26).frame(width: 360).background(Palette.ribbon)
        .preferredColorScheme(.dark)
    }
}

private struct QuickBar: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        ZStack {
            Text(manager.title).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 440).frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                Color.clear.frame(width: 78, height: 1)
                AppIconPreviewView().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.horizontal, 2)
                quick("Open", "Открыть", "folder", .open)
                quick("Save", "Сохранить", "square.and.arrow.down", .save)
                quick("Print", "Печать", "printer", .print)
                Hairline(height: 20)
                QuickIcon("Undo", "Отменить", "arrow.uturn.backward", language: manager.language) { manager.perform(.development) }
                QuickIcon("Redo", "Повторить", "arrow.uturn.forward", language: manager.language) { manager.perform(.development) }
                QuickIcon("Back", "Назад", "chevron.left", language: manager.language) { manager.perform(.previous) }
                QuickIcon("Forward", "Вперёд", "chevron.right", language: manager.language) { manager.perform(.next) }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField(manager.language == .ru ? "Поиск / Быстрый поиск…" : "Search / Quick Search…", text: $manager.searchText, onCommit: { manager.send(.refresh) })
                        .textFieldStyle(.plain).frame(width: 158)
                }.padding(.horizontal, 8).frame(height: 25).background(Palette.raised, in: RoundedRectangle(cornerRadius: 4)).padding(.trailing, 10)
            }
        }
        .frame(height: 40).background(Color(red: 0.125, green: 0.125, blue: 0.125))
        .overlay(alignment: .bottom) { Palette.separator.frame(height: 1) }
    }

    private func quick(_ en: String, _ ru: String, _ symbol: String, _ action: RibbonAction) -> some View {
        QuickIcon(en, ru, symbol, language: manager.language) { manager.perform(action) }
    }
}

private struct QuickIcon: View {
    let en: String; let ru: String; let symbol: String; let action: () -> Void
    let language: AppLanguage
    init(_ en: String, _ ru: String, _ symbol: String, language: AppLanguage, action: @escaping () -> Void) {
        self.en = en; self.ru = ru; self.symbol = symbol; self.language = language; self.action = action
    }
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 24) }
            .buttonStyle(.plain).foregroundStyle(Palette.text).help(language == .ru ? ru : en)
    }
}

private struct RibbonView: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(RibbonTab.allCases) { tab in
                        Button { manager.tab = tab } label: {
                            Text(manager.text(tab.title)).font(.system(size: 12, weight: manager.tab == tab ? .semibold : .regular))
                                .foregroundStyle(tab == .file ? Color.white : Palette.text)
                                .padding(.horizontal, tab == .file ? 14 : 10).frame(height: 33)
                                .background(tab == .file ? Palette.file : (manager.tab == tab ? Palette.selected : .clear))
                                .overlay(alignment: .bottom) { if manager.tab == tab && tab != .file { Palette.accent.frame(height: 2) } }
                        }.buttonStyle(.plain).help(manager.text(tab.title))
                    }
                }.padding(.horizontal, 5)
            }.frame(height: 34)
            Palette.separator.frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(groups(for: manager.tab), id: \.id) { group in RibbonGroupView(group: group, manager: manager) }
                }.padding(.horizontal, 6)
            }.frame(height: 91)
            Palette.separator.frame(height: 1)
        }.background(Palette.ribbon)
    }

    private func groups(for tab: RibbonTab) -> [RibbonGroupSpec] {
        let dev = RibbonAction.development
        let tool = { (id: String, en: String, ru: String, icon: String, value: PDFTool) in RibbonCommand(id, en, ru, icon, .tool(value)) }
        let cmd = { (id: String, en: String, ru: String, icon: String) in RibbonCommand(id, en, ru, icon, dev) }
        switch tab {
        case .file:
            return [RibbonGroupSpec("file", "Document", "Документ", [
                RibbonCommand("open", "Open", "Открыть", "folder", .open), RibbonCommand("save", "Save", "Сохранить", "square.and.arrow.down", .save),
                RibbonCommand("saveAs", "Save As", "Сохранить как", "square.and.arrow.up", .saveAs), RibbonCommand("close", "Close", "Закрыть", "xmark", .close),
                RibbonCommand("print", "Print", "Печать", "printer", .print), RibbonCommand("settings", "Settings", "Настройки", "gearshape", .settings)
            ])]
        case .home:
            return [
                RibbonGroupSpec("tools", "Tools", "Инструменты", [tool("hand", "Hand", "Рука", "hand.raised", .hand), tool("text", "Select Text", "Выделить текст", "text.cursor", .textSelection), tool("selectComments", "Select Comments", "Выделить комментарии", "cursorarrow", .selectComments)]),
                RibbonGroupSpec("view", "View", "Вид", [RibbonCommand("zoomOut", "Zoom Out", "Уменьшить", "minus.magnifyingglass", .zoomOut), RibbonCommand("actual", "Actual Size 1:1", "Реальный размер 1:1", "1.magnifyingglass", .actualSize), RibbonCommand("zoomIn", "Zoom In", "Увеличить", "plus.magnifyingglass", .zoomIn), RibbonCommand("fitWidth", "Fit Width", "По ширине", "arrow.left.and.right", .fitWidth), RibbonCommand("rotateLeft", "Rotate 90° CCW", "Повернуть на 90° влево", "rotate.left", .rotateLeft), RibbonCommand("rotateRight", "Rotate 90° CW", "Повернуть на 90° вправо", "rotate.right", .rotateRight)]),
                RibbonGroupSpec("objects", "Objects", "Объекты", [cmd("editText", "Edit Text", "Редактировать текст", "character.cursor.ibeam"), cmd("editContent", "Edit Content", "Редактировать содержимое", "square.and.pencil"), cmd("addImage", "Add Image", "Добавить изображение", "photo.badge.plus")]),
                RibbonGroupSpec("comment", "Comment", "Комментарий", [tool("typewriter", "Typewriter", "Печатная машинка", "character.cursor.ibeam", .typewriter), RibbonCommand("highlight", "Highlight Text", "Подсветить текст", "highlighter", .highlight), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline), cmd("stamp", "Stamp", "Штамп", "seal"), cmd("sticky", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("links", "Links", "Ссылки", [cmd("addLink", "Add Link", "Добавить ссылку", "link"), cmd("editLink", "Edit Links", "Изменить ссылки", "link.badge.plus")]),
                RibbonGroupSpec("security", "Security", "Защита", [cmd("sign", "Sign Document", "Подписать документ", "signature"), cmd("protect", "Protect", "Защитить", "lock.shield")])
            ]
        case .view:
            return [
                RibbonGroupSpec("navigation", "Navigation", "Навигация", [RibbonCommand("prev", "Previous", "Назад", "chevron.left", .previous), RibbonCommand("next", "Next", "Вперёд", "chevron.right", .next), RibbonCommand("first", "First Page", "Первая страница", "backward.end", .first), RibbonCommand("last", "Last Page", "Последняя страница", "forward.end", .last)]),
                RibbonGroupSpec("zoom", "Zoom", "Масштаб", [RibbonCommand("actual", "1:1", "1:1", "1.magnifyingglass", .actualSize), RibbonCommand("zoomOut", "Zoom Out", "Уменьшить", "minus.magnifyingglass", .zoomOut), RibbonCommand("zoomIn", "Zoom In", "Увеличить", "plus.magnifyingglass", .zoomIn), RibbonCommand("fitPage", "Fit Page", "Вся страница", "arrow.down.right.and.arrow.up.left", .fitPage), RibbonCommand("fitWidth", "Fit Width", "По ширине", "arrow.left.and.right", .fitWidth), cmd("marquee", "Marquee Zoom", "Масштаб области", "viewfinder")]),
                RibbonGroupSpec("display", "Page Display", "Отображение страниц", layoutCommands() + [RibbonCommand("rulers", "Rulers", "Линейки", "ruler", .toggleRulers)]),
                RibbonGroupSpec("window", "Window", "Окно", [RibbonCommand("panels", "Panels", "Панели", "sidebar.left", .panels), cmd("newWindow", "New Window", "Новое окно", "macwindow.badge.plus"), cmd("cascade", "Cascade", "Каскадом", "square.stack")]),
                RibbonGroupSpec("read", "Read Out Loud", "Чтение вслух", [cmd("read", "Read", "Читать", "speaker.wave.2"), cmd("pauseRead", "Pause", "Пауза", "pause.fill")])
            ]
        case .comment:
            return [
                RibbonGroupSpec("tools", "Tools", "Инструменты", [tool("hand", "Hand", "Рука", "hand.raised", .hand), tool("selectComments", "Select Comments", "Выбрать комментарии", "cursorarrow", .selectComments)]),
                RibbonGroupSpec("text", "Text", "Текст", [tool("typewriter", "Typewriter", "Печатная машинка", "character.cursor.ibeam", .typewriter), tool("textBox", "Text Box", "Текстовое поле", "text.alignleft", .typewriter), tool("callout", "Callout", "Выноска", "text.bubble", .callout)]),
                RibbonGroupSpec("note", "Note", "Заметка", [cmd("note", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("markup", "Text Markup", "Разметка текста", [RibbonCommand("highlight", "Highlight", "Подсветка", "highlighter", .highlight), cmd("strike", "Strikethrough", "Зачёркивание", "strikethrough"), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline)]),
                RibbonGroupSpec("drawing", "Drawing", "Рисование", [tool("line", "Line", "Линия", "line.diagonal", .line), tool("arrow", "Arrow", "Стрелка", "arrow.up.right", .arrow), tool("rect", "Rectangle", "Прямоугольник", "rectangle", .rectangle), cmd("cloud", "Cloud", "Облако", "cloud"), cmd("pencil", "Pencil", "Карандаш", "pencil.tip"), cmd("eraser", "Eraser", "Ластик", "eraser")]),
                RibbonGroupSpec("measure", "Measurement", "Измерение", [cmd("distance", "Distance", "Расстояние", "ruler"), cmd("perimeter", "Perimeter", "Периметр", "point.topleft.down.to.point.bottomright.curvepath"), cmd("area", "Area", "Площадь", "square.dashed"), cmd("scale", "Scale: 1:1", "Масштаб: 1:1", "scale.3d")]),
                RibbonGroupSpec("media", "Media", "Медиа", [cmd("audio", "Audio", "Аудио", "waveform"), cmd("video", "Video", "Видео", "video"), cmd("3d", "3D", "3D", "cube")]),
                RibbonGroupSpec("manage", "Comment Management", "Управление комментариями", [cmd("list", "Comments List", "Список комментариев", "list.bullet"), cmd("importComments", "Import", "Импорт", "square.and.arrow.down"), cmd("exportComments", "Export", "Экспорт", "square.and.arrow.up")])
            ]
        case .protect:
            return [RibbonGroupSpec("signatures", "Digital Signatures", "Цифровые подписи", [cmd("sign", "Sign Document", "Подписать документ", "signature"), cmd("verify", "Verify", "Проверить", "checkmark.seal")]),
                    RibbonGroupSpec("privacy", "Privacy (MS RMS)", "Конфиденциальность (MS RMS)", [cmd("rms", "Rights Management", "Управление правами", "lock.shield")]),
                    RibbonGroupSpec("initials", "Signatures & Initials", "Подписи и инициалы", [cmd("signature", "Signatures", "Подписи", "signature"), cmd("initials", "Initials", "Инициалы", "pencil.tip.crop.circle")]),
                    RibbonGroupSpec("redaction", "Redaction", "Редакция", [cmd("markRedact", "Mark for Redaction", "Пометить для удаления", "eye.slash"), cmd("applyRedact", "Apply All", "Применить всё", "checkmark.shield")]),
                    RibbonGroupSpec("security", "Document Security", "Безопасность документа", [cmd("password", "Password", "Пароль", "key.horizontal"), cmd("certificates", "Certificates", "Сертификаты", "checkmark.seal")]),
                    RibbonGroupSpec("docusign", "DocuSign", "DocuSign", [cmd("docusign", "Send for Signature", "Отправить на подпись", "paperplane")])]
        case .form:
            return [RibbonGroupSpec("fields", "Form Fields", "Поля формы", [cmd("textField", "Text Field", "Текстовое поле", "character.textbox"), cmd("checkbox", "Checkbox", "Флажок", "checkmark.square"), cmd("radio", "Radio Button", "Переключатель", "circle.inset.filled"), cmd("dropdown", "Dropdown", "Список", "chevron.down.square"), cmd("button", "Button", "Кнопка", "button.horizontal")]),
                    RibbonGroupSpec("field", "Fields", "Поля", [cmd("selectFields", "Select Fields", "Выбрать поля", "cursorarrow"), cmd("alignFields", "Align", "Выровнять", "align.horizontal.left")]),
                    RibbonGroupSpec("data", "Form Data", "Данные формы", [cmd("import", "Import", "Импорт", "square.and.arrow.down"), cmd("export", "Export", "Экспорт", "square.and.arrow.up"), cmd("clear", "Clear", "Очистить", "eraser")]),
                    RibbonGroupSpec("fill", "Fill Forms", "Заполнение форм", [cmd("fill", "Fill Form", "Заполнить форму", "pencil.line")]),
                    RibbonGroupSpec("javascript", "JavaScript Console", "Консоль JavaScript", [cmd("js", "JavaScript", "JavaScript", "curlybraces")])]
        case .organize:
            return [RibbonGroupSpec("pages", "Pages", "Страницы", [RibbonCommand("insert", "Insert Blank Page", "Вставить пустую страницу", "doc.badge.plus", .insertBlankPage), RibbonCommand("delete", "Delete Page", "Удалить страницу", "trash", .deletePage), RibbonCommand("duplicate", "Duplicate Page", "Дублировать страницу", "doc.on.doc", .duplicatePage), cmd("extract", "Extract", "Извлечь", "doc.zipper"), cmd("replace", "Replace", "Заменить", "arrow.2.squarepath"), cmd("split", "Split", "Разделить", "scissors"), cmd("swap", "Swap", "Поменять", "arrow.left.arrow.right")]),
                    RibbonGroupSpec("operations", "Page Operations", "Операции со страницей", [RibbonCommand("rotateLeft", "Rotate Left", "Повернуть влево", "rotate.left", .rotateLeft), RibbonCommand("rotateRight", "Rotate Right", "Повернуть вправо", "rotate.right", .rotateRight), cmd("crop", "Crop", "Обрезать", "crop.rotate"), cmd("resize", "Resize", "Изменить размер", "arrow.up.left.and.arrow.down.right"), cmd("margins", "Margins", "Поля", "rectangle.inset.filled")]),
                    RibbonGroupSpec("labeling", "Page Labeling", "Оформление страниц", [cmd("watermark", "Watermark", "Водяной знак", "drop"), cmd("background", "Background", "Фон", "rectangle.fill"), cmd("header", "Header/Footer", "Колонтитулы", "text.aligncenter"), cmd("bates", "Bates Numbering", "Нумерация Бейтса", "number")])]
        case .convert:
            return [RibbonGroupSpec("create", "Create", "Создать", [cmd("scanner", "From Scanner", "Со сканера", "scanner"), cmd("fromFiles", "From Files", "Из файлов", "doc.on.doc"), cmd("blank", "Blank", "Пустой документ", "doc.badge.plus")]),
                    RibbonGroupSpec("edit", "Edit", "Изменить", [cmd("edit", "Edit PDF", "Изменить PDF", "square.and.pencil")]),
                    RibbonGroupSpec("export", "Export", "Экспорт", [cmd("word", "To Word", "В Word", "doc.text"), cmd("excel", "To Excel", "В Excel", "tablecells"), cmd("powerpoint", "To PowerPoint", "В PowerPoint", "rectangle.on.rectangle"), cmd("images", "To Images", "В изображения", "photo")]),
                    RibbonGroupSpec("ocr", "OCR", "OCR", [cmd("ocr", "Recognize Text", "Распознать текст", "text.viewfinder")]),
                    RibbonGroupSpec("enhance", "Enhanced Pages", "Улучшение страниц", [cmd("enhance", "Enhance", "Улучшить", "wand.and.stars")]),
                    RibbonGroupSpec("color", "Color Conversion", "Преобразование цвета", [cmd("colors", "Convert Colors", "Преобразовать цвета", "circle.lefthalf.filled")])]
        case .mailings:
            return [RibbonGroupSpec("send", "Send", "Отправить", [cmd("emailCurrent", "Email Current Page", "Отправить страницу", "envelope"), cmd("emailAll", "Email All Pages", "Отправить все страницы", "envelope.badge")]),
                    RibbonGroupSpec("sharepoint", "SharePoint", "SharePoint", [cmd("sharepoint", "SharePoint", "SharePoint", "square.and.arrow.up.on.square")])]
        case .review:
            return [RibbonGroupSpec("proofing", "Proofing", "Проверка", [cmd("spell", "Spell Check", "Проверка орфографии", "textformat.abc"), cmd("wordCount", "Word Count", "Подсчёт слов", "number")]),
                    RibbonGroupSpec("comments", "Comments", "Комментарии", [cmd("addComment", "Add", "Добавить", "plus.bubble"), cmd("deleteComment", "Delete", "Удалить", "trash"), cmd("showComments", "Show/Hide", "Показать/скрыть", "eye")]),
                    RibbonGroupSpec("compare", "Compare Documents", "Сравнить документы", [cmd("compare", "Compare", "Сравнить", "rectangle.split.2x1")])]
        case .accessibility:
            return [RibbonGroupSpec("checker", "Accessibility Checker", "Проверка доступности", [cmd("check", "Check Document", "Проверить документ", "accessibility")]),
                    RibbonGroupSpec("order", "Reading Order", "Порядок чтения", [cmd("order", "Reading Order", "Порядок чтения", "list.number")]),
                    RibbonGroupSpec("alt", "Alternative Text", "Альтернативный текст", [cmd("alt", "Alt Text", "Описание изображения", "text.quote")])]
        case .bookmarks:
            return [RibbonGroupSpec("create", "Create", "Создать", [cmd("bookmarkFromPageText", "From Page Text", "Из текста на странице", "text.viewfinder"), cmd("bookmarkEveryN", "Every N-th Page", "Закладка для каждой N-й стр.", "book.pages"), cmd("bookmarkFromTOC", "From TOC", "Из Содержания", "list.bullet.rectangle"), cmd("bookmarkFromFile", "From Text File", "Из текстового файла", "doc.text")]),
                    RibbonGroupSpec("modify", "Modify", "Изменить", [cmd("bookmarkAddText", "Add Text", "Добавить текст", "text.badge.plus"), cmd("bookmarkCase", "Change Case", "Изменить регистр", "textformat"), cmd("bookmarkZoom", "Change Zoom", "Изменить масштаб", "magnifyingglass"), cmd("bookmarkDestination", "Named Destination to Link", "Имен. назначение в ссылку", "link"), cmd("bookmarkFind", "Find & Replace", "Найти и заменить", "text.magnifyingglass"), cmd("bookmarkActions", "Delete Actions", "Удалить действия", "trash"), cmd("bookmarkSort", "Sort", "Сортировать", "arrow.up.arrow.down"), cmd("bookmarkValidate", "Validate", "Утвердить", "checkmark.seal"), cmd("bookmarkMerge", "Merge Duplicates", "Объединить дубликаты", "arrow.triangle.merge")]),
                    RibbonGroupSpec("convert", "Convert", "Преобразовать", [cmd("bookmarkTOC", "Create Table of Contents", "Создать Содержание", "list.bullet.indent"), cmd("bookmarkLinks", "Link for Bookmarks", "Ссылка для закладок", "link.badge.plus"), cmd("bookmarkSortPages", "Sort Pages", "Сортировка страниц", "doc.text.magnifyingglass"), cmd("bookmarkNamed", "Convert to Named Destinations", "Преобр. в им. назначения", "bookmark.fill"), cmd("bookmarkHTML", "Export to HTML", "Экспорт в HTML", "chevron.left.forwardslash.chevron.right"), cmd("bookmarkText", "Export to Text File", "Экспортировать в текстовый файл", "doc.text")])]
        case .help:
            return [RibbonGroupSpec("ui", "UI Settings", "Настройки интерфейса", [cmd("theme", "Theme", "Тема", "circle.lefthalf.filled"), cmd("customize", "Customize Ribbon", "Настроить ленту", "slider.horizontal.3"), RibbonCommand("language", "Language", "Язык", "globe", .languagePicker)]),
                    RibbonGroupSpec("help", "Help", "Справка", [cmd("onlineHelp", "Online Help", "Справка в интернете", "questionmark.circle"), cmd("support", "Support", "Поддержка", "person.crop.circle.badge.questionmark"), cmd("args", "Command Line", "Командная строка", "terminal")]),
                    RibbonGroupSpec("product", "Product", "Программа", [RibbonCommand("about", "About", "О программе", "info.circle", .about), cmd("updates", "Check Updates", "Проверить обновления", "arrow.clockwise"), cmd("associations", "File Associations", "Связи файлов", "doc.badge.gearshape"), cmd("license", "License", "Лицензия", "key")])]
        }
    }

    private func layoutCommands() -> [RibbonCommand] {
        PageLayout.allCases.map { layout in
            RibbonCommand("layout-\(layout.id)", layout.title.en, layout.title.ru, layout == .spread ? "book.pages" : (layout == .single ? "doc" : "scroll"), .layout(layout))
        }
    }
}

private struct RibbonGroupView: View {
    let group: RibbonGroupSpec
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                ForEach(group.commands) { command in
                    Group {
                        switch command.action {
                        case .panels: PanelsMenuButton(manager: manager, command: command)
                        case .languagePicker: LanguageMenuButton(manager: manager, command: command)
                        default:
                            Button { manager.perform(command.action) } label: {
                                commandLabel(command, manager: manager)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .center)
            Text(manager.text(group.title)).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1).padding(.bottom, 3)
        }
        .padding(.horizontal, 7).frame(height: 88)
        .overlay(alignment: .trailing) { Palette.separator.frame(width: 1, height: 68).padding(.bottom, 12) }
    }
}

@MainActor
private func commandLabel(_ command: RibbonCommand, manager: DocumentManager) -> some View {
    let selected: Bool
    if case .toggleRulers = command.action { selected = manager.rulersVisible }
    else if case .tool(let tool) = command.action { selected = manager.tool == tool }
    else { selected = false }
    return VStack(spacing: 5) {
        Image(systemName: command.symbol).font(.system(size: 20, weight: .regular)).frame(height: 24)
        Text(manager.text(command.title)).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75).frame(height: 23)
    }
    .foregroundStyle(selected ? Palette.accent : Palette.text)
    .frame(width: 59, height: 60)
    .background(selected ? Palette.selected : Palette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
    .help(manager.text(command.title))
}

private struct PanelsMenuButton: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var panels: PanelWorkspaceModel
    let command: RibbonCommand
    init(manager: DocumentManager, command: RibbonCommand) { self.manager = manager; self.panels = manager.panels; self.command = command }
    var body: some View {
        Menu {
            ForEach(WorkspacePanel.allCases) { panel in
                Toggle(manager.text(panel.title), isOn: Binding(
                    get: { manager.panels.configuration(for: panel).isVisible },
                    set: { manager.panels.setVisible($0, for: panel) }
                ))
            }
        } label: { commandLabel(command, manager: manager) }
            .menuStyle(.borderlessButton).help(manager.text(command.title))
    }
}

private struct LanguageMenuButton: View {
    @ObservedObject var manager: DocumentManager
    let command: RibbonCommand
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button { manager.language = language } label: {
                    if manager.language == language { Label(language.displayName, systemImage: "checkmark") }
                    else { Text(language.displayName) }
                }
            }
        } label: { commandLabel(command, manager: manager) }
            .menuStyle(.borderlessButton).help(manager.text(command.title))
    }
}

private struct DocumentTabs: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        HStack(spacing: 0) {
            ForEach(manager.documents) { item in
                HStack(spacing: 0) {
                    Button { manager.select(item.id) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "doc.text").foregroundStyle(manager.selectedID == item.id ? Palette.accent : Palette.muted)
                            Text(item.filename).lineLimit(1)
                        }.font(.system(size: 11)).padding(.horizontal, 11).frame(height: 32).frame(maxWidth: 230)
                            .background(manager.selectedID == item.id ? Palette.selected : .clear)
                    }.buttonStyle(.plain).help(item.filename)
                    Button { manager.close(item.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 24, height: 28) }
                        .buttonStyle(.plain).help(manager.language == .ru ? "Закрыть документ" : "Close document")
                }.overlay(alignment: .trailing) { Palette.separator.frame(width: 1, height: 18) }
            }
            Button { manager.openPanel() } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 35, height: 32) }
                .buttonStyle(.plain).help(manager.language == .ru ? "Открыть PDF" : "Open PDF")
            Spacer()
        }
        .frame(height: 33).background(Palette.ribbon.opacity(0.96))
        .overlay(alignment: .bottom) { Palette.separator.frame(height: 1) }
    }
}

private struct EmptyWorkspace: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "doc.text.viewfinder").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Palette.muted)
            Text(manager.language == .ru ? "Документ не открыт" : "No document open").font(.system(size: 17, weight: .medium))
            Text(manager.language == .ru ? "Дважды щёлкните здесь или перетащите PDF-файл" : "Double-click here or drop a PDF file to open")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button { manager.openPanel() } label: { Label(manager.language == .ru ? "Открыть PDF" : "Open PDF", systemImage: "folder") }
                .buttonStyle(.borderedProminent).tint(Palette.accent).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        .onTapGesture(count: 2) { manager.openPanel() }
    }
}

private struct WorkspaceArea: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var panels: PanelWorkspaceModel
    init(manager: DocumentManager) { self.manager = manager; self.panels = manager.panels }
    var body: some View {
        GeometryReader { geometry in
            let count = (panels.activePanel(on: .left) == nil ? 0 : 1) + (panels.activePanel(on: .right) == nil ? 0 : 1)
            let maximum = min(600, max(200, (geometry.size.width - 300) / CGFloat(max(1, count))))
            HStack(spacing: 0) {
                PanelIconStrip(side: .left, manager: manager, panels: panels)
                DockedPanelContainer(side: .left, manager: manager, panels: panels, maximumWidth: maximum)
                if manager.selected != nil { viewer } else { EmptyWorkspace(manager: manager) }
                DockedPanelContainer(side: .right, manager: manager, panels: panels, maximumWidth: maximum)
                PanelIconStrip(side: .right, manager: manager, panels: panels)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var viewer: some View {
        VStack(spacing: 0) {
            if manager.rulersVisible {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(RulerUnit.allCases) { unit in Button(unit.rawValue) { manager.rulerUnit = unit } }
                    } label: { Text(manager.rulerUnit.rawValue).font(.system(size: 8)) }
                    .menuStyle(.borderlessButton).frame(width: 30, height: 25).background(Color(white: 0.125))
                    RulerBar(axis: .horizontal, manager: manager).frame(height: 25)
                }
            }
            HStack(spacing: 0) {
                if manager.rulersVisible { RulerBar(axis: .vertical, manager: manager).frame(width: 30) }
                PDFViewer(manager: manager).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(white: 0.12)).frame(minWidth: 180)
    }
}
private struct PanelIconStrip: View {
    let side: PanelDock
    @ObservedObject var manager: DocumentManager
    @ObservedObject var panels: PanelWorkspaceModel
    var body: some View {
        VStack(spacing: 4) {
            ForEach(WorkspacePanel.allCases.filter {
                let config = panels.configuration(for: $0)
                return (config.dock == .floating ? config.lastDock : config.dock) == side
            }) { panel in
                let config = panels.configuration(for: panel)
                Button { panels.toggleDrawer(panel) } label: {
                    Image(systemName: panel.symbol).font(.system(size: 14))
                        .foregroundStyle(config.isVisible && config.isExpanded ? Palette.accent : Palette.muted)
                        .frame(width: 29, height: 32)
                        .background(config.isVisible && config.isExpanded ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 3))
                }.buttonStyle(.plain).help(manager.text(panel.title))
            }
            Spacer(minLength: 0)
        }.padding(.top, 5).frame(width: 33).frame(maxHeight: .infinity).background(Palette.ribbon)
    }
}
private struct DockedPanelContainer: View {
    let side: PanelDock
    let maximumWidth: CGFloat
    @ObservedObject var manager: DocumentManager
    @ObservedObject var panels: PanelWorkspaceModel
    init(side: PanelDock, manager: DocumentManager, panels: PanelWorkspaceModel, maximumWidth: CGFloat) {
        self.side = side; self.manager = manager; self.panels = panels; self.maximumWidth = maximumWidth
    }
    var body: some View {
        if let panel = panels.activePanel(on: side) {
            let width = min(CGFloat(panels.configuration(for: panel).width), maximumWidth)
            HStack(spacing: 0) {
                if side == .right { PanelResizeHandle(panel: panel, manager: manager, direction: -1, initialWidth: width) }
                VStack(spacing: 0) {
                    PanelHeader(panel: panel, manager: manager)
                    PanelBody(panel: panel, manager: manager)
                }.frame(width: width).frame(maxHeight: .infinity).background(Color(white: 0.20))
                if side == .left { PanelResizeHandle(panel: panel, manager: manager, direction: 1, initialWidth: width) }
            }
        }
    }
}

private struct PanelResizeHandle: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    let direction: CGFloat
    var initialWidth: CGFloat? = nil
    var body: some View {
        Rectangle().fill(Color.clear).frame(width: 6).contentShape(Rectangle())
            .overlay(Palette.separator.opacity(0.7).frame(width: 1))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    manager.panels.resize(panel, translation: direction * value.translation.width, initialWidth: initialWidth)
                }
                .onEnded { _ in manager.panels.endResize(panel) })
            .help(manager.language == .ru ? "Перетащите, чтобы изменить ширину" : "Drag to resize panel")
    }
}

private struct PanelHeader: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        let config = manager.panels.configuration(for: panel)
        HStack(spacing: 3) {
            Text(manager.text(panel.title)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Button { manager.panels.setDock(config.dock == .floating ? config.lastDock : .floating, for: panel) } label: {
                Image(systemName: config.dock == .floating ? "rectangle.inset.filled" : "macwindow").frame(width: 20, height: 23)
            }.buttonStyle(.plain).help(manager.language == .ru ? "Отсоединить / закрепить" : "Detach / Re-dock")
            Button { manager.panels.setDock(.left, for: panel) } label: {
                Image(systemName: "arrow.left").frame(width: 20, height: 23)
            }.buttonStyle(.plain).disabled(config.dock == .left).help(manager.language == .ru ? "Переместить влево" : "Dock Left")
            Button { manager.panels.setDock(.right, for: panel) } label: {
                Image(systemName: "arrow.right").frame(width: 20, height: 23)
            }.buttonStyle(.plain).disabled(config.dock == .right).help(manager.language == .ru ? "Переместить вправо" : "Dock Right")
            Button { manager.panels.setVisible(false, for: panel) } label: {
                Image(systemName: "xmark").frame(width: 20, height: 23)
            }.buttonStyle(.plain).help(manager.language == .ru ? "Закрыть панель" : "Close panel")
        }.font(.system(size: 10)).padding(.horizontal, 6).frame(height: 30).background(Palette.raised)
    }
}

private struct PanelBody: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        Group {
            switch panel {
            case .thumbnails: thumbnailList
            case .bookmarks: bookmarkList
            case .properties: properties
            case .comments: comments
            case .layers: empty(manager.language == .ru ? "Слои PDF недоступны" : "No PDF layers available", symbol: "square.3.layers.3d")
            case .attachments: empty(manager.language == .ru ? "Вложения не найдены" : "No attachments found", symbol: "paperclip")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var thumbnailList: some View {
        if let document = manager.selected?.document {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        if let page = document.page(at: index) {
                            Button { manager.navigate(to: index) } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: page.thumbnail(of: NSSize(width: 140, height: 180), for: .cropBox))
                                        .resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 142, maxHeight: 180)
                                        .background(.white)
                                        .overlay(Rectangle().stroke(manager.selected?.pageIndex == index ? Palette.accent : Palette.separator, lineWidth: 2))
                                    Text("\(index + 1)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxWidth: .infinity).padding(8)
            }
        } else { empty(manager.language == .ru ? "Откройте PDF" : "Open a PDF", symbol: "doc.text") }
    }

    private var bookmarkList: some View {
        Group {
            if let root = manager.selected?.document.outlineRoot {
                let rows = makeBookmarkRows(root: root, document: manager.selected?.document)
                if rows.isEmpty { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
                else {
                    List {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Button { manager.navigate(to: row.pageIndex) } label: {
                                Text(row.title).font(.system(size: 11)).lineLimit(2).padding(.leading, CGFloat(row.depth * 10))
                            }.buttonStyle(.plain)
                        }
                    }.listStyle(.plain)
                }
            } else { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
        }
    }

    private var properties: some View {
        Group {
            if let item = manager.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        AnnotationStyleControls(manager: manager)
                        property(manager.language == .ru ? "Файл" : "File", item.filename)
                        property(manager.language == .ru ? "Страниц" : "Pages", "\(item.pageCount)")
                        if let page = item.document.page(at: item.pageIndex) {
                            let size = page.bounds(for: .cropBox).size
                            property(manager.language == .ru ? "Размер страницы" : "Page size", String(format: "%.1f × %.1f pt", size.width, size.height))
                            property(manager.language == .ru ? "Поворот" : "Rotation", "\(page.rotation)°")
                        }
                        property(manager.language == .ru ? "Масштаб" : "Zoom", String(format: "%.0f%%", Double(item.zoom * 100)))
                    }.padding(10)
                }
            } else { empty(manager.language == .ru ? "Нет выбранного документа" : "No active document", symbol: "doc") }
        }
    }

    private var comments: some View {
        Group {
            if let item = manager.selected {
                let annotations = (0..<item.pageCount).flatMap { index -> [(Int, PDFAnnotation)] in
                    guard let page = item.document.page(at: index) else { return [] }
                    return page.annotations.filter { !AnnotationMetadata.isContainer($0) }.map { (index, $0) }
                }
                if annotations.isEmpty { empty(manager.language == .ru ? "Аннотаций нет" : "No annotations", symbol: "text.bubble") }
                else {
                    List {
                        ForEach(Array(annotations.enumerated()), id: \.offset) { _, entry in
                            Button { manager.navigate(to: entry.0) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.1.contents ?? entry.1.type ?? (manager.language == .ru ? "Аннотация" : "Annotation"))
                                    Text("\(manager.language == .ru ? "Страница" : "Page") \(entry.0 + 1)").font(.system(size: 9)).foregroundStyle(Palette.muted)
                                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }.listStyle(.plain)
                }
            } else { empty(manager.language == .ru ? "Откройте PDF" : "Open a PDF", symbol: "text.bubble") }
        }
    }

    private func property(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 11)).textSelection(.enabled)
        }
    }
    private func empty(_ message: String, symbol: String) -> some View {
        VStack(spacing: 8) { Image(systemName: symbol).font(.title3).foregroundStyle(Palette.muted); Text(message).font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }
}

private struct AnnotationStyleControls: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manager.language == .ru ? "Оформление аннотации" : "Annotation appearance").font(.system(size: 11, weight: .semibold))
            ColorPicker(manager.language == .ru ? "Цвет" : "Color", selection: $manager.annotationColor, supportsOpacity: false)
            HStack {
                Text(manager.language == .ru ? "Толщина" : "Stroke")
                Slider(value: $manager.annotationStrokeWidth, in: 0.5...12)
                Text(String(format: "%.1f", manager.annotationStrokeWidth)).frame(width: 30)
            }
            HStack { Text(manager.language == .ru ? "Непрозр." : "Opacity"); Slider(value: $manager.annotationOpacity, in: 0.1...1) }
            Stepper("\(manager.language == .ru ? "Шрифт" : "Font"): \(Int(manager.textFontSize))", value: $manager.textFontSize, in: 6...72)
            Toggle(manager.language == .ru ? "Рамка текста" : "Text border", isOn: $manager.textBorderEnabled)
            if manager.selectedAnnotation != nil {
                Button(manager.language == .ru ? "Применить к выбранной" : "Apply to selected") { manager.send(.applyAnnotationStyle) }
            }
        }.font(.system(size: 10))
    }
}

private struct BookmarkRow { let title: String; let pageIndex: Int; let depth: Int }
private func makeBookmarkRows(root: PDFOutline, document: PDFDocument?, depth: Int = 0) -> [BookmarkRow] {
    var rows: [BookmarkRow] = []
    for index in 0..<root.numberOfChildren {
        guard let child = root.child(at: index) else { continue }
        if let page = child.destination?.page, let pageIndex = document?.index(for: page) {
            rows.append(BookmarkRow(title: child.label ?? "Bookmark", pageIndex: pageIndex, depth: depth))
        }
        rows.append(contentsOf: makeBookmarkRows(root: child, document: document, depth: depth + 1))
    }
    return rows
}

private struct FloatingPanelContents: View {
    let panel: WorkspacePanel
    @ObservedObject var panels: PanelWorkspaceModel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(panel: panel, manager: manager)
            PanelBody(panel: panel, manager: manager)
        }.frame(minWidth: 200, minHeight: 180)
    }
}

private struct StatusBar: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var viewport: ViewportState
    init(manager: DocumentManager) { self.manager = manager; self.viewport = manager.viewport }
    var body: some View {
        HStack(spacing: 8) {
            StatusIcon(manager: manager, title: Bilingual(en: "Previous Page", ru: "Предыдущая страница"), symbol: "chevron.left", action: .previous)
            TextField("1", text: $manager.pageText, onCommit: manager.commitPageField)
                .textFieldStyle(.roundedBorder).frame(width: 44).multilineTextAlignment(.center).disabled(manager.selected == nil)
            Text("/ \(manager.selected?.pageCount ?? 0)").font(.system(size: 10)).foregroundStyle(Palette.muted)
            StatusIcon(manager: manager, title: Bilingual(en: "Next Page", ru: "Следующая страница"), symbol: "chevron.right", action: .next)
            Hairline(height: 17)
            Text(manager.selected == nil ? (manager.language == .ru ? "Готово" : "Ready") : manager.text(manager.tool.title))
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            if let point = manager.cursorPage {
                Text(String(format: "X %.2f  Y %.2f %@", point.x / manager.rulerUnit.pointsPerUnit, point.y / manager.rulerUnit.pointsPerUnit, manager.rulerUnit.rawValue))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Picker("Units", selection: $manager.rulerUnit) { ForEach(RulerUnit.allCases) { unit in Text(unit.rawValue).tag(unit) } }.labelsHidden().frame(width: 62)
            Image(systemName: "minus.magnifyingglass").font(.system(size: 10))
            Slider(value: Binding(get: { Double(manager.selected?.zoom ?? 1) }, set: { manager.send(.setZoom(CGFloat($0))) }), in: 0.25...4)
                .frame(width: 120).disabled(manager.selected == nil)
            Image(systemName: "plus.magnifyingglass").font(.system(size: 10))
            Text(String(format: "%.0f%%", Double(manager.selected?.zoom ?? 1) * 100)).font(.system(size: 10, design: .monospaced)).frame(width: 42, alignment: .trailing)
            Hairline(height: 17)
            ForEach(PageLayout.allCases) { layout in
                Button { manager.layout = layout; manager.send(.refresh) } label: {
                    Image(systemName: layout == .continuous ? "scroll" : (layout == .single ? "doc" : "book.pages"))
                        .font(.system(size: 11)).foregroundStyle(manager.layout == layout ? Palette.accent : Palette.muted).frame(width: 22, height: 22)
                }.buttonStyle(.plain).help(manager.text(layout.title))
            }
        }.padding(.horizontal, 10).frame(height: 31).background(Palette.ribbon)
            .overlay(alignment: .top) { Palette.separator.frame(height: 1) }
    }
}

private struct StatusIcon: View {
    @ObservedObject var manager: DocumentManager
    let title: Bilingual
    let symbol: String
    let action: RibbonAction
    var body: some View {
        Button { manager.perform(action) } label: { Image(systemName: symbol).font(.system(size: 11)).frame(width: 23, height: 23) }
            .buttonStyle(.plain).disabled(manager.selected == nil).help(manager.text(title))
    }
}

private struct Hairline: View {
    let height: CGFloat
    var body: some View { Palette.separator.frame(width: 1, height: height).padding(.horizontal, 3) }
}

private enum RulerAxis { case horizontal, vertical }

private struct RulerBar: View {
    let axis: RulerAxis
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var viewport: ViewportState
    init(axis: RulerAxis, manager: DocumentManager) { self.axis = axis; self.manager = manager; self.viewport = manager.viewport }
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.125)))
            let metrics = manager.rulerMetrics
            guard metrics.valid else { return }
            let horizontal = axis == .horizontal
            let origin = horizontal ? metrics.horizontalOrigin : metrics.verticalOrigin
            let step = horizontal ? metrics.horizontalPointsPerPixel : metrics.verticalPointsPerPixel
            let length = horizontal ? size.width : size.height
            guard abs(step) > 0.000001 else { return }
            let unitsPerPixel = step / manager.rulerUnit.pointsPerUnit
            let start = origin / manager.rulerUnit.pointsPerUnit
            let end = start + length * unitsPerPixel
            let major = rulerInterval(for: 80 * abs(unitsPerPixel)); let minor = major / 10
            var value = floor(min(start, end) / minor) * minor; var count = 0
            while value <= max(start, end) + minor && count < 2500 {
                let pixel = (value - start) / unitsPerPixel
                if pixel >= 0 && pixel <= length {
                    let majorTick = abs(value / major - (value / major).rounded()) < 0.00001
                    let mediumTick = abs(value / (major / 2) - (value / (major / 2)).rounded()) < 0.00001
                    let tickLength: CGFloat = majorTick ? 15 : (mediumTick ? 10 : 5)
                    var tick = Path()
                    if horizontal { tick.move(to: CGPoint(x: pixel, y: size.height)); tick.addLine(to: CGPoint(x: pixel, y: size.height - tickLength)) }
                    else { tick.move(to: CGPoint(x: size.width, y: pixel)); tick.addLine(to: CGPoint(x: size.width - tickLength, y: pixel)) }
                    context.stroke(tick, with: .color(Color(white: 0.533)), lineWidth: 1)
                    if majorTick {
                        let digits = major >= 1 ? 0 : (major >= 0.1 ? 1 : 2)
                        let label = Text(String(format: "%.*f", digits, abs(value) < minor / 2 ? 0 : value)).font(.system(size: 8)).foregroundColor(Color(white: 0.8))
                        if horizontal { context.draw(label, at: CGPoint(x: pixel + 3, y: 2), anchor: .topLeading) }
                        else {
                            var rotated = context; rotated.translateBy(x: 8, y: pixel + 3); rotated.rotate(by: .degrees(90))
                            rotated.draw(label, at: .zero, anchor: .topLeading)
                        }
                    }
                }
                count += 1; value += minor
            }
            if let cursor = manager.cursorViewport {
                let pixel = horizontal ? cursor.x : cursor.y; var marker = Path()
                if horizontal { marker.move(to: CGPoint(x: pixel, y: 0)); marker.addLine(to: CGPoint(x: pixel, y: size.height)) }
                else { marker.move(to: CGPoint(x: 0, y: pixel)); marker.addLine(to: CGPoint(x: size.width, y: pixel)) }
                context.stroke(marker, with: .color(Palette.accent), lineWidth: 1)
            }
        }.accessibilityLabel("\(manager.language == .ru ? "Линейка" : "Ruler") \(manager.rulerUnit.rawValue)")
    }
}

private func rulerInterval(for target: CGFloat) -> CGFloat {
    let safeTarget = max(0.01, target)
    let power = pow(10, floor(log10(Double(safeTarget))))
    for multiplier in [1.0, 2.0, 5.0, 10.0] where multiplier * power >= Double(safeTarget) {
        return CGFloat(multiplier * power)
    }
    return CGFloat(10 * power)
}

private struct PDFViewer: NSViewRepresentable {
    @ObservedObject var manager: DocumentManager
    func makeCoordinator() -> Coordinator { Coordinator(manager: manager) }
    func makeNSView(context: Context) -> PDFViewerView {
        let view = PDFViewerView(frame: .zero)
        view.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        view.displaysPageBreaks = true
        view.displayBox = .cropBox
        view.pageShadowsEnabled = true
        view.autoScales = false
        view.minScaleFactor = 0.05; view.maxScaleFactor = 20
        disableLiveTextIfAvailable(on: view)
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ view: PDFViewerView, context: Context) {
        context.coordinator.manager = manager
        context.coordinator.update(view)
    }

    static func dismantleNSView(_ nsView: PDFViewerView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.stopEventMonitoring()
    }

    private func disableLiveTextIfAvailable(on view: PDFViewerView) {
        // Some SDK/runtime combinations expose this PDFView selector and others do not.
        // Call it only when present so the single source file builds against public SDKs.
        let setter = NSSelectorFromString("setLiveTextInteractionEnabled:")
        guard view.responds(to: setter), let implementation = view.method(for: setter) else { return }
        typealias BooleanSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(implementation, to: BooleanSetter.self)(view, setter, false)
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        var manager: DocumentManager
        weak var view: PDFViewerView?
        var activeDocumentID: UUID?
        var lastCommand = -1
        var observationTokens: [NSObjectProtocol] = []
        var clipToken: NSObjectProtocol?
        weak var observedClip: NSClipView?
        var syncScheduled = false
        var textPopover: NSPopover?
        var lastSearchText = ""

        init(manager: DocumentManager) { self.manager = manager }
        func attach(_ view: PDFViewerView) {
            self.view = view; view.delegate = self
            view.onCreateText = { [weak self, weak view] page, point, leader in
                guard let self, let view else { return }
                self.createFreeText(on: page, at: point, in: view, leader: leader)
            }
            view.onEditText = { [weak self, weak view] annotation in
                guard let self, let view, let page = annotation.page else { return }
                self.openTextEditor(annotation, page: page, in: view, isNew: false, leader: nil)
            }
            view.onSelectionChanged = { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    self?.manager.selectedAnnotation = view?.selectedAnnotation
                }
            }
            view.onAnnotationChanged = { [weak self] in self?.manager.send(.refresh) }

            view.onCursorChange = { [weak self] viewport, pagePoint in
                guard let self else { return }
                if self.manager.cursorViewport != viewport { self.manager.cursorViewport = viewport }
                if self.manager.cursorPage != pagePoint { self.manager.cursorPage = pagePoint }
            }
            view.onViewportChange = { [weak self, weak view] in
                guard let self, let view else { return }
                self.scheduleViewportSync(for: view)
            }
            for name in [Notification.Name.PDFViewScaleChanged, Notification.Name.PDFViewPageChanged] {
                let token = NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let view = self.view else { return }
                        self.scheduleViewportSync(for: view)
                    }
                }
                observationTokens.append(token)
            }
        }
        func detach() {
            for token in observationTokens { NotificationCenter.default.removeObserver(token) }
            observationTokens.removeAll()
            if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
            clipToken = nil; observedClip = nil
            textPopover?.close(); textPopover = nil
        }
        private func observeScroll(in view: PDFViewerView) {
            guard let clip = view.internalScrollView?.contentView, clip !== observedClip else { return }
            if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
            observedClip = clip; clip.postsBoundsChangedNotifications = true
            clipToken = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let view = self.view else { return }
                    self.scheduleViewportSync(for: view)
                }
            }
        }

        func update(_ view: PDFViewerView) {
            if activeDocumentID != manager.selected?.id {
                activeDocumentID = manager.selected?.id
                lastSearchText = ""
                if let popover = textPopover { Task { @MainActor in popover.close() } }
                view.selectAnnotation(nil)
                view.document = manager.selected?.document
                if let item = manager.selected {
                    view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, item.zoom))
                    if let page = item.document.page(at: item.pageIndex) { view.go(to: page) }
                }
            }
            if view.displayMode != manager.layout.pdfMode { view.displayMode = manager.layout.pdfMode }
            if view.displaysAsBook != (manager.layout == .spread) { view.displaysAsBook = manager.layout == .spread }
            view.activeTool = manager.tool
            view.strokeColor = NSColor(manager.annotationColor).withAlphaComponent(CGFloat(manager.annotationOpacity))
            view.strokeWidth = CGFloat(manager.annotationStrokeWidth)
            view.refreshOverlay()
            observeScroll(in: view)
            if manager.searchText != lastSearchText, !manager.searchText.isEmpty {
                lastSearchText = manager.searchText
                if let selection = itemSearch(manager.searchText, in: view.document) {
                    view.setCurrentSelection(selection, animate: true)
                    view.go(to: selection)
                }
            }
            if lastCommand != manager.commandIndex {
                lastCommand = manager.commandIndex
                let command = manager.command
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    guard let self, let view else { return }
                    self.perform(command, on: view)
                }
            }
            scheduleViewportSync(for: view)
        }

        private func perform(_ command: ViewerCommand, on view: PDFViewerView) {
            guard let item = manager.selected, view.document === item.document else { return }
            switch command {
            case .refresh: break
            case .zoomIn: view.autoScales = false; view.scaleFactor = min(view.maxScaleFactor, view.scaleFactor * 1.2)
            case .zoomOut: view.autoScales = false; view.scaleFactor = max(view.minScaleFactor, view.scaleFactor / 1.2)
            case .actualSize: view.autoScales = false; view.scaleFactor = 1
            case .fitPage:
                view.autoScales = true
                view.layoutSubtreeIfNeeded()
                view.autoScales = false
            case .fitWidth:
                guard let page = view.currentPage ?? item.document.page(at: 0) else { return }
                let width = page.bounds(for: view.displayBox).width
                guard width > 0 else { return }
                view.autoScales = false
                view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, (view.bounds.width - 32) / width))
            case .rotate(let angle):
                guard let page = view.currentPage else { return }
                page.rotation = (page.rotation + angle + 360) % 360
                let index = item.document.index(for: page)
                reload(view, document: item, pageIndex: index)
                manager.send(.refresh)
            case .page(let index):
                if let page = item.document.page(at: index) { view.go(to: page) }
            case .highlight: addMarkup(on: view, underline: false)
            case .underline: addMarkup(on: view, underline: true)
            case .insertBlankPage: insertBlankPage(on: view, document: item)
            case .deletePage: deleteCurrentPage(on: view, document: item)
            case .duplicatePage:
                guard let source = view.currentPage, let duplicate = source.copy() as? PDFPage else { return }
                let index = item.document.index(for: source) + 1
                AnnotationMetadata.copy(from: source, to: duplicate)
                item.document.insert(duplicate, at: index)
                item.pageIndex = index
                reload(view, document: item, pageIndex: index)
                manager.pageText = String(index + 1); manager.send(.refresh)
            case .applyAnnotationStyle:
                if let annotation = view.selectedAnnotation {
                    annotation.removeValue(forAnnotationKey: .appearanceDictionary)
                    annotation.color = annotation.type == "FreeText" ? .clear : view.strokeColor
                    AnnotationMetadata.setOpacity(manager.annotationOpacity, on: annotation)
                    let border = PDFBorder(); border.lineWidth = view.strokeWidth
                    annotation.border = annotation.type == "FreeText" && !manager.textBorderEnabled ? nil : border
                    if annotation.type == "FreeText" {
                        annotation.fontColor = view.strokeColor
                        annotation.font = NSFont.systemFont(ofSize: CGFloat(manager.textFontSize))
                        if let group = AnnotationMetadata.group(of: annotation), let page = annotation.page {
                            for leader in page.annotations where leader.type == "Line" && AnnotationMetadata.group(of: leader) == group {
                                leader.removeValue(forAnnotationKey: .appearanceDictionary)
                                leader.color = view.strokeColor; leader.border = border
                                AnnotationMetadata.setOpacity(manager.annotationOpacity, on: leader)
                            }
                        }
                    }
                    view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh)
                }
            case .print:
                guard view.document != nil, view.document === item.document else { return }
                let printInfo = NSPrintInfo.shared
                view.print(with: printInfo, autoRotate: true, pageScaling: .pageScaleDownToFit)
            case .setZoom(let zoom):
                view.autoScales = false
                view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, zoom))
            }
            scheduleViewportSync(for: view)
        }

        private func scheduleViewportSync(for view: PDFViewerView) {
            guard !syncScheduled else { return }
            syncScheduled = true
            Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self else { return }
                self.syncScheduled = false
                guard let view, let item = self.manager.selected, view.document === item.document else { return }
                self.observeScroll(in: view)
                self.syncPage(); self.syncMetrics(for: view); view.refreshOverlay()
                if item.zoom != view.scaleFactor { item.zoom = view.scaleFactor }
            }
        }

        private func itemSearch(_ query: String, in document: PDFDocument?) -> PDFSelection? {
            document?.findString(query, withOptions: [.caseInsensitive]).first
        }

        private func addMarkup(on view: PDFViewerView, underline: Bool) {
            guard let selection = view.currentSelection, !(selection.string ?? "").isEmpty else {
                manager.say(
                    underline ? "Select PDF text first, then choose Underline." : "Select PDF text first, then choose Highlight Text.",
                    underline ? "Сначала выделите текст в PDF, затем нажмите «Подчеркнуть»." : "Сначала выделите текст в PDF, затем нажмите «Подсветить текст»."
                )
                return
            }
            let subtype: PDFAnnotationSubtype = underline ? .underline : .highlight
            let tint = underline ? NSColor.systemCyan.withAlphaComponent(0.72) : NSColor.systemYellow.withAlphaComponent(0.52)
            let lineSelections = selection.selectionsByLine()
            if lineSelections.isEmpty {
                addMarkup(selection, subtype: subtype, color: tint)
            } else {
                for lineSelection in lineSelections { addMarkup(lineSelection, subtype: subtype, color: tint) }
            }
            view.setCurrentSelection(nil, animate: false)
            view.setNeedsDisplay(view.bounds)
        }

        private func addMarkup(_ selection: PDFSelection, subtype: PDFAnnotationSubtype, color: NSColor) {
            for page in selection.pages {
                let bounds = selection.bounds(for: page).insetBy(dx: -1, dy: -1)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = color
                AnnotationMetadata.setOpacity(Double(color.alphaComponent), on: annotation)
                page.addAnnotation(annotation)
            }
        }

        func createFreeText(on page: PDFPage, at point: CGPoint, in view: PDFViewerView, leader: PDFAnnotation?) {
            let crop = page.bounds(for: .cropBox)
            let width = min(260, crop.width)
            let x = min(max(point.x, crop.minX), crop.maxX - width)
            let y = max(crop.minY, min(point.y - 60, crop.maxY - 60))
            let annotation = PDFAnnotation(bounds: CGRect(x: x, y: y, width: width, height: 60), forType: .freeText, withProperties: nil)
            annotation.contents = ""
            annotation.font = NSFont.systemFont(ofSize: CGFloat(manager.textFontSize))
            annotation.fontColor = view.strokeColor
            annotation.color = .clear
            AnnotationMetadata.setOpacity(manager.annotationOpacity, on: annotation)
            if let leader, let group = AnnotationMetadata.group(of: leader) {
                AnnotationMetadata.setGroup(group, on: annotation)
            }
            annotation.alignment = .left
            let border = PDFBorder(); border.lineWidth = manager.textBorderEnabled ? view.strokeWidth : 0
            annotation.border = border
            page.addAnnotation(annotation)
            view.selectAnnotation(annotation)
            openTextEditor(annotation, page: page, in: view, isNew: true, leader: leader)
        }
        private func openTextEditor(_ annotation: PDFAnnotation, page: PDFPage, in view: PDFViewerView, isNew: Bool, leader: PDFAnnotation?) {
            textPopover?.close()
            let popover = NSPopover()
            let editor = FreeTextEditorController(annotation: annotation, language: manager.language)
            editor.onLiveChange = { [weak view] in
                view?.updateCalloutLeader(for: annotation)
                view?.refreshOverlay(); view?.setNeedsDisplay(view?.bounds ?? .zero)
            }
            editor.onFinish = { [weak self, weak view] cancelled in
                if isNew && (cancelled || (annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    page.removeAnnotation(annotation)
                    if let leader { page.removeAnnotation(leader) }
                    view?.selectAnnotation(nil)
                }
                view?.updateCalloutLeader(for: annotation)
                view?.refreshOverlay(); view?.setNeedsDisplay(view?.bounds ?? .zero)
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.manager.send(.refresh)
                }
                self?.textPopover = nil
            }
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 360, height: 255)
            popover.contentViewController = editor; popover.delegate = editor; editor.popover = popover
            textPopover = popover
            let anchor = view.convert(annotation.bounds, from: page).intersection(view.bounds)
            popover.show(relativeTo: anchor.isEmpty ? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) : anchor, of: view, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeFirstResponder(editor.textView)
        }

        private func insertBlankPage(on view: PDFViewerView, document item: PDFDocumentItem) {
            let currentIndex = view.currentPage.map { item.document.index(for: $0) } ?? item.pageIndex
            let insertIndex = min(max(currentIndex, 0), item.pageCount)
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            item.document.insert(page, at: insertIndex)
            item.pageIndex = insertIndex
            reload(view, document: item, pageIndex: insertIndex)
            manager.pageText = String(insertIndex + 1)
            manager.send(.refresh)
        }

        private func deleteCurrentPage(on view: PDFViewerView, document item: PDFDocumentItem) {
            guard item.pageCount > 1 else {
                manager.say("A PDF must keep at least one page.", "В PDF должна остаться хотя бы одна страница.")
                return
            }
            let currentIndex = view.currentPage.map { item.document.index(for: $0) } ?? item.pageIndex
            let removeIndex = min(max(currentIndex, 0), item.pageCount - 1)
            item.document.removePage(at: removeIndex)
            let nextIndex = min(removeIndex, item.pageCount - 1)
            item.pageIndex = nextIndex
            reload(view, document: item, pageIndex: nextIndex)
            manager.pageText = String(nextIndex + 1)
            manager.send(.refresh)
        }

        private func reload(_ view: PDFViewerView, document item: PDFDocumentItem, pageIndex: Int) {
            let zoom = view.scaleFactor
            view.selectAnnotation(nil)
            view.document = nil
            view.document = item.document
            view.scaleFactor = zoom
            if let page = item.document.page(at: pageIndex) { view.go(to: page) }
            view.setCurrentSelection(nil, animate: false)
            view.setNeedsDisplay(view.bounds)
        }

        private func syncPage() {
            guard let view, let item = manager.selected, let page = view.currentPage else { return }
            let index = max(0, item.document.index(for: page))
            if item.pageIndex != index { item.pageIndex = index }
            let pageValue = String(index + 1)
            if manager.pageText != pageValue { manager.pageText = pageValue }
        }

        private func syncMetrics(for view: PDFViewerView) {
            guard let page = view.currentPage, !view.bounds.isEmpty else {
                if manager.rulerMetrics.valid { manager.rulerMetrics = RulerMetrics() }
                return
            }
            let crop = page.bounds(for: .cropBox)
            guard crop.width > 0, crop.height > 0 else { return }
            // PDFView conversions include page rotation, page-break spacing, pan, and magnification.
            let cropOriginInView = view.convert(CGPoint(x: crop.minX, y: crop.maxY), from: page)
            let cropOrigin = view.convert(cropOriginInView, to: page)
            let topLeft = CGPoint(x: view.bounds.minX, y: view.isFlipped ? view.bounds.minY : view.bounds.maxY)
            let origin = view.convert(topLeft, to: page)
            let right = view.convert(CGPoint(x: topLeft.x + 1, y: topLeft.y), to: page)
            let down = view.convert(CGPoint(x: topLeft.x, y: topLeft.y + (view.isFlipped ? 1 : -1)), to: page)
            let horizontalX = abs(right.x - origin.x) >= abs(right.y - origin.y)
            let verticalY = abs(down.y - origin.y) >= abs(down.x - origin.x)
            let metrics = RulerMetrics(
                horizontalOrigin: horizontalX ? origin.x - cropOrigin.x : origin.y - crop.minY,
                horizontalPointsPerPixel: horizontalX ? right.x - origin.x : right.y - origin.y,
                verticalOrigin: verticalY ? origin.y - crop.minY : origin.x - cropOrigin.x,
                verticalPointsPerPixel: verticalY ? down.y - origin.y : down.x - origin.x,
                valid: true
            )
            if manager.rulerMetrics != metrics { manager.rulerMetrics = metrics }
        }

        func pdfViewPageChanged(_ notification: Notification) {
            if let view { scheduleViewportSync(for: view) }
        }
    }
}

@MainActor
private final class FreeTextEditorController: NSViewController, NSTextViewDelegate, NSPopoverDelegate {
    let annotation: PDFAnnotation
    let language: AppLanguage
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 330, height: 105))
    private let fontSize = NSTextField(string: "18")
    private let thickness = NSTextField(string: "2")
    private let color = NSColorWell(frame: .zero)
    private let opacity = NSSlider(value: 1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let borderToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    weak var popover: NSPopover?
    var onLiveChange: (() -> Void)?
    var onFinish: ((Bool) -> Void)?
    private var cancelled = false
    private var finished = false
    private let originalContents: String?
    private let originalFont: NSFont?
    private let originalColor: NSColor
    private let originalFontColor: NSColor?
    private let originalBorder: PDFBorder?
    private let originalBounds: CGRect
    private let originalOpacity: CGFloat

    init(annotation: PDFAnnotation, language: AppLanguage) {
        self.annotation = annotation; self.language = language
        originalContents = annotation.contents; originalFont = annotation.font
        originalColor = annotation.color; originalFontColor = annotation.fontColor
        originalBorder = annotation.border?.copy() as? PDFBorder; originalBounds = annotation.bounds
        originalOpacity = AnnotationMetadata.alpha(of: annotation)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 255))
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 136, width: 336, height: 105))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        textView.isRichText = false; textView.delegate = self
        textView.string = annotation.contents ?? ""
        textView.font = annotation.font ?? NSFont.systemFont(ofSize: 18)
        textView.textColor = annotation.fontColor ?? .systemRed
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView; root.addSubview(scroll)
        fontSize.stringValue = String(format: "%.0f", annotation.font?.pointSize ?? 18)
        thickness.stringValue = String(format: "%.1f", annotation.border?.lineWidth ?? 2)
        color.color = annotation.fontColor ?? annotation.color
        opacity.doubleValue = Double(AnnotationMetadata.alpha(of: annotation))
        color.color = color.color.withAlphaComponent(1)
        borderToggle.title = language == .ru ? "Рамка" : "Border"
        borderToggle.state = (annotation.border?.lineWidth ?? 0) > 0 ? .on : .off
        for field in [fontSize, thickness] { field.target = self; field.action = #selector(applyControls) }
        color.target = self; color.action = #selector(applyControls)
        opacity.target = self; opacity.action = #selector(applyControls); opacity.isContinuous = true
        borderToggle.target = self; borderToggle.action = #selector(applyControls)
        let label1 = NSTextField(labelWithString: language == .ru ? "Шрифт" : "Font")
        let label2 = NSTextField(labelWithString: language == .ru ? "Толщина" : "Stroke")
        let row = NSStackView(views: [label1, fontSize, label2, thickness, color])
        row.frame = NSRect(x: 12, y: 96, width: 336, height: 30); row.spacing = 8; root.addSubview(row)
        let row2 = NSStackView(views: [borderToggle, NSTextField(labelWithString: language == .ru ? "Непрозрачность" : "Opacity"), opacity])
        row2.frame = NSRect(x: 12, y: 58, width: 336, height: 28); row2.spacing = 8; root.addSubview(row2)
        let done = NSButton(title: language == .ru ? "Готово" : "Done", target: self, action: #selector(commit))
        let cancel = NSButton(title: language == .ru ? "Отмена" : "Cancel", target: self, action: #selector(cancelEditing))
        let buttons = NSStackView(views: [cancel, done]); buttons.frame = NSRect(x: 190, y: 15, width: 158, height: 28)
        root.addSubview(buttons); view = root
    }
    func textDidChange(_ notification: Notification) { applyControls() }
    @objc private func applyControls() {
        let size = CGFloat(min(72, max(6, Double(fontSize.stringValue) ?? 18)))
        let font = NSFont.systemFont(ofSize: size)
        let tint = color.color.withAlphaComponent(CGFloat(opacity.doubleValue))
        annotation.removeValue(forAnnotationKey: .appearanceDictionary)
        annotation.contents = textView.string; annotation.font = font; annotation.fontColor = tint
        annotation.color = .clear
        AnnotationMetadata.setOpacity(opacity.doubleValue, on: annotation)
        let border = PDFBorder(); border.lineWidth = borderToggle.state == .on ? CGFloat(min(12, max(0.5, Double(thickness.stringValue) ?? 2))) : 0
        annotation.border = border
        let measured = (textView.string as NSString).boundingRect(with: CGSize(width: max(20, originalBounds.width - 16), height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let height = max(originalBounds.height, ceil(measured.height) + 16)
        annotation.bounds = CGRect(x: originalBounds.minX, y: originalBounds.maxY - height, width: originalBounds.width, height: height)
        textView.font = font; textView.textColor = tint
        onLiveChange?()
    }
    @objc private func commit() { applyControls(); popover?.close() }
    @objc private func cancelEditing() { cancelled = true; popover?.close() }
    func popoverDidClose(_ notification: Notification) {
        guard !finished else { return }; finished = true
        if cancelled {
            annotation.contents = originalContents; annotation.font = originalFont
            annotation.color = originalColor; annotation.fontColor = originalFontColor
            annotation.border = originalBorder; annotation.bounds = originalBounds
            AnnotationMetadata.setOpacity(Double(originalOpacity), on: annotation)
        } else { applyControls() }
        onFinish?(cancelled)
    }
}

@MainActor
private final class AnnotationOverlayView: NSView {
    weak var pdfView: PDFViewerView?
    override var isFlipped: Bool { pdfView?.isFlipped ?? false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let pdf = pdfView else { return }
        if let annotation = pdf.selectedAnnotation, let page = annotation.page {
            let rect = convert(pdf.convert(annotation.bounds, from: page), from: pdf)
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2)); outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
            for corner in pdf.annotationCorners(annotation) {
                let point = convert(pdf.convert(corner, from: page), from: pdf)
                let handle = NSBezierPath(rect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); handle.stroke()
            }
        }
        if let preview = pdf.preview {
            let start = convert(pdf.convert(preview.start, from: preview.page), from: pdf)
            let end = convert(pdf.convert(preview.end, from: preview.page), from: pdf)
            pdf.strokeColor.setStroke()
            let path: NSBezierPath
            if preview.tool == .rectangle {
                path = NSBezierPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            } else { path = NSBezierPath(); path.move(to: start); path.line(to: end) }
            path.lineWidth = max(1, pdf.strokeWidth * pdf.scaleFactor); path.stroke()
        }
    }
}

@MainActor
private final class PDFViewerView: PDFView {
    struct Preview { let page: PDFPage; let start: CGPoint; var end: CGPoint; let tool: PDFTool }
    private struct Transform {
        let annotation: PDFAnnotation
        let page: PDFPage
        let start: CGPoint
        let bounds: CGRect
        let corner: Int?
        let lineStart: CGPoint
        let lineEnd: CGPoint
    }
    var activeTool: PDFTool = .hand { didSet { if activeTool != oldValue { window?.invalidateCursorRects(for: self) } } }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 2
    var onViewportChange: (() -> Void)?
    var onCreateText: ((PDFPage, CGPoint, PDFAnnotation?) -> Void)?
    var onEditText: ((PDFAnnotation) -> Void)?
    var onSelectionChanged: ((PDFAnnotation?) -> Void)?
    var onAnnotationChanged: (() -> Void)?
    var onCursorChange: ((CGPoint?, CGPoint?) -> Void)?
    private(set) var selectedAnnotation: PDFAnnotation?
    private(set) var preview: Preview?
    private var transform: Transform?
    private var panPoint: CGPoint?
    private var cursorPushed = false
    private var eventMonitor: Any?
    private var tracking: NSTrackingArea?
    private let overlay = AnnotationOverlayView(frame: .zero)
    override var acceptsFirstResponder: Bool { true }

    var internalScrollView: NSScrollView? {
        if let scroll = documentView?.enclosingScrollView { return scroll }
        func find(_ view: NSView) -> NSScrollView? {
            for child in view.subviews {
                if let scroll = child as? NSScrollView { return scroll }
                if let result = find(child) { return result }
            }
            return nil
        }
        return find(self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopEventMonitoring()
        guard window != nil else { return }
        overlay.pdfView = self; overlay.autoresizingMask = [.width, .height]
        addSubview(overlay, positioned: .above, relativeTo: nil); refreshOverlay()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated {
                if let self, event.window === self.window {
                    let local = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(local) {
                        if event.type == .magnify {
                            self.applyMagnification(event.magnification, at: local); handled = true
                        } else if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                            self.applyMagnification(-event.scrollingDeltaY * 0.01, at: local); handled = true
                        }
                    }
                }
            }
            return handled ? nil : event
        }
    }
    func stopEventMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) { trackCursor(event) }
    override func mouseEntered(with event: NSEvent) { trackCursor(event) }
    override func mouseExited(with event: NSEvent) { onCursorChange?(nil, nil) }
    private func trackCursor(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let viewport = CGPoint(x: local.x - bounds.minX, y: isFlipped ? local.y - bounds.minY : bounds.maxY - local.y)
        var pdfPoint: CGPoint?
        if let page = page(for: local, nearest: false) {
            let point = convert(local, to: page); let crop = page.bounds(for: .cropBox)
            if crop.contains(point) { pdfPoint = CGPoint(x: point.x - crop.minX, y: point.y - crop.minY) }
        }
        onCursorChange?(viewport, pdfPoint)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let nativeHit = super.hitTest(point)
        if nativeHit is NSScroller { return nativeHit }
        let intercepted: Bool
        switch activeTool {
        case .hand, .typewriter, .rectangle, .line, .arrow, .callout, .selectComments: intercepted = true
        default: intercepted = false
        }
        let local = convert(point, from: superview)
        return intercepted && bounds.contains(local) ? self : nativeHit
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        switch activeTool {
        case .hand: addCursorRect(visibleRect, cursor: .openHand)
        case .textSelection, .typewriter: addCursorRect(visibleRect, cursor: .iBeam)
        case .rectangle, .line, .arrow, .callout: addCursorRect(visibleRect, cursor: .crosshair)
        default: break
        }
    }
    func selectAnnotation(_ annotation: PDFAnnotation?) {
        if let annotation, let group = AnnotationMetadata.group(of: annotation), let page = annotation.page {
            selectedAnnotation = page.annotations.first { $0.type == "FreeText" && AnnotationMetadata.group(of: $0) == group } ?? annotation
        } else { selectedAnnotation = annotation }
        refreshOverlay(); onSelectionChanged?(selectedAnnotation)
    }
    func updateCalloutLeader(for annotation: PDFAnnotation) {
        guard annotation.type == "FreeText", let group = AnnotationMetadata.group(of: annotation), let page = annotation.page,
              let leader = page.annotations.first(where: { $0.type == "Line" && AnnotationMetadata.group(of: $0) == group }) else { return }
        let start = CGPoint(x: leader.bounds.minX + leader.startPoint.x, y: leader.bounds.minY + leader.startPoint.y)
        let end = CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY)
        let rect = CGRect(x: min(start.x, end.x) - 1, y: min(start.y, end.y) - 1, width: max(2, abs(end.x - start.x) + 2), height: max(2, abs(end.y - start.y) + 2))
        leader.bounds = rect
        leader.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
        leader.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
    }
    func refreshOverlay() {
        if overlay.frame != bounds { overlay.frame = bounds }
        if overlay.superview === self && subviews.last !== overlay { addSubview(overlay, positioned: .above, relativeTo: nil) }
        overlay.needsDisplay = true
    }
    func annotationCorners(_ annotation: PDFAnnotation) -> [CGPoint] {
        let r = annotation.bounds
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }
    override func mouseDown(with event: NSEvent) {
        trackCursor(event)
        if activeTool == .hand {
            panPoint = event.locationInWindow; NSCursor.closedHand.push(); cursorPushed = true; return
        }
        let local = convert(event.locationInWindow, from: nil)
        guard let page = page(for: local, nearest: false) else { selectAnnotation(nil); return }
        let point = convert(local, to: page)
        if activeTool == .selectComments {
            window?.makeFirstResponder(self)
            if let annotation = selectedAnnotation, annotation.page === page {
                let corner = annotationCorners(annotation).firstIndex { corner in
                    let handle = convert(corner, from: page)
                    return hypot(handle.x - local.x, handle.y - local.y) <= 9
                }
                if let corner {
                    transform = Transform(annotation: annotation, page: page, start: point, bounds: annotation.bounds, corner: corner, lineStart: annotation.startPoint, lineEnd: annotation.endPoint)
                    return
                }
            }
            let annotation = page.annotations.reversed().first { $0.shouldDisplay && !AnnotationMetadata.isContainer($0) && $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
            selectAnnotation(annotation)
            if let annotation = selectedAnnotation {
                if event.clickCount == 2 && annotation.type == "FreeText" { onEditText?(annotation); return }
                transform = Transform(annotation: annotation, page: page, start: point, bounds: annotation.bounds, corner: nil, lineStart: annotation.startPoint, lineEnd: annotation.endPoint)
            }
            return
        }
        guard page.bounds(for: .cropBox).contains(point) else { return }
        switch activeTool {
        case .typewriter: onCreateText?(page, point, nil)
        case .rectangle, .line, .arrow, .callout: preview = Preview(page: page, start: point, end: point, tool: activeTool); refreshOverlay()
        default: super.mouseDown(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        trackCursor(event)
        if var drawing = preview {
            let point = convert(convert(event.locationInWindow, from: nil), to: drawing.page)
            let crop = drawing.page.bounds(for: .cropBox)
            drawing.end = CGPoint(x: min(crop.maxX, max(crop.minX, point.x)), y: min(crop.maxY, max(crop.minY, point.y)))
            preview = drawing; refreshOverlay(); return
        }
        if let change = transform {
            let point = convert(convert(event.locationInWindow, from: nil), to: change.page)
            let dx = point.x - change.start.x, dy = point.y - change.start.y
            var rect = change.bounds
            let crop = change.page.bounds(for: .cropBox)
            if let corner = change.corner {
                var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
                if corner == 0 || corner == 3 { minX = min(maxX - 6, max(crop.minX, minX + dx)) }
                else { maxX = max(minX + 6, min(crop.maxX, maxX + dx)) }
                if corner == 0 || corner == 1 { minY = min(maxY - 6, max(crop.minY, minY + dy)) }
                else { maxY = max(minY + 6, min(crop.maxY, maxY + dy)) }
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            } else {
                rect.origin.x = min(max(crop.minX, rect.minX + dx), max(crop.minX, crop.maxX - rect.width))
                rect.origin.y = min(max(crop.minY, rect.minY + dy), max(crop.minY, crop.maxY - rect.height))
            }
            change.annotation.bounds = rect
            if change.corner != nil && change.annotation.type == "Line" {
                let sx = rect.width / max(1, change.bounds.width), sy = rect.height / max(1, change.bounds.height)
                change.annotation.startPoint = CGPoint(x: change.lineStart.x * sx, y: change.lineStart.y * sy)
                change.annotation.endPoint = CGPoint(x: change.lineEnd.x * sx, y: change.lineEnd.y * sy)
            }
            updateCalloutLeader(for: change.annotation)
            setNeedsDisplay(bounds); refreshOverlay(); return
        }
        if let previous = panPoint, let scroll = internalScrollView {
            let clip = scroll.contentView; let current = event.locationInWindow
            let deltaInView = convert(current, from: nil) - convert(previous, from: nil)
            let delta = clip.convert(deltaInView, from: self) - clip.convert(.zero, from: self)
            let proposed = CGRect(origin: CGPoint(x: clip.bounds.minX - delta.x, y: clip.bounds.minY - delta.y), size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin); scroll.reflectScrolledClipView(clip)
            panPoint = current; onViewportChange?(); return
        }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if let drawing = preview {
            preview = nil; commitDrawing(drawing); refreshOverlay(); onAnnotationChanged?(); return
        }
        if transform != nil { transform = nil; onAnnotationChanged?(); return }
        if panPoint != nil {
            panPoint = nil; if cursorPushed { NSCursor.pop(); cursorPushed = false }; return
        }
        super.mouseUp(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if activeTool == .selectComments && (event.keyCode == 51 || event.keyCode == 117),
           let annotation = selectedAnnotation, let page = annotation.page {
            if let group = AnnotationMetadata.group(of: annotation) {
                for component in page.annotations where AnnotationMetadata.group(of: component) == group { page.removeAnnotation(component) }
            } else { page.removeAnnotation(annotation) }
            selectAnnotation(nil); setNeedsDisplay(bounds); onAnnotationChanged?(); return
        }
        if event.keyCode == 53 { selectAnnotation(nil); preview = nil; transform = nil; refreshOverlay(); return }
        super.keyDown(with: event)
    }
    private func commitDrawing(_ drawing: Preview) {
        let start = drawing.start, end = drawing.end
        guard hypot(end.x - start.x, end.y - start.y) >= 3 else { return }
        let rect = CGRect(x: min(start.x, end.x) - 1, y: min(start.y, end.y) - 1, width: max(2, abs(end.x - start.x) + 2), height: max(2, abs(end.y - start.y) + 2))
        let annotation = PDFAnnotation(bounds: rect, forType: drawing.tool == .rectangle ? .square : .line, withProperties: nil)
        annotation.color = strokeColor
        AnnotationMetadata.setOpacity(Double(strokeColor.alphaComponent), on: annotation)
        if drawing.tool == .callout { AnnotationMetadata.setGroup(UUID().uuidString, on: annotation) }
        let border = PDFBorder(); border.lineWidth = strokeWidth; annotation.border = border
        if drawing.tool != .rectangle {
            annotation.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            annotation.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
            if drawing.tool == .arrow { annotation.endLineStyle = .openArrow }
            if drawing.tool == .callout { annotation.startLineStyle = .openArrow }
        }
        drawing.page.addAnnotation(annotation)
        if drawing.tool == .callout { onCreateText?(drawing.page, end, annotation) }
        else { selectAnnotation(annotation) }
        setNeedsDisplay(bounds)
    }
    private func applyMagnification(_ delta: CGFloat, at anchor: CGPoint) {
        guard delta.isFinite, delta != 0 else { return }
        let page = page(for: anchor, nearest: true)
        let pagePoint = page.map { convert(anchor, to: $0) }
        autoScales = false
        scaleFactor = min(maxScaleFactor, max(minScaleFactor, scaleFactor * exp(delta)))
        layoutDocumentView()
        layoutSubtreeIfNeeded()
        if let page, let pagePoint, let scroll = internalScrollView {
            scroll.layoutSubtreeIfNeeded()
            documentView?.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            // Older PDFKit releases adjust the clip origin during scale layout.
            // Recalculate the correction after layout, then once more after scroll.
            for _ in 0..<2 {
                let mapped = convert(pagePoint, from: page)
                let movement = clip.convert(mapped, from: self) - clip.convert(anchor, from: self)
                if hypot(movement.x, movement.y) < 0.25 { break }
                var origin = CGPoint(x: clip.bounds.minX + movement.x, y: clip.bounds.minY + movement.y)
                if let document = scroll.documentView {
                    let content = document.frame
                    if content.width > clip.bounds.width {
                        origin.x = min(max(content.minX, origin.x), content.maxX - clip.bounds.width)
                    } else { origin.x = clip.bounds.minX }
                    if content.height > clip.bounds.height {
                        origin.y = min(max(content.minY, origin.y), content.maxY - clip.bounds.height)
                    } else { origin.y = clip.bounds.minY }
                }
                // scroll(to:) quantizes to clip-space points on macOS 15. With
                // magnified bounds that causes a visible screen-space drift.
                clip.setBoundsOrigin(origin)
                clip.needsDisplay = true
                scroll.reflectScrolledClipView(clip)
                layoutSubtreeIfNeeded()
            }
        }
        refreshOverlay(); onViewportChange?()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            applyMagnification(-event.scrollingDeltaY * 0.01, at: convert(event.locationInWindow, from: nil))
        } else {
            if let scroll = internalScrollView { scroll.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
            onViewportChange?()
        }
    }
    override func magnify(with event: NSEvent) {
        applyMagnification(event.magnification, at: convert(event.locationInWindow, from: nil))
    }
    override func viewDidEndLiveResize() { super.viewDidEndLiveResize(); onViewportChange?() }
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        Task { @MainActor [weak self] in self?.onViewportChange?(); self?.refreshOverlay() }
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
