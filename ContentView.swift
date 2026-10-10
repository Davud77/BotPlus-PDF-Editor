import SwiftUI
import AppKit
import PDFKit
import AVFoundation
import CoreText
import UniformTypeIdentifiers

private enum BotPlusBrand {
    static let name = "BotPlus PDF Editor"
    static let version = "1.1"
    static let copyright = "© 2026 BotPlus"
    static let supportURL = URL(string: "https://github.com/Davud77/BotPlus-PDF-Editor")!
    static let telegramURL = URL(string: "https://t.me/botplus_pdf")!
}

// Native macOS PDF workspace. Source-content editing is implemented in PDFiumSourceEditor.swift.
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

private enum AppTheme: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .dark: Bilingual(en: "Dark", ru: "Тёмная")
        case .light: Bilingual(en: "Light", ru: "Светлая")
        case .system: Bilingual(en: "System", ru: "Системная")
        }
    }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
    var appearance: NSAppearance? { self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    @MainActor var isDark: Bool {
        self == .dark || (self == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
private enum Palette {
    private static func grey(_ dark: CGFloat, _ light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(calibratedWhite: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }
    static let ribbon = grey(0.17, 0.95)
    static let chrome = grey(0.125, 0.91)
    static let raised = grey(0.205, 0.98)
    static let panel = grey(0.20, 0.97)
    static let workspace = grey(0.12, 0.82)
    static let ruler = grey(0.125, 0.94)
    static let rulerTicks = grey(0.533, 0.45)
    static let rulerText = grey(0.8, 0.25)
    static let separator = grey(0.25, 0.76)
    static let selected = grey(0.29, 0.83)
    static let file = Color(red: 0.65, green: 0.18, blue: 0.20)
    static let text = grey(0.88, 0.12)
    static let muted = grey(0.68, 0.40)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.30, green: 0.62, blue: 0.90, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.72, alpha: 1)
    })
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
    case hand, textSelection, selectComments, highlight, underline, strike, typewriter, rectangle, ellipse, cloud, pencil, eraser, line, arrow, callout, note, stamp, link, marquee, formText, formCheckbox, formRadio, formChoice, formButton, addText, editText
    var title: Bilingual {
        switch self {
        case .hand: Bilingual(en: "Hand", ru: "Рука")
        case .textSelection: Bilingual(en: "Text Selection", ru: "Выделить текст")
        case .selectComments: Bilingual(en: "Select Comments", ru: "Выделить комментарии")
        case .highlight: Bilingual(en: "Highlight Text", ru: "Подсветить текст")
        case .underline: Bilingual(en: "Underline", ru: "Подчёркивание")
        case .strike: Bilingual(en: "Strikethrough", ru: "Зачёркивание")
        case .ellipse: Bilingual(en: "Ellipse", ru: "Эллипс")
        case .cloud: Bilingual(en: "Cloud", ru: "Облако")
        case .pencil: Bilingual(en: "Pencil", ru: "Карандаш")
        case .eraser: Bilingual(en: "Eraser", ru: "Ластик")
        case .note: Bilingual(en: "Sticky Note", ru: "Заметка")
        case .stamp: Bilingual(en: "Stamp", ru: "Штамп")
        case .link: Bilingual(en: "Link", ru: "Ссылка")
        case .marquee: Bilingual(en: "Marquee Zoom", ru: "Масштаб области")
        case .formText: Bilingual(en: "Text Field",ru: "Поле формы")
        case .formCheckbox: Bilingual(en: "Checkbox",ru: "Флажок")
        case .formRadio: Bilingual(en: "Radio Button",ru: "Переключатель")
        case .formChoice: Bilingual(en: "Dropdown",ru: "Список")
        case .formButton: Bilingual(en: "Button",ru: "Кнопка")
        case .typewriter: Bilingual(en: "Text Box", ru: "Текстовое поле")
        case .rectangle: Bilingual(en: "Rectangle", ru: "Прямоугольник")
        case .line: Bilingual(en: "Line", ru: "Линия")
        case .arrow: Bilingual(en: "Arrow", ru: "Стрелка")
        case .callout: Bilingual(en: "Callout", ru: "Выноска")
        case .addText: Bilingual(en: "Add PDF Text", ru: "Добавить текст PDF")
        case .editText: Bilingual(en: "Edit PDF Text", ru: "Редактировать текст PDF")
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
        let sharedWidth = activePanel(on: config.dock).map { configuration(for: $0).width } ?? config.width
        for candidate in WorkspacePanel.allCases where configuration(for: candidate).dock == config.dock && config.dock != .floating {
            next[candidate]?.width = sharedWidth
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
    func setWidth(_ width: CGFloat, for panel: WorkspacePanel) {
        let dock = configuration(for: panel).dock
        var next = configurations
        for candidate in WorkspacePanel.allCases where candidate == panel || (dock != .floating && configuration(for: candidate).dock == dock) {
            next[candidate]?.width = Double(min(600,max(200,width)))
        }
        publish(next)
    }
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
                if let window = floatingWindows[panel] {
                    if window.title != manager.text(panel.title) { window.title = manager.text(panel.title) }
                    if window.appearance?.name != manager.theme.appearance?.name { window.appearance = manager.theme.appearance }
                    continue
                }
                let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: config.width, height: 420),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
                window.title = manager.text(panel.title)
                window.appearance = manager.theme.appearance
                window.isReleasedWhenClosed = false; window.isFloatingPanel = true; window.level = .floating
                window.minSize = NSSize(width: 200, height: 180); window.maxSize = NSSize(width: 600, height: 1600)
                window.delegate = self
                window.contentView = NSHostingView(rootView: FloatingPanelContents(panel: panel, panels: self, manager: manager))
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
    @Published var document: PDFDocument
    @Published var pageIndex = 0
    @Published var zoom: CGFloat = 1
    @Published var isUntitled = false
    struct Snapshot { let data: Data; let page: Int; let zoom: CGFloat; let bookmarks: [PDFBookmarkStore.Record]? }
    var undoHistory: [Snapshot] = []
    var redoHistory: [Snapshot] = []
    var historyGroup = ""
    var historyDate = Date.distantPast

    init(url: URL, document: PDFDocument) { self.url = url; self.document = document }
    var filename: String { isUntitled ? "Untitled.pdf" : url.lastPathComponent }
    var pageCount: Int { document.pageCount }
}

@MainActor
private final class DocumentManager: ObservableObject {
    let panels = PanelWorkspaceModel()
    @Published private(set) var documents: [PDFDocumentItem] = []
    @Published var selectedID: UUID?
    @Published var language: AppLanguage = .ru
    @Published var theme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "BotPlusPDFEditor.theme") ?? "dark") ?? .dark {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "BotPlusPDFEditor.theme") }
    }
    @Published var thumbnailZoom = 0.55
    @Published var thumbnailGestureActive = false
    var contentRevision = 0
    @Published var selectedOutline: PDFOutline?
    @Published var stampText = "СОГЛАСОВАНО"
    @Published var annotationFill = false
    lazy var speech = AVSpeechSynthesizer()
    @Published var tab: RibbonTab = .home
    @Published var tool: PDFTool = .hand
    @Published var layout: PageLayout = .continuous
    @Published var rulersVisible = false
    @Published var rulerUnit: RulerUnit = .millimeters
    let viewport = ViewportState()
    let textProperties = PDFTextPropertiesModel()
    var cursorViewport: CGPoint? { get { viewport.cursorViewport } set { viewport.cursorViewport = newValue } }
    var cursorPage: CGPoint? { get { viewport.cursorPage } set { viewport.cursorPage = newValue } }
    @Published var annotationColor: Color = .red
    @Published var annotationStrokeWidth: Double = 2
    @Published var annotationOpacity: Double = 1
    @Published var textFontSize: Double = 18
    @Published var textBorderEnabled = true
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var selectedContent: PDFSourceSession.ContentObject?
    @Published var pageText = "1"
    @Published var searchText = ""
    @Published var notice: String?
    @Published var commandIndex = 0
    @Published var command: ViewerCommand = .refresh
    var rulerMetrics: RulerMetrics { get { viewport.metrics } set { viewport.metrics = newValue } }
    var finishSourceEditing: (() -> Bool)?
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
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            DispatchQueue.main.async { for url in panel.urls { self?.open(url) } }
        }
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
        guard selectedID == id || finishSourceEditing?() != false else { return }
        if selectedID != id { selectedOutline = nil }
        selectedID = id
        pageText = String((documents.first(where: { $0.id == id })?.pageIndex ?? 0) + 1)
        send(.refresh)
    }

    func close(_ id: UUID) {
        guard selectedID != id || finishSourceEditing?() != false else { return }
        let wasSelected = selectedID == id
        documents.removeAll(where: { $0.id == id })
        if wasSelected {
            selectedID = documents.last?.id
            pageText = String((selected?.pageIndex ?? 0) + 1)
            send(.refresh)
        }
    }

    func send(_ next: ViewerCommand) { if next == .refresh { contentRevision &+= 1 }; command = next; commandIndex &+= 1 }
    func navigate(to index: Int) {
        guard finishSourceEditing?() != false else { return }
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
        guard finishSourceEditing?() != false else { return }
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        if selected.isUntitled { saveDocumentAs(); return }
        do { try PDFDocumentSerializer.save(selected.document,to: selected.url) }
        catch { say("Could not save the PDF.","Не удалось сохранить PDF-файл.") }
    }
    func saveDocumentAs() {
        guard finishSourceEditing?() != false else { return }
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = selected.filename
        panel.begin { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            DispatchQueue.main.async {
                do { try PDFDocumentSerializer.save(selected.document,to: url) }
                catch { self?.say("Could not save the PDF.","Не удалось сохранить PDF-файл."); return }
                selected.url = url; selected.isUntitled = false; self?.send(.refresh)
            }
        }
    }
    func printDocument() {
        guard selected?.document != nil else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        send(.print)
    }
    func perform(_ action: RibbonAction) {
        if case .feature(let id) = action {
            if id == "undo" || id == "redo" { undoDocument(redo: id == "redo"); return }
            if id == "blank" { createBlankDocument(); return }
            if id == "newWindow" { PDFWindowPool.shared.open(); return }
            if id == "fromFiles" { createFromFiles(); return }
        }
        if selected == nil {
            switch action {
            case .open, .settings, .toggleLanguage, .toggleRulers, .panels, .languagePicker, .about, .support, .telegram, .themePicker, .development: break
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
        case .tool(let next):
            guard finishSourceEditing?() != false else { return }
            tool = next; send(.refresh)
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
        case .highlight: activateMarkup(.highlight)
        case .underline: activateMarkup(.underline)
        case .feature(let id): send(.feature(id))
        case .insertBlankPage: send(.insertBlankPage)
        case .deletePage: send(.deletePage)
        case .duplicatePage: send(.duplicatePage)
        case .toggleLanguage: language = language == .ru ? .en : .ru
        case .toggleRulers: rulersVisible.toggle()
        case .panels: break
        case .languagePicker: break
        case .about: isAboutPresented = true
        case .support: openExternalLink(BotPlusBrand.supportURL)
        case .telegram: openExternalLink(BotPlusBrand.telegramURL)
        case .themePicker: break
        case .copy: send(.copy)
        case .cut: send(.cut)
        case .paste: send(.paste)
        case .deleteSelection: send(.deleteSelection)
        case .development: say("Feature in development", "Функция в разработке")
        }
    }

    private func openExternalLink(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            say("Could not open the link.", "Не удалось открыть ссылку.")
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
    private static func isOpacityContainer(_ annotation: PDFAnnotation) -> Bool {
        ["Text", "FreeText", "Popup"].contains(annotation.type ?? "") && (annotation.contents ?? "").hasPrefix(prefix)
    }
    static func isContainer(_ annotation: PDFAnnotation) -> Bool {
        isOpacityContainer(annotation) || (!annotation.shouldDisplay && !annotation.shouldPrint && PDFSourceSession.isLayoutMetadata(annotation.contents ?? ""))
    }
    // PDFKit's writer omits custom dictionary keys. A hidden, non-printing FreeText
    // annotation carries editor settings while standard visible annotations stay editable.
    static func prepareForSave(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isOpacityContainer(annotation) { removeContainer(annotation, from: page) }
            let entries = page.annotations.filter { !isContainer($0) }.enumerated().compactMap { index, annotation -> Entry? in
                guard let record = records.object(forKey: annotation)?.record else { return nil }
                return Entry(index: index, subtype: annotation.type ?? "", center: CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), record: record)
            }
            guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { continue }
            let marker = PDFAnnotation(bounds: CGRect(x: page.bounds(for: .cropBox).minX, y: page.bounds(for: .cropBox).minY, width: 1, height: 1), forType: .freeText, withProperties: nil)
            marker.contents = prefix + data.base64EncodedString()
            marker.shouldDisplay = false; marker.shouldPrint = false
            marker.userName = BotPlusBrand.name
            page.addAnnotation(marker)
        }
    }
    private static func removeContainer(_ marker: PDFAnnotation, from page: PDFPage) {
        if let popup = marker.popup { page.removeAnnotation(popup) }
        marker.popup = nil
        page.removeAnnotation(marker)
    }
    static func removeContainers(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isOpacityContainer(annotation) { removeContainer(annotation, from: page) }
        }
    }
    static func restore(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let annotations = page.annotations.filter { !isContainer($0) }
            let containers = page.annotations.filter(isOpacityContainer)
            var used = Set<Int>()
            for marker in containers where marker.type != "Popup" {
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
                    if annotation.type != "Stamp" { annotation.removeValue(forAnnotationKey: .appearanceDictionary) }
                    if annotation.type == "FreeText" {
                        annotation.color = .clear
                        annotation.fontColor = (annotation.fontColor ?? .black).withAlphaComponent(CGFloat(entry.record.opacity))
                    } else { annotation.color = annotation.color.withAlphaComponent(CGFloat(entry.record.opacity)) }
                }
            }
            for marker in containers { removeContainer(marker, from: page) }
        }
    }
    static func transfer(from originals: [PDFAnnotation], to copies: [PDFAnnotation]) {
        var groups: [String: String] = [:]
        for (original, duplicate) in zip(originals, copies) {
            guard var record = records.object(forKey: original)?.record else { continue }
            record.id = UUID().uuidString
            if let group = record.group {
                let copied = groups[group] ?? UUID().uuidString; groups[group] = copied; record.group = copied
            }
            records.setObject(Box(record), forKey: duplicate)
        }
    }
    static func copy(from source: PDFPage, to destination: PDFPage) {
        let old = source.annotations.filter { !isContainer($0) }
        for marker in destination.annotations where isOpacityContainer(marker) { removeContainer(marker, from: destination) }
        transfer(from: old, to: destination.annotations.filter { !isContainer($0) })
    }

}

private enum ViewerCommand: Equatable {
    case refresh, zoomIn, zoomOut, actualSize, fitPage, fitWidth, rotate(Int), page(Int), highlight, underline, insertBlankPage, deletePage, duplicatePage, print, applyAnnotationStyle
    case strike, destination(PDFDestination), feature(String)
    case setZoom(CGFloat)
    case copy, cut, paste, deleteSelection
    case deletePageAt(Int), duplicatePageAt(Int), copyPageAt(Int), pastePagesAt(Int), blankPageAt(Int), rotatePageAt(Int,Int)
}

private enum RibbonAction {
    case feature(String)
    case open, save, saveAs, close, print, settings
    case tool(PDFTool), layout(PageLayout), zoomIn, zoomOut, actualSize, fitPage, fitWidth
    case rotateLeft, rotateRight, previous, next, first, last, highlight, toggleLanguage, toggleRulers
    case panels, languagePicker, themePicker, about, support, telegram, underline, insertBlankPage, deletePage, duplicatePage, copy, cut, paste, deleteSelection, development
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
            ContentView().frame(minWidth: 1060, minHeight: 700)
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
        .background(WindowChromeConfigurator(theme: manager.theme).frame(width: 0, height: 0))
        .foregroundStyle(Palette.text)
        .preferredColorScheme(manager.theme.colorScheme)
        .environment(\.locale,Locale(identifier: manager.language == .ru ? "ru_RU" : "en_US"))
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenPDF)) { _ in manager.openPanel() }
        .onReceive(manager.panels.$configurations) { _ in
            DispatchQueue.main.async { manager.panels.synchronizeFloatingWindows(manager: manager) }
        }
        .onChange(of: manager.language) { _, _ in manager.panels.synchronizeFloatingWindows(manager: manager) }
        .onChange(of: manager.theme) { _, _ in manager.panels.synchronizeFloatingWindows(manager: manager) }
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
    let theme: AppTheme
    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView(frame: .zero); view.theme = theme; return view
    }
    func updateNSView(_ view: WindowChromeView, context: Context) { view.theme = theme; DispatchQueue.main.async { [weak view] in view?.configureWindow() } }

    @MainActor
    final class WindowChromeView: NSView {
        var theme: AppTheme = .dark
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.configureWindow() }
        }
        private var configuredWindow: ObjectIdentifier?
        private var configuredTheme: AppTheme?
        func configureWindow() {
            guard let window else { return }
            guard configuredWindow != ObjectIdentifier(window) || configuredTheme != theme else { return }
            configuredWindow = ObjectIdentifier(window); configuredTheme = theme
            window.appearance = theme.appearance
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(calibratedWhite: theme.isDark ? 0.125 : 0.91, alpha: 1)
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
            Button(manager.language == .ru ? "Закрыть" : "Close") { manager.isAboutPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26).frame(width: 360).background(Palette.ribbon)
        .preferredColorScheme(manager.theme.colorScheme)
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
                quick("Save", "Сохранить", "botplus.floppy", .save)
                quick("Print", "Печать", "printer", .print)
                Hairline(height: 20)
                QuickIcon("Undo", "Отменить", "arrow.uturn.backward", language: manager.language) { manager.perform(.feature("undo")) }
                QuickIcon("Redo", "Повторить", "arrow.uturn.forward", language: manager.language) { manager.perform(.feature("redo")) }
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
        .frame(height: 40).background(Palette.chrome)
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
        Button(action: action) {
            Group {
                if symbol == "botplus.floppy" { FloppyDiskSymbol().stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)).frame(width: 14, height: 14) }
                else { Image(systemName: symbol).font(.system(size: 12)) }
            }.frame(width: 24, height: 24)
        }
            .buttonStyle(.plain).foregroundStyle(Palette.text).help(language == .ru ? ru : en)
    }
}

private struct FloppyDiskSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width / 16, y = rect.height / 16
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: rect.minX + px * x, y: rect.minY + py * y) }
        var path = Path(); path.move(to: point(1, 1)); path.addLine(to: point(11, 1))
        path.addLine(to: point(15, 5)); path.addLine(to: point(15, 15)); path.addLine(to: point(1, 15)); path.closeSubpath()
        path.addRect(CGRect(x: rect.minX + 4*x, y: rect.minY + y, width: 6*x, height: 5*y))
        path.addRect(CGRect(x: rect.minX + 4*x, y: rect.minY + 9*y, width: 8*x, height: 6*y))
        return path
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
                                .lineLimit(1).frame(width: tabWidth(tab), height: 33)
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

    private func tabWidth(_ tab: RibbonTab) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = (manager.text(tab.title) as NSString).size(withAttributes: [.font: font]).width
        return max(50, ceil(width) + (tab == .file ? 28 : 20))
    }

    private func groups(for tab: RibbonTab) -> [RibbonGroupSpec] {
                let tool = { (id: String, en: String, ru: String, icon: String, value: PDFTool) in RibbonCommand(id, en, ru, icon, .tool(value)) }
        let cmd = { (id: String, en: String, ru: String, icon: String) in RibbonCommand(id, en, ru, icon, .feature(id)) }
        switch tab {
        case .file:
            return [RibbonGroupSpec("file", "Document", "Документ", [
                RibbonCommand("open", "Open", "Открыть", "folder", .open), RibbonCommand("save", "Save", "Сохранить", "botplus.floppy", .save),
                RibbonCommand("saveAs", "Save As", "Сохранить как", "square.and.arrow.up", .saveAs), RibbonCommand("close", "Close", "Закрыть", "xmark", .close),
                RibbonCommand("print", "Print", "Печать", "printer", .print), RibbonCommand("settings", "Settings", "Настройки", "gearshape", .settings)
            ])]
        case .home:
            return [
                RibbonGroupSpec("tools", "Tools", "Инструменты", [tool("hand", "Hand", "Рука", "hand.raised", .hand), tool("text", "Select Text", "Выделить текст", "text.cursor", .textSelection), tool("selectComments", "Select Comments", "Выделить комментарии", "cursorarrow", .selectComments)]),
                RibbonGroupSpec("view", "View", "Вид", [RibbonCommand("zoomOut", "Zoom Out", "Уменьшить", "minus.magnifyingglass", .zoomOut), RibbonCommand("actual", "Actual Size 1:1", "Реальный размер 1:1", "1.magnifyingglass", .actualSize), RibbonCommand("zoomIn", "Zoom In", "Увеличить", "plus.magnifyingglass", .zoomIn), RibbonCommand("fitWidth", "Fit Width", "По ширине", "arrow.left.and.right", .fitWidth), RibbonCommand("rotateLeft", "Rotate 90° CCW", "Повернуть на 90° влево", "rotate.left", .rotateLeft), RibbonCommand("rotateRight", "Rotate 90° CW", "Повернуть на 90° вправо", "rotate.right", .rotateRight)]),
                RibbonGroupSpec("objects", "Objects", "Объекты", [tool("addText", "Add Text", "Добавить текст", "text.badge.plus", .addText), tool("editText", "Edit PDF Text", "Редактировать текст", "character.cursor.ibeam", .editText), RibbonCommand("pasteObject", "Paste", "Вставить", "doc.on.clipboard", .paste), RibbonCommand("copyObject", "Copy", "Копировать", "doc.on.doc", .copy), RibbonCommand("cutObject", "Cut", "Вырезать", "scissors", .cut), RibbonCommand("deleteObject", "Delete", "Удалить", "trash", .deleteSelection), cmd("addImage", "Add Image", "Добавить изображение", "photo.badge.plus")]),
                RibbonGroupSpec("comment", "Comment", "Комментарий", [tool("typewriter", "Text Box", "Текстовое поле", "character.cursor.ibeam", .typewriter), RibbonCommand("highlight", "Highlight Text", "Подсветить текст", "highlighter", .highlight), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline), cmd("stamp", "Stamp", "Штамп", "seal"), cmd("sticky", "Sticky Note", "Заметка", "note.text")]),
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
                RibbonGroupSpec("text", "Text", "Текст", [tool("textBox", "Text Box", "Текстовое поле", "text.alignleft", .typewriter), tool("callout", "Callout", "Выноска", "text.bubble", .callout)]),
                RibbonGroupSpec("note", "Note", "Заметка", [cmd("note", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("markup", "Text Markup", "Разметка текста", [RibbonCommand("highlight", "Highlight", "Подсветка", "highlighter", .highlight), cmd("strike", "Strikethrough", "Зачёркивание", "strikethrough"), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline)]),
                RibbonGroupSpec("drawing", "Drawing", "Рисование", [tool("line", "Line", "Линия", "line.diagonal", .line), tool("arrow", "Arrow", "Стрелка", "arrow.up.right", .arrow), tool("rect", "Rectangle", "Прямоугольник", "rectangle", .rectangle), tool("ellipse", "Ellipse", "Эллипс", "oval", .ellipse), cmd("cloud", "Cloud", "Облако", "cloud"), cmd("pencil", "Pencil", "Карандаш", "pencil.tip"), cmd("eraser", "Eraser", "Ластик", "eraser")]),
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
            return [RibbonGroupSpec("create", "Create", "Создать", [cmd("bookmarkAdd", "Add Bookmark", "Добавить закладку", "bookmark.badge.plus"), cmd("bookmarkDelete", "Delete Bookmark", "Удалить закладку", "bookmark.slash"), cmd("bookmarkFromPageText", "From Page Text", "Из текста на странице", "text.viewfinder"), cmd("bookmarkEveryN", "Every N-th Page", "Закладка для каждой N-й стр.", "book.pages"), cmd("bookmarkFromTOC", "From TOC", "Из Содержания", "list.bullet.rectangle"), cmd("bookmarkFromFile", "From Text File", "Из текстового файла", "doc.text")]),
                    RibbonGroupSpec("modify", "Modify", "Изменить", [cmd("bookmarkAddText", "Add Text", "Добавить текст", "text.badge.plus"), cmd("bookmarkCase", "Change Case", "Изменить регистр", "textformat"), cmd("bookmarkZoom", "Change Zoom", "Изменить масштаб", "magnifyingglass"), cmd("bookmarkDestination", "Named Destination to Link", "Имен. назначение в ссылку", "link"), cmd("bookmarkFind", "Find & Replace", "Найти и заменить", "text.magnifyingglass"), cmd("bookmarkActions", "Delete Actions", "Удалить действия", "trash"), cmd("bookmarkSort", "Sort", "Сортировать", "arrow.up.arrow.down"), cmd("bookmarkValidate", "Validate", "Утвердить", "checkmark.seal"), cmd("bookmarkMerge", "Merge Duplicates", "Объединить дубликаты", "arrow.triangle.merge")]),
                    RibbonGroupSpec("convert", "Convert", "Преобразовать", [cmd("bookmarkTOC", "Create Table of Contents", "Создать Содержание", "list.bullet.indent"), cmd("bookmarkLinks", "Link for Bookmarks", "Ссылка для закладок", "link.badge.plus"), cmd("bookmarkSortPages", "Sort Pages", "Сортировка страниц", "doc.text.magnifyingglass"), cmd("bookmarkNamed", "Convert to Named Destinations", "Преобр. в им. назначения", "bookmark.fill"), cmd("bookmarkHTML", "Export to HTML", "Экспорт в HTML", "chevron.left.forwardslash.chevron.right"), cmd("bookmarkText", "Export to Text File", "Экспортировать в текстовый файл", "doc.text")])]
        case .help:
            return [RibbonGroupSpec("ui", "UI Settings", "Настройки интерфейса", [RibbonCommand("theme", "Theme", "Тема", "circle.lefthalf.filled", .themePicker), cmd("customize", "Customize Ribbon", "Настроить ленту", "slider.horizontal.3"), RibbonCommand("language", "Language", "Язык", "globe", .languagePicker)]),
                    RibbonGroupSpec("help", "Contact", "Контакты", [RibbonCommand("support", "Support", "Поддержка", "person.crop.circle.badge.questionmark", .support), RibbonCommand("telegram", "Telegram", "Телеграм", "paperplane", .telegram)]),
                    RibbonGroupSpec("product", "Product", "Программа", [RibbonCommand("about", "About", "О программе", "info.circle", .about), cmd("updates", "Check Updates", "Проверить обновления", "arrow.clockwise"), cmd("license", "License", "Лицензия", "key")])]
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
                        case .themePicker: ThemeMenuButton(manager: manager, command: command)
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
        Group {
            if command.symbol == "botplus.floppy" { FloppyDiskSymbol().stroke(style: StrokeStyle(lineWidth: 1.7, lineJoin: .round)).frame(width: 22, height: 22) }
            else { Image(systemName: command.symbol).font(.system(size: 20, weight: .regular)) }
        }.frame(height: 24)
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

private struct ThemeMenuButton: View {
    @ObservedObject var manager: DocumentManager
    let command: RibbonCommand
    var body: some View {
        Menu {
            ForEach(AppTheme.allCases) { theme in
                Button { manager.theme = theme } label: {
                    if manager.theme == theme { Label(manager.text(theme.title), systemImage: "checkmark") }
                    else { Text(manager.text(theme.title)) }
                }
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
                    .menuStyle(.borderlessButton).frame(width: 30, height: 25).background(Palette.ruler)
                    RulerBar(axis: .horizontal, manager: manager).frame(height: 25)
                }
            }
            HStack(spacing: 0) {
                if manager.rulersVisible { RulerBar(axis: .vertical, manager: manager).frame(width: 30) }
                PDFViewer(manager: manager).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
        }.background(Palette.workspace).frame(minWidth: 180)
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
                }.frame(width: width).frame(maxHeight: .infinity).background(Palette.panel)
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
            .overlay(ResizeCursorRegion().allowsHitTesting(false))
            .overlay(Palette.separator.opacity(0.7).frame(width: 1))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    manager.panels.resize(panel, translation: direction * value.translation.width, initialWidth: initialWidth)
                }
                .onEnded { _ in manager.panels.endResize(panel) })
            .help(manager.language == .ru ? "Перетащите, чтобы изменить ширину" : "Drag to resize panel")
    }
}

private struct ResizeCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorView(frame: .zero) }
    func updateNSView(_ view: NSView,context: Context) { }
    private final class CursorView: NSView {
        private var tracking: NSTrackingArea?
        private var cursorInside = false
        override func resetCursorRects() { addCursorRect(bounds,cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            if let tracking { removeTrackingArea(tracking) }
            let next = NSTrackingArea(rect: .zero,options: [.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner: self)
            addTrackingArea(next); tracking = next; super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { if !cursorInside { NSCursor.resizeLeftRight.push(); cursorInside = true } }
        override func mouseExited(with event: NSEvent) { restoreCursor() }
        override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { restoreCursor() }; super.viewWillMove(toWindow: newWindow) }
        private func restoreCursor() { if cursorInside { NSCursor.pop(); cursorInside = false } }
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
        Group {
            if let item = manager.selected {
                let document = item.document
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $manager.thumbnailZoom,in: 0...1)
                        Image(systemName: "plus.magnifyingglass")
                    }.padding(.horizontal,10).help(manager.language == .ru ? "Размер миниатюр" : "Thumbnail size")
                    GeometryReader { geometry in
                        let available = max(44,geometry.size.width-16)
                        let target = 44+(available-44)*CGFloat(manager.thumbnailZoom)
                        let count = max(1,Int((available+8)/(target+8)))
                        let cell = (available-CGFloat(count-1)*8)/CGFloat(count)
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 8),count: count),spacing: 10) {
                                ForEach(0..<document.pageCount,id: \.self) { index in
                                    if let page = document.page(at: index) {
                                        let box = page.bounds(for: .cropBox),rotated = page.rotation%180 != 0
                                        let ratio = rotated ? box.width/max(1,box.height) : box.height/max(1,box.width)
                                        Button { manager.navigate(to: index) } label: {
                                            VStack(spacing: 4) {
                                                Image(nsImage: PDFThumbnailCache.shared.image(page: page,documentID: item.id,index: index,revision: manager.contentRevision,width: cell,ratio: ratio,interactive: manager.thumbnailGestureActive))
                                                    .resizable().aspectRatio(contentMode: .fit).frame(width: cell,height: cell*ratio)
                                                    .background(.white)
                                                    .overlay(Rectangle().stroke(manager.selected?.pageIndex == index ? Palette.accent : Palette.separator,lineWidth: 2))
                                                Text("\(index+1)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                            }
                                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button(manager.language == .ru ? "Удалить страницу" : "Delete page") { manager.send(.deletePageAt(index)) }.disabled(document.pageCount <= 1)
                                Button(manager.language == .ru ? "Дублировать страницу" : "Duplicate page") { manager.send(.duplicatePageAt(index)) }
                                Divider()
                                Button(manager.language == .ru ? "Копировать страницу" : "Copy page") { manager.send(.copyPageAt(index)) }
                                Button(manager.language == .ru ? "Вставить страницы после" : "Paste pages after") { manager.send(.pastePagesAt(index+1)) }
                                Button(manager.language == .ru ? "Вставить пустую перед" : "Insert blank before") { manager.send(.blankPageAt(index)) }
                                Button(manager.language == .ru ? "Вставить пустую после" : "Insert blank after") { manager.send(.blankPageAt(index+1)) }
                                Divider()
                                Button(manager.language == .ru ? "Повернуть по часовой стрелке" : "Rotate clockwise") { manager.send(.rotatePageAt(index,90)) }
                                Button(manager.language == .ru ? "Повернуть против часовой стрелки" : "Rotate counterclockwise") { manager.send(.rotatePageAt(index,-90)) }
                            }
                                    }
                                }
                            }.padding(8)
                        }
                    }.background(ThumbnailGestureRegion(manager: manager))
                }
            } else { empty(manager.language == .ru ? "Откройте PDF" : "Open a PDF",symbol: "doc.text") }
        }
    }

    private var bookmarkList: some View {
        Group {
            if let root = manager.selected?.document.outlineRoot {
                let rows = makeBookmarkRows(root: root, document: manager.selected?.document)
                if rows.isEmpty { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
                else {
                    List {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Button {
                                guard manager.finishSourceEditing?() != false else { return }
                                manager.selectedOutline = row.node
                                if row.pageIndex >= 0,let destination = row.node.destination { manager.send(.destination(destination)) }
                            } label: {
                                Text(row.title).font(.system(size: 11)).lineLimit(2).padding(.leading, CGFloat(row.depth * 10)).foregroundStyle(manager.selectedOutline === row.node ? Palette.accent : Palette.text)
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(manager.language == .ru ? "Добавить дочернюю" : "Add child") { manager.addBookmarkPrompt(parent: row.node) }
                                Button(manager.language == .ru ? "Переименовать" : "Rename") { manager.renameBookmark(row.node) }
                                Button(manager.language == .ru ? "Удалить" : "Delete") { manager.deleteBookmark(row.node) }
                            }
                        }
                    }.listStyle(.plain)
                }
            } else { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
        }
    }

    private var properties: some View { WorkspacePropertiesContent(manager: manager) }

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

private struct WorkspacePropertiesContent: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var source: PDFTextPropertiesModel
    init(manager: DocumentManager) { self.manager = manager; source = manager.textProperties }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 12) {
                if source.active || manager.selectedAnnotation != nil || manager.selectedContent != nil {
                    SourceOrAnnotationProperties(manager: manager)
                } else if let item = manager.selected {
                    if ![PDFTool.hand,.textSelection,.editText,.selectComments].contains(manager.tool) { AnnotationStyleControls(manager: manager) }
                    DocumentPropertiesView(item: item,russian: manager.language == .ru)
                } else { Text(manager.language == .ru ? "Нет выбранного документа" : "No active document") }
            }.frame(maxWidth: .infinity,alignment: .leading).padding(10)
        }
    }
    private func row(_ title: String,_ value: String) -> some View {
        VStack(alignment: .leading,spacing: 3) { Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 11)).textSelection(.enabled) }
    }
}

private struct DocumentPropertiesView: View {
    @ObservedObject var item: PDFDocumentItem
    let russian: Bool
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
                    Text(russian ? "Свойства документа" : "Document properties").font(.headline)
                    row(russian ? "Файл" : "File",item.filename)
                    row(russian ? "Страниц" : "Pages",String(item.pageCount))
                    if let page = item.document.page(at: item.pageIndex) {
                        let size = page.bounds(for: .cropBox).size
                        row(russian ? "Размер страницы" : "Page size",String(format: "%.1f × %.1f pt",size.width,size.height))
                        row(russian ? "Поворот" : "Rotation","\(page.rotation)°")
                    }
                    row(russian ? "Масштаб" : "Zoom",String(format: "%.0f%%",Double(item.zoom*100)))
                    if let title = item.document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String { row(russian ? "Название" : "Title",title) }
                    if let author = item.document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String { row(russian ? "Автор" : "Author",author) }
        }
    }
    private func row(_ title: String,_ value: String) -> some View {
        VStack(alignment: .leading,spacing: 3) { Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 11)).textSelection(.enabled) }
    }
}

private struct SourceOrAnnotationProperties: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var source: PDFTextPropertiesModel
    init(manager: DocumentManager) { self.manager = manager; source = manager.textProperties }
    var body: some View {
        Group {
            if source.active { PDFTextPropertiesView(model: source,russian: manager.language == .ru) }
            else if let object = manager.selectedContent {
                VStack(alignment: .leading,spacing: 8) {
                    Text(manager.language == .ru ? (object.kind == "image" ? "Изображение" : "Векторный объект") : (object.kind == "image" ? "Image" : "Vector object")).font(.headline)
                    Text(String(format: "%.1f × %.1f pt",object.bounds.width,object.bounds.height))
                    Text(String(format: "X %.1f  Y %.1f pt",object.bounds.minX,object.bounds.minY))
                    if let pixels = object.pixelSize { Text("\(Int(pixels.width)) × \(Int(pixels.height)) px") }
                }.font(.system(size: 11))
            } else if let annotation = manager.selectedAnnotation {
                VStack(alignment: .leading,spacing: 8) {
                    Text(manager.language == .ru ? "Свойства комментария" : "Comment properties").font(.headline)
                    Text(annotation.type ?? "Annotation")
                    if annotation.type == "Text" {
                        TextEditor(text: Binding(get: { annotation.contents ?? "" },set: { annotation.contents = $0; manager.send(.refresh) })).frame(minHeight: 80)
                    } else if let contents = annotation.contents,!contents.isEmpty { Text(contents).textSelection(.enabled) }
                    if annotation.type == "Link" {
                        Text((annotation.action as? PDFActionURL)?.url?.absoluteString ?? "Page link").font(.system(size: 10))
                        Button(manager.language == .ru ? "Изменить ссылку" : "Edit link") { manager.editLink(annotation) }
                    }
                    if annotation.type == "Widget" {
                        TextField("Field name / Имя поля",text: Binding(get: { annotation.fieldName ?? "" },set: { annotation.fieldName = $0; manager.send(.refresh) }))
                    } else if annotation.type != "Stamp" { AnnotationStyleControls(manager: manager) }
                }
            }

        }
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
            HStack { Text(manager.language == .ru ? "Непрозр." : "Opacity"); Slider(value: $manager.annotationOpacity, in: 0...1) }
            Stepper("\(manager.language == .ru ? "Шрифт" : "Font"): \(Int(manager.textFontSize))", value: $manager.textFontSize, in: 6...72)
            Toggle(manager.language == .ru ? "Заливка фигуры" : "Shape fill",isOn: $manager.annotationFill)
            Toggle(manager.language == .ru ? "Рамка текста" : "Text border", isOn: $manager.textBorderEnabled)
            if manager.selectedAnnotation != nil {
                Button(manager.language == .ru ? "Применить к выбранной" : "Apply to selected") { manager.send(.applyAnnotationStyle) }
            }
        }.font(.system(size: 10))
        .onChange(of: manager.annotationColor) { _,_ in apply() }
        .onChange(of: manager.annotationOpacity) { _,_ in apply() }
        .onChange(of: manager.annotationStrokeWidth) { _,_ in apply() }
        .onChange(of: manager.annotationFill) { _,_ in apply() }
    }
    private func apply() { if manager.selectedAnnotation != nil { manager.send(.applyAnnotationStyle) } }
}

private struct BookmarkRow { let title: String; let pageIndex: Int; let depth: Int; let node: PDFOutline }
private func makeBookmarkRows(root: PDFOutline, document: PDFDocument?, depth: Int = 0) -> [BookmarkRow] {
    var rows: [BookmarkRow] = []
    for index in 0..<root.numberOfChildren {
        guard let child = root.child(at: index) else { continue }
        let proposed = child.destination?.page.flatMap { document?.index(for: $0) } ?? -1
        let pageIndex = proposed >= 0 && proposed < (document?.pageCount ?? 0) ? proposed : -1
        rows.append(BookmarkRow(title: child.label ?? "Bookmark",pageIndex: pageIndex,depth: depth,node: child))
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
            .background(Palette.panel).foregroundStyle(Palette.text).preferredColorScheme(manager.theme.colorScheme)
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
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.ruler))
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
                    context.stroke(tick, with: .color(Palette.rulerTicks), lineWidth: 1)
                    if majorTick {
                        let digits = major >= 1 ? 0 : (major >= 0.1 ? 1 : 2)
                        let label = Text(String(format: "%.*f", digits, abs(value) < minor / 2 ? 0 : value)).font(.system(size: 8)).foregroundColor(Palette.rulerText)
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

private enum ObjectClipboard {
    static let pages = NSPasteboard.PasteboardType("com.botplus.pdfeditor.pages")
    static let annotations = NSPasteboard.PasteboardType("com.botplus.pdfeditor.annotation-objects")
    static let sourceText = NSPasteboard.PasteboardType("com.botplus.pdfeditor.source-text")
    struct TextStyle: Codable {
        let text: String
        let fontSize: Double
        let fontName: String
        let rgba: [Double]
        init(text: String, size: CGFloat, name: String, color: NSColor) {
            self.text = text; fontSize = Double(size); fontName = name
            let c = color.usingColorSpace(.deviceRGB) ?? .black
            rgba = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        }
        var color: NSColor {
            guard rgba.count == 4 else { return .black }
            return NSColor(calibratedRed: min(1,max(0,rgba[0])), green: min(1,max(0,rgba[1])), blue: min(1,max(0,rgba[2])), alpha: min(1,max(0,rgba[3])))
        }
    }
}

private struct PDFViewer: NSViewRepresentable {
    @ObservedObject var manager: DocumentManager
    func makeCoordinator() -> Coordinator { Coordinator(manager: manager) }
    func makeNSView(context: Context) -> PDFViewerView {
        let view = PDFViewerView(frame: .zero)
        view.clipsToBounds = true
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
        context.coordinator.requestUpdate(view)
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
        var sourceDocument: ObjectIdentifier?
        var fontDocument: ObjectIdentifier?
        var fontNames: [String] = []
        var sourceOutlineData: Data?
        var sourceOutlineCache: [Int:[PDFSourceSession.BlockDescriptor]] = [:]
        var outlinePending = false
        var outlineGeneration = 0
        var sourceAnchor: (index: Int, point: CGPoint)?
        var lastSearchText = ""

        init(manager: DocumentManager) { self.manager = manager }
        func attach(_ view: PDFViewerView) {
            self.view = view; view.delegate = self
            manager.finishSourceEditing = { [weak self] in self?.finishSourceEditor() ?? true }
            view.onCreateText = { [weak self, weak view] page, point, leader in
                guard let self, let view else { return }
                self.createFreeText(on: page, at: point, in: view, leader: leader)
            }
            view.onSourceTextRequest = { [weak self, weak view] page, point, adding, activate in
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    guard let self, let view else { return }
                    self.openSourceEditor(on: page, point: point, adding: adding, activating: activate, view: view)
                }
            }
            view.onClipboardCommand = { [weak self, weak view] command in
                guard let self, let view else { return }
                self.perform(command, on: view)
            }
            view.onEditText = { [weak self, weak view] annotation in
                guard let self, let view, let page = annotation.page else { return }
                self.openTextEditor(annotation, page: page, in: view, isNew: false, leader: nil)
            }
            view.onSelectionChanged = { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    self?.manager.selectedAnnotation = view?.selectedAnnotation
                    if let self,let annotation = view?.selectedAnnotation {
                        self.manager.annotationColor = Color(nsColor: annotation.type == "FreeText" ? annotation.fontColor ?? .black : annotation.color)
                        self.manager.annotationOpacity = Double(AnnotationMetadata.alpha(of: annotation))
                        self.manager.annotationStrokeWidth = Double(annotation.border?.lineWidth ?? 2)
                        if annotation.type == "FreeText" { self.manager.textFontSize = Double(annotation.font?.pointSize ?? 18); self.manager.textBorderEnabled = (annotation.border?.lineWidth ?? 0) > 0 }
                        if ["Square","Circle"].contains(annotation.type ?? "") { self.manager.annotationFill = annotation.interiorColor != nil }
                        self.manager.panels.select(.properties)
                    }
                    if view?.selectedAnnotation != nil || (view?.sourceSelection == nil && view?.sourceInline == nil) { self?.manager.selectedContent = nil }
                }
            }
            view.onWillModify = { [weak self] in if let self,let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") } }
            view.onAnnotationChanged = { [weak self] in self?.manager.send(.refresh) }
            view.onMarkupFinished = { [weak self,weak view] in
                guard let self,let view else { return }
                let subtype: PDFAnnotationSubtype = view.activeTool == .underline ? .underline : (view.activeTool == .strike ? .strikeOut : .highlight)
                if (view.currentSelection?.string ?? "").isEmpty { view.selectAnnotation(nil) }
                else { self.addMarkup(on: view,subtype: subtype) }
            }
            view.onPlaceObject = { [weak self,weak view] page,point,tool in
                guard let self,let view else { return }; self.placeObject(tool,on: page,point: point,view: view)
            }

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
            manager.finishSourceEditing = nil
            for token in observationTokens { NotificationCenter.default.removeObserver(token) }
            observationTokens.removeAll()
            if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
            clipToken = nil; observedClip = nil
            textPopover?.close(); textPopover = nil
            view?.sourceInline?.cancel(); view?.sourceInline = nil
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

        private var updatePending = false
        func requestUpdate(_ view: PDFViewerView) {
            guard !updatePending else { return }; updatePending = true
            DispatchQueue.main.async { [weak self,weak view] in
                guard let self else { return }; self.updatePending = false
                guard let view else { return }; self.update(view)
            }
        }
        private var previousBounds = CGRect.zero
        func update(_ view: PDFViewerView) {
            var changed = previousBounds != view.bounds
            previousBounds = view.bounds
            if activeDocumentID != manager.selected?.id || view.document !== manager.selected?.document {
                changed = true
                activeDocumentID = manager.selected?.id
                lastSearchText = ""
                if let popover = textPopover { Task { @MainActor in popover.close() } }
                if let inline = view.sourceInline { Task { @MainActor in inline.cancel() } }
                view.setSourceSelection(nil)
                view.selectAnnotation(nil)
                Task { @MainActor [weak self] in self?.manager.selectedContent = nil }
                view.document = manager.selected?.document
                if let item = manager.selected {
                    view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, item.zoom))
                    if let page = item.document.page(at: item.pageIndex) { view.go(to: page) }
                }
            }
            if view.displayMode != manager.layout.pdfMode { view.displayMode = manager.layout.pdfMode; changed = true }
            if view.displaysAsBook != (manager.layout == .spread) { view.displaysAsBook = manager.layout == .spread; changed = true }
            if view.activeTool != manager.tool { view.activeTool = manager.tool; changed = true }
            let markup = ![PDFTool.textSelection,.highlight,.underline,.strike].contains(manager.tool)
            if view.isInMarkupMode != markup { view.isInMarkupMode = markup }
            view.fillEnabled = manager.annotationFill
            let background = NSColor(calibratedWhite: manager.theme.isDark ? 0.12 : 0.82,alpha: 1)
            if !view.backgroundColor.isEqual(background) { view.backgroundColor = background; changed = true }
            let stroke = NSColor(manager.annotationColor).withAlphaComponent(CGFloat(manager.annotationOpacity))
            if !view.strokeColor.isEqual(stroke) { view.strokeColor = stroke; changed = true }
            if view.strokeWidth != CGFloat(manager.annotationStrokeWidth) { view.strokeWidth = CGFloat(manager.annotationStrokeWidth); changed = true }
            if changed { view.refreshOverlay() }
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
            if changed { scheduleViewportSync(for: view) }
        }

        private func perform(_ command: ViewerCommand, on view: PDFViewerView) {
            guard let item = manager.selected, view.document === item.document else { return }
            switch command {
            case .rotate,.deletePageAt,.duplicatePageAt,.blankPageAt,.rotatePageAt,.insertBlankPage,.deletePage,.duplicatePage:
                guard finishSourceEditor() else { return }; manager.recordUndo(item,group: "pages")
            case .applyAnnotationStyle: if view.selectedAnnotation != nil { manager.recordUndo(item,group: "annotationStyle") }
            default: break
            }
            switch command {
            case .destination(let destination): view.go(to: destination)
            case .copy: copyObjects(on: view, cutting: false)
            case .cut: copyObjects(on: view, cutting: true)
            case .paste: pasteObjects(on: view)
            case .deleteSelection: deleteObjects(on: view)
            case .refresh: break
            case .zoomIn: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = min(view.maxScaleFactor, view.scaleFactor * 1.2)
            case .zoomOut: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = max(view.minScaleFactor, view.scaleFactor / 1.2)
            case .actualSize: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = 1
            case .fitPage:
                view.resetPagePadding()
                view.autoScales = true
                view.layoutSubtreeIfNeeded()
                view.autoScales = false
            case .fitWidth:
                guard let page = view.currentPage ?? item.document.page(at: 0) else { return }
                let width = page.bounds(for: view.displayBox).width
                guard width > 0 else { return }
                view.resetPagePadding(); view.autoScales = false
                view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, (view.bounds.width - 32) / width))
            case .rotate(let angle):
                guard let page = view.currentPage else { return }
                page.rotation = (page.rotation + angle + 360) % 360
                let index = item.document.index(for: page)
                reload(view, document: item, pageIndex: index)
                manager.send(.refresh)
            case .page(let index):
                if let page = item.document.page(at: index) { center(page,in: view) }
            case .deletePageAt(let index):
                guard finishSourceEditor(),item.pageCount > 1,item.document.page(at: index) != nil else { return }
                item.document.removePage(at: index); item.pageIndex = min(index,item.pageCount-1)
                reload(view,document: item,pageIndex: item.pageIndex); manager.pageText = String(item.pageIndex+1); manager.send(.refresh)
            case .duplicatePageAt(let index):
                guard finishSourceEditor(),let source = item.document.page(at: index),let duplicate = source.copy() as? PDFPage else { return }
                AnnotationMetadata.copy(from: source,to: duplicate); item.document.insert(duplicate,at: index+1); item.pageIndex = index+1
                reload(view,document: item,pageIndex: index+1); manager.pageText = String(index+2); manager.send(.refresh)
            case .copyPageAt(let index): copyPage(index,item: item)
            case .pastePagesAt(let index): pastePages(index,item: item,view: view)
            case .blankPageAt(let index):
                guard finishSourceEditor() else { return }
                let blank = PDFPage(); blank.setBounds(item.document.page(at: min(max(0,index),item.pageCount-1))?.bounds(for: .mediaBox) ?? CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox)
                let target = min(max(0,index),item.pageCount); item.document.insert(blank,at: target); item.pageIndex = target
                reload(view,document: item,pageIndex: target); manager.pageText = String(target+1); manager.send(.refresh)
            case .rotatePageAt(let index,let angle):
                guard finishSourceEditor(),let page = item.document.page(at: index) else { return }
                page.rotation = (page.rotation+angle+360)%360; item.pageIndex = index
                reload(view,document: item,pageIndex: index); manager.send(.refresh)
            case .highlight: addMarkup(on: view, subtype: .highlight)
            case .underline: addMarkup(on: view, subtype: .underline)
            case .strike: addMarkup(on: view, subtype: .strikeOut)
            case .feature(let id): performFeature(id,on: view,item: item)
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
                    if annotation.type == "Stamp" { break }
                    annotation.removeValue(forAnnotationKey: .appearanceDictionary)
                    annotation.color = annotation.type == "FreeText" ? .clear : view.strokeColor
                    AnnotationMetadata.setOpacity(manager.annotationOpacity, on: annotation)
                    let border = PDFBorder(); border.lineWidth = view.strokeWidth
                    annotation.border = annotation.type == "FreeText" && !manager.textBorderEnabled ? nil : border
                    if ["Square","Circle"].contains(annotation.type ?? "") { annotation.interiorColor = manager.annotationFill ? view.strokeColor.withAlphaComponent(view.strokeColor.alphaComponent*0.25) : nil }
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
                    if ["Highlight","Underline","StrikeOut"].contains(annotation.type ?? "") {
                        for part in annotationComponents(annotation) where part !== annotation {
                            part.removeValue(forAnnotationKey: .appearanceDictionary); part.color = view.strokeColor; part.border = border
                            AnnotationMetadata.setOpacity(manager.annotationOpacity,on: part)
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

        private func sourceData(_ item: PDFDocumentItem) throws -> Data {
            guard item.document.allowsDocumentChanges else { throw PDFSourceError.permission }
            AnnotationMetadata.prepareForSave(item.document)
            defer { AnnotationMetadata.removeContainers(item.document) }
            let data = try PDFDocumentSerializer.data(item.document)
            return data
        }
        private func sourceError(_ error: Error) {
            if let error = error as? PDFSourceError { manager.say(error.english, error.russian) }
            else { manager.say("Could not modify the PDF text.", "Не удалось изменить текст PDF.") }
        }
        private func installSourceData(_ data: Data, item: PDFDocumentItem, index: Int, view: PDFViewerView, bounds: CGRect?, anchor: CGPoint? = nil) throws {
            guard let document = PDFDocument(data: data), document.pageCount == item.pageCount else { throw PDFSourceError.save }
            AnnotationMetadata.restore(document)
            PDFBookmarkStore.restore(PDFBookmarkStore.capture(item.document),on: document)
            manager.recordUndo(item,group: "sourceText")
            item.document = document; item.pageIndex = index
            reload(view, document: item, pageIndex: index)
            if let bounds, let page = document.page(at: index) {
                view.setSourceSelection((page, bounds)); sourceAnchor = (index, anchor ?? CGPoint(x: bounds.midX, y: bounds.midY))
            } else { view.setSourceSelection(nil); sourceAnchor = nil }
            manager.pageText = String(index + 1); manager.send(.refresh)
        }
        private func finishSourceEditor() -> Bool {
            guard let inline = view?.sourceInline else { return true }
            return inline.finish()
        }
        private func refreshSourceOutlines(_ view: PDFViewerView) {
            guard manager.tool == .editText,let item = manager.selected,view.document === item.document else {
                view.sourceBlocks = []; view.refreshOverlay(); return
            }
            let identity = ObjectIdentifier(item.document)
            if sourceDocument != identity {
                sourceDocument = identity; sourceOutlineData = nil; sourceOutlineCache = [:]
                outlineGeneration += 1; outlinePending = false
            }
            let pages = view.visiblePages.isEmpty ? (view.currentPage.map { [$0] } ?? []) : view.visiblePages
            let indices = pages.map { item.document.index(for: $0) }.filter { $0 >= 0 && $0 < item.pageCount }
            @MainActor func install() {
                view.sourceBlocks = indices.flatMap { index -> [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] in
                    guard let page = item.document.page(at: index) else { return [] }
                    return (sourceOutlineCache[index] ?? []).map { (page,$0) }
                }
                view.refreshOverlay()
            }
            if indices.allSatisfy({ sourceOutlineCache[$0] != nil }) { install(); return }
            guard !outlinePending else { return }; outlinePending = true
            let generation = outlineGeneration
            Task { @MainActor [weak self,weak view,weak item] in
                await Task.yield()
                guard let self,let view,let item,self.outlineGeneration == generation,
                      view.document === item.document,self.manager.tool == .editText else { return }
                defer { self.outlinePending = false }
                do {
                    let data = try self.sourceOutlineData ?? self.sourceData(item)
                    self.sourceOutlineData = data
                    for index in indices where self.sourceOutlineCache[index] == nil {
                        self.sourceOutlineCache[index] = try PDFSourceSession.blocks(data: data,pageIndex: index)
                    }
                    view.sourceBlocks = indices.flatMap { index -> [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] in
                        guard let page = item.document.page(at: index) else { return [] }
                        return (self.sourceOutlineCache[index] ?? []).map { (page,$0) }
                    }
                    view.refreshOverlay()
                } catch { self.sourceError(error) }
            }
        }
        private func openSourceEditor(on page: PDFPage, point: CGPoint, adding: Bool, activating: Bool = true, view: PDFViewerView) {
            guard let item = manager.selected,item.document === view.document else { return }
            let requestedIndex = item.document.index(for: page)
            do {
                let index = requestedIndex
                let click = view.convert(point,from: page)
                let descriptor = view.sourceBlocks.last { $0.page === page && $0.block.snapshot.bounds.contains(point) }
                let selectionPoint = descriptor?.block.point ?? point
                guard finishSourceEditor() else { return }
                guard let targetPage = item.document.page(at: index) else { throw PDFSourceError.page }
                let data = try sourceData(item)
                let session = try adding
                    ? PDFSourceSession.adding(data: data,pageIndex: index,point: point,fontSize: CGFloat(manager.textFontSize),color: NSColor(manager.annotationColor))
                    : PDFSourceSession.editing(data: data,pageIndex: index,point: selectionPoint)
                view.selectAnnotation(nil); view.setSourceSelection((targetPage,session.snapshot.bounds)); sourceAnchor = (index,selectionPoint)
                let expectedDocument = item.document
                if fontDocument != ObjectIdentifier(item.document) {
                    fontNames = try PDFSourceSession.documentFonts(data: data); fontDocument = ObjectIdentifier(item.document)
                }
                manager.textProperties.fonts = fontNames
                let previewData = try session.previewWithoutSelectedText()
                let previewDocument = PDFDocument(data: previewData)
                if let previewDocument { AnnotationMetadata.restore(previewDocument) }
                let inline = PDFInlineTextEditor(snapshot: session.snapshot,page: targetPage,pdfView: view,model: manager.textProperties,previewPage: previewDocument?.page(at: index))
                manager.selectedContent = nil
                inline.onApply = { [weak self,weak view,weak item] text,width,height,geometry in
                    guard let self,let view,let item,self.manager.selected?.id == item.id,item.document === expectedDocument else { return false }
                    do {
                        let committing = try adding
                            ? PDFSourceSession.adding(data: data,pageIndex: index,point: point,fontSize: session.snapshot.fontSize,color: session.snapshot.color)
                            : PDFSourceSession.editing(data: data,pageIndex: index,point: selectionPoint)
                        let changed = try committing.applying(text: text.string,fontSize: session.snapshot.fontSize,color: session.snapshot.color,width: width,height: height,richText: text,geometry: geometry)
                        try self.installSourceData(changed,item: item,index: index,view: view,bounds: committing.resultingBounds,anchor: committing.resultingPoint)
                        return true
                    } catch { self.sourceError(error); return false }
                }
                inline.onCancel = { [weak self,weak view] in view?.setSourceSelection(nil); self?.sourceAnchor = nil }
                inline.onRedraw = { [weak view,weak inline] in
                    guard let view else { return }
                    if inline?.isAttached == false { view.sourceInline = nil }
                    view.refreshOverlay()
                }
                view.sourceInline = inline; manager.panels.select(.properties)
                inline.focus(at: click); view.refreshOverlay()
            } catch PDFSourceError.textNotFound {
                view.setSourceSelection(nil); sourceAnchor = nil; manager.selectedAnnotation = nil; manager.selectedContent = nil
                if let item = manager.selected,let currentPage = item.document.page(at: requestedIndex) {
                    let index = requestedIndex
                    if let object = try? PDFSourceSession.objectInfo(data: sourceData(item),pageIndex: index,point: point) {
                        manager.selectedContent = object; view.setSourceSelection((currentPage,object.bounds)); manager.panels.select(.properties)
                    }
                }
            } catch { sourceError(error) }
        }
        private func annotationComponents(_ annotation: PDFAnnotation) -> [PDFAnnotation] {
            if let group = AnnotationMetadata.group(of: annotation), let page = annotation.page {
                return page.annotations.filter { AnnotationMetadata.group(of: $0) == group }
            }
            return [annotation]
        }
        private func annotationClipboardData(_ annotation: PDFAnnotation) -> Data? {
            guard let page = annotation.page else { return nil }
            let components = annotationComponents(annotation)
            let clipboardPage = PDFPage(); clipboardPage.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
            clipboardPage.setBounds(page.bounds(for: .cropBox), for: .cropBox)
            let copies = components.compactMap { $0.copy() as? PDFAnnotation }
            guard copies.count == components.count else { return nil }
            for copy in copies { copy.page = nil; clipboardPage.addAnnotation(copy) }
            AnnotationMetadata.transfer(from: components, to: copies)
            let document = PDFDocument(); document.insert(clipboardPage, at: 0)
            AnnotationMetadata.prepareForSave(document)
            guard let data = document.dataRepresentation(options: [PDFDocumentWriteOption.saveTextFromOCROption: false]) else { return nil }
            return data
        }
        private func copyAnnotationObjects(_ annotation: PDFAnnotation, board: NSPasteboard = .general) -> Bool {
            guard let data = annotationClipboardData(annotation) else { return false }
            board.clearContents()
            let success = board.setData(data, forType: ObjectClipboard.annotations)
            _ = board.setData(data, forType: .pdf)
            if let text = annotation.contents { _ = board.setString(text, forType: .string) }
            return success
        }
        private func sourceSessionForSelection(view: PDFViewerView) throws -> (PDFSourceSession, PDFDocumentItem, Int, String?) {
            guard let item = manager.selected else { throw PDFSourceError.document }
            if let sourceAnchor, view.sourceSelection != nil {
                return (try PDFSourceSession.editing(data: sourceData(item), pageIndex: sourceAnchor.index, point: sourceAnchor.point), item, sourceAnchor.index, nil)
            }
            if let selection = view.currentSelection, let page = selection.pages.first, selection.pages.count == 1,
               let text = selection.string, !text.isEmpty {
                let bounds = selection.bounds(for: page), index = item.document.index(for: page)
                return (try PDFSourceSession.editing(data: sourceData(item), pageIndex: index, point: CGPoint(x: bounds.midX,y: bounds.midY)), item, index, text)
            }
            throw PDFSourceError.textNotFound
        }
        private func writeTextClipboard(_ text: String, snapshot: PDFSourceSession.Snapshot) {
            let board = NSPasteboard.general; board.clearContents(); _ = board.setString(text, forType: .string)
            let style = ObjectClipboard.TextStyle(text: text, size: snapshot.fontSize, name: snapshot.fontName, color: snapshot.color)
            if let data = try? JSONEncoder().encode(style) { _ = board.setData(data, forType: ObjectClipboard.sourceText) }
        }
        private func copyObjects(on view: PDFViewerView, cutting: Bool) {
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                if cutting { editor.cut(nil) } else { editor.copy(nil) }; return
            }
            if let annotation = view.selectedAnnotation {
                if copyAnnotationObjects(annotation) {
                    if cutting { _ = view.deleteSelectedAnnotation() }
                } else { manager.say("Could not write to the clipboard.", "Не удалось записать данные в буфер обмена.") }
                return
            }
            if !cutting, let selection = view.currentSelection, let text = selection.string, !text.isEmpty, view.sourceSelection == nil {
                let board = NSPasteboard.general; board.clearContents(); _ = board.setString(text, forType: .string); return
            }
            do {
                let (session, item, index, selected) = try sourceSessionForSelection(view: view)
                let copied = selected ?? session.snapshot.text
                writeTextClipboard(copied, snapshot: session.snapshot)
                if cutting {
                    let remaining: String
                    if let selected {
                        guard let range = session.snapshot.text.range(of: selected) else { throw PDFSourceError.content }
                        var updated = session.snapshot.text; updated.removeSubrange(range); remaining = updated
                    } else { remaining = "" }
                    let data = try session.applying(text: remaining, fontSize: session.snapshot.fontSize, color: session.snapshot.color)
                    try installSourceData(data, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
                }
            } catch { sourceError(error) }
        }
        private func deleteObjects(on view: PDFViewerView) {
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.delete(nil); return }
            if view.deleteSelectedAnnotation() { return }
            do {
                let (session, item, index, selected) = try sourceSessionForSelection(view: view)
                var remaining = ""
                if let selected {
                    guard let range = session.snapshot.text.range(of: selected) else { throw PDFSourceError.content }
                    remaining = session.snapshot.text; remaining.removeSubrange(range)
                }
                let data = try session.applying(text: remaining, fontSize: session.snapshot.fontSize, color: session.snapshot.color)
                try installSourceData(data, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
            } catch { sourceError(error) }
        }
        private func pasteAnnotationData(_ data: Data, on view: PDFViewerView) -> Bool {
            guard let target = view.currentPage, let source = PDFDocument(data: data), let page = source.page(at: 0) else { return false }
                AnnotationMetadata.restore(source)
                let originals = page.annotations.filter { !AnnotationMetadata.isContainer($0) }
                let copies = originals.compactMap { $0.copy() as? PDFAnnotation }
                guard !copies.isEmpty, copies.count == originals.count else { return false }
                let union = copies.reduce(CGRect.null) { $0.union($1.bounds) }
                let center = view.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), to: target)
                let crop = target.bounds(for: .cropBox)
                let x = min(max(crop.minX, center.x-union.width/2), max(crop.minX,crop.maxX-union.width))
                let y = min(max(crop.minY, center.y-union.height/2), max(crop.minY,crop.maxY-union.height))
                for copy in copies { copy.page = nil; copy.bounds = copy.bounds.offsetBy(dx: x-union.minX,dy: y-union.minY); target.addAnnotation(copy) }
                AnnotationMetadata.transfer(from: originals, to: copies)
                manager.tool = .selectComments; view.setSourceSelection(nil); view.selectAnnotation(copies.first)
                view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
        }

        private func pasteObjects(on view: PDFViewerView, board: NSPasteboard = .general) {
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.paste(nil); return }
            guard let item = manager.selected, let target = view.currentPage else { return }
            if let data = board.data(forType: ObjectClipboard.annotations) {
                if !pasteAnnotationData(data, on: view) { manager.say("Could not paste these PDF objects.", "Не удалось вставить эти объекты PDF.") }
                return
            }
            let style = board.data(forType: ObjectClipboard.sourceText).flatMap { try? JSONDecoder().decode(ObjectClipboard.TextStyle.self, from: $0) }
            guard let text = style?.text ?? board.string(forType: .string), !text.isEmpty else {
                manager.say("The clipboard contains no PDF objects or text.", "В буфере обмена нет объектов PDF или текста."); return
            }
            do {
                let index = item.document.index(for: target)
                let point = view.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), to: target)
                let size = CGFloat(min(200,max(1,style?.fontSize ?? manager.textFontSize)))
                let color = style?.color ?? NSColor(manager.annotationColor)
                let session = try PDFSourceSession.adding(data: sourceData(item), pageIndex: index, point: point, fontSize: size, color: color, fontName: style?.fontName ?? "Arial")
                let changed = try session.applying(text: text, fontSize: size, color: color)
                manager.tool = .editText
                try installSourceData(changed, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
            } catch { sourceError(error) }
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
                self.syncPage(); self.syncMetrics(for: view); view.sourceInline?.updatePlacement(); view.refreshOverlay(); self.refreshSourceOutlines(view)
                if item.zoom != view.scaleFactor { item.zoom = view.scaleFactor }
            }
        }

        private func itemSearch(_ query: String, in document: PDFDocument?) -> PDFSelection? {
            document?.findString(query, withOptions: [.caseInsensitive]).first
        }

        private func addMarkup(on view: PDFViewerView, subtype: PDFAnnotationSubtype) {
            guard let selection = view.currentSelection, !(selection.string ?? "").isEmpty else { return }
            if let item = manager.selected { manager.recordUndo(item,group: "markup") }
            let tint = NSColor(manager.annotationColor).withAlphaComponent(CGFloat(manager.annotationOpacity))
            let group = UUID().uuidString
            let lineSelections = selection.selectionsByLine()
            if lineSelections.isEmpty {
                addMarkup(selection, subtype: subtype, color: tint,group: group)
            } else {
                for lineSelection in lineSelections { addMarkup(lineSelection, subtype: subtype, color: tint,group: group) }
            }
            view.setCurrentSelection(nil, animate: false)
            view.setNeedsDisplay(view.bounds)
        }

        private func addMarkup(_ selection: PDFSelection, subtype: PDFAnnotationSubtype, color: NSColor,group: String) {
            for page in selection.pages {
                let bounds = selection.bounds(for: page).insetBy(dx: -1, dy: -1)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = color
                AnnotationMetadata.setGroup(group,on: annotation)
                AnnotationMetadata.setOpacity(Double(color.alphaComponent), on: annotation)
                page.addAnnotation(annotation)
                view?.selectAnnotation(annotation)
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

        private func center(_ page: PDFPage,in view: PDFViewerView) {
            view.go(to: page); view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
            if let scroll = view.internalScrollView {
                let rect = view.convert(page.bounds(for: view.displayBox),from: page)
                let vertical = max(8,(scroll.contentView.bounds.height-rect.height)/2+8)
                let margin = vertical/max(0.05,view.scaleFactor)
                let next = NSEdgeInsets(top: margin,left: 8,bottom: margin,right: 8)
                let previous = view.pageBreakMargins
                if previous.top != next.top || previous.bottom != next.bottom || previous.left != next.left || previous.right != next.right { view.pageBreakMargins = next; view.layoutDocumentView(); view.layoutSubtreeIfNeeded() }
            }
            guard let documentView = view.documentView,let scroll = view.internalScrollView else { return }
            let clip = scroll.contentView
            let rect = documentView.convert(view.convert(page.bounds(for: view.displayBox),from: page),from: view)
            let target = CGPoint(x: rect.midX-clip.bounds.width/2,y: rect.midY-clip.bounds.height/2)
            let constrained = clip.constrainBoundsRect(CGRect(origin: target,size: clip.bounds.size)).origin
            let centered = CGPoint(x: rect.width < clip.bounds.width ? target.x : constrained.x,y: rect.height < clip.bounds.height ? target.y : constrained.y)
            clip.setBoundsOrigin(centered)
            scroll.reflectScrolledClipView(clip); view.onViewportChange?()
        }
        private func copyPage(_ index: Int,item: PDFDocumentItem,board: NSPasteboard = .general) {
            guard finishSourceEditor(),let source = item.document.page(at: index),let copy = source.copy() as? PDFPage else { return }
            AnnotationMetadata.copy(from: source,to: copy)
            let document = PDFDocument(); document.insert(copy,at: 0); AnnotationMetadata.prepareForSave(document)
            guard let data = document.dataRepresentation(options: [PDFDocumentWriteOption.saveTextFromOCROption: false]) else { return }
            board.clearContents(); _ = board.setData(data,forType: ObjectClipboard.pages); _ = board.setData(data,forType: .pdf)
        }
        private func pastePages(_ index: Int,item: PDFDocumentItem,view: PDFViewerView,board: NSPasteboard = .general) {
            guard finishSourceEditor(),let data = board.data(forType: ObjectClipboard.pages) ?? board.data(forType: .pdf),let document = PDFDocument(data: data),document.pageCount > 0 else {
                manager.say("No PDF pages in the clipboard.","В буфере обмена нет страниц PDF."); return
            }
            AnnotationMetadata.restore(document)
            let target = min(max(0,index),item.pageCount)
            for offset in 0..<document.pageCount {
                guard let source = document.page(at: offset),let copy = source.copy() as? PDFPage else { continue }
                AnnotationMetadata.copy(from: source,to: copy); item.document.insert(copy,at: target+offset)
            }
            item.pageIndex = target; reload(view,document: item,pageIndex: target); manager.pageText = String(target+1); manager.send(.refresh)
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
            sourceDocument = nil; sourceOutlineData = nil; sourceOutlineCache = [:]; fontDocument = nil
            outlineGeneration += 1; outlinePending = false
            view.selectAnnotation(nil)
            view.document = nil
            view.document = item.document
            view.scaleFactor = zoom
            if let page = item.document.page(at: pageIndex) { center(page,in: view) }
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
        textView.textColor = .labelColor
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
        textView.font = font; textView.textColor = .labelColor
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
        NSBezierPath(rect: bounds).addClip()
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
        if pdf.activeTool == .editText {
            NSColor(calibratedWhite: 0.55,alpha: 0.9).setStroke()
            for entry in pdf.sourceBlocks {
                let rect = convert(pdf.convert(entry.block.snapshot.bounds,from: entry.page),from: pdf)
                if rect.intersects(bounds) { let path = NSBezierPath(rect: rect); path.lineWidth = 0.7; path.stroke() }
            }
        }
        pdf.sourceInline?.drawControls(in: self)
        if pdf.sourceInline == nil, let source = pdf.sourceSelection {
            let rect = convert(pdf.convert(source.bounds, from: source.page), from: pdf)
            NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: rect.insetBy(dx: -2,dy: -2)); path.lineWidth = 1; path.stroke()
        }
        if let preview = pdf.preview {
            let start = convert(pdf.convert(preview.start, from: preview.page), from: pdf)
            let end = convert(pdf.convert(preview.end, from: preview.page), from: pdf)
            pdf.strokeColor.setStroke()
            let path: NSBezierPath
            if [.rectangle,.ellipse,.cloud,.link,.marquee].contains(preview.tool) {
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                path = preview.tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            } else if preview.tool == .pencil {
                path = NSBezierPath(); path.move(to: start)
                for p in preview.points { path.line(to: convert(pdf.convert(p,from: preview.page),from: pdf)) }
            } else { path = NSBezierPath(); path.move(to: start); path.line(to: end) }
            path.lineWidth = max(1, pdf.strokeWidth * pdf.scaleFactor); path.stroke()
        }
    }
}

@MainActor
private final class PDFViewerView: PDFView {
    struct Preview { let page: PDFPage; let start: CGPoint; var end: CGPoint; let tool: PDFTool; var points: [CGPoint] = [] }
    private struct Transform {
        let annotation: PDFAnnotation
        let page: PDFPage
        let start: CGPoint
        let bounds: CGRect
        let corner: Int?
        let lineStart: CGPoint
        let lineEnd: CGPoint
        var paths: [NSBezierPath] = []
        var recordedHistory = false
    }
    var activeTool: PDFTool = .hand { didSet { if activeTool != oldValue { window?.invalidateCursorRects(for: self) } } }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 2
    var fillEnabled = false
    var onWillModify: (() -> Void)?
    var onMarkupFinished: (() -> Void)?
    var onPlaceObject: ((PDFPage,CGPoint,PDFTool) -> Void)?
    var onViewportChange: (() -> Void)?
    var onCreateText: ((PDFPage, CGPoint, PDFAnnotation?) -> Void)?
    var onEditText: ((PDFAnnotation) -> Void)?
    var onSourceTextRequest: ((PDFPage, CGPoint, Bool, Bool) -> Void)?
    var sourceInline: PDFInlineTextEditor?
    var sourceBlocks: [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] = []
    var pendingLinkBounds: CGRect?
    private var sourceDragging = false
    var onClipboardCommand: ((ViewerCommand) -> Void)?
    private(set) var sourceSelection: (page: PDFPage, bounds: CGRect)?
    var onSelectionChanged: ((PDFAnnotation?) -> Void)?
    var onAnnotationChanged: (() -> Void)?
    var onCursorChange: ((CGPoint?, CGPoint?) -> Void)?
    private(set) var selectedAnnotation: PDFAnnotation?
    private(set) var preview: Preview?
    private var transform: Transform?
    private var panPoint: CGPoint?
    private var cursorPushed = false
    private var requestedScrollOrigin: CGPoint?
    private var lastScrollOrigin: CGPoint?
    private var eventMonitor: Any?
    private var pendingZoom: CGFloat = 0
    private var zoomAnchor: CGPoint?
    private var zoomScheduled = false
    private var tracking: NSTrackingArea?
    private let overlay = AnnotationOverlayView(frame: .zero)
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); clipsToBounds = true }
    required init?(coder: NSCoder) { super.init(coder: coder); clipsToBounds = true }

    var internalScrollView: NSScrollView? {
        if let scroll = documentView?.enclosingScrollView { scroll.clipsToBounds = true; scroll.contentView.clipsToBounds = true; return scroll }
        func find(_ view: NSView) -> NSScrollView? {
            for child in view.subviews {
                if let scroll = child as? NSScrollView { scroll.clipsToBounds = true; scroll.contentView.clipsToBounds = true; return scroll }
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
        overlay.clipsToBounds = true; overlay.pdfView = self; overlay.autoresizingMask = [.width, .height]
        addSubview(overlay, positioned: .above, relativeTo: nil); refreshOverlay()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .leftMouseUp]) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated {
                if let self,let local = HoverEventLocation.point(for: event,in: self) {
                    if self.visibleRect.contains(local) {
                        if event.type == .leftMouseUp {
                            if [.highlight,.underline,.strike].contains(self.activeTool) {
                                DispatchQueue.main.async { [weak self] in self?.onMarkupFinished?() }
                            }
                        } else if event.type == .magnify {
                            self.queueMagnification(event.magnification,at: local); handled = true
                        } else if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                            self.queueMagnification(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08),at: local); handled = true
                        } else {
                            self.applyScroll(event); handled = true
                        }
                    }
                }
            }
            return handled ? nil : event
        }
    }
    func stopEventMonitoring() {
        pendingZoom = 0; zoomAnchor = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
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
        // Clipping affects drawing, not hit testing. Out-of-viewport editors
        // must never intercept the ribbon or docked panel controls.
        let viewportPoint = convert(point,from: superview)
        guard bounds.contains(viewportPoint) else { return nil }
        let nativeHit = super.hitTest(point)
        if nativeHit is NSScroller { return nativeHit }
        let sourcePoint = convert(point,from: superview)
        if let inline = sourceInline {
            if inline.handle(at: sourcePoint) != nil { return self }
            if inline.owns(nativeHit) { return nativeHit }
        }
        let intercepted: Bool
        switch activeTool {
        case .hand, .typewriter, .rectangle, .ellipse, .cloud, .pencil, .eraser, .note, .stamp, .link, .marquee, .formText, .formCheckbox, .formRadio, .formChoice, .formButton, .line, .arrow, .callout, .selectComments, .addText, .editText: intercepted = true
        default: intercepted = false
        }
        let local = convert(point, from: superview)
        return intercepted && bounds.contains(local) ? self : nativeHit
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        switch activeTool {
        case .hand: addCursorRect(visibleRect, cursor: .openHand)
        case .textSelection, .highlight, .underline, .strike, .typewriter, .addText, .editText: addCursorRect(visibleRect, cursor: .iBeam)
        case .rectangle, .ellipse, .cloud, .pencil, .eraser, .link, .marquee, .note, .stamp, .formText, .formCheckbox, .formRadio, .formChoice, .formButton, .line, .arrow, .callout: addCursorRect(visibleRect, cursor: .crosshair)
        default: break
        }
    }
    func setSourceSelection(_ selection: (PDFPage, CGRect)?) {
        sourceSelection = selection.map { (page: $0.0, bounds: $0.1) }; refreshOverlay()
    }
    func selectAnnotation(_ annotation: PDFAnnotation?) {
        if annotation != nil { sourceSelection = nil }
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
            window?.makeFirstResponder(self)
            setSourceSelection(nil); selectAnnotation(nil)
            panPoint = event.locationInWindow; NSCursor.closedHand.push(); cursorPushed = true; return
        }
        let local = convert(event.locationInWindow, from: nil)
        if let inline = sourceInline,let handle = inline.handle(at: local) {
            sourceDragging = true; inline.beginDrag(handle,at: convert(local,to: inline.page)); return
        }
        guard let page = page(for: local, nearest: false) else {
            guard sourceInline?.finish() != false else { return }
            setSourceSelection(nil); selectAnnotation(nil); return
        }
        let point = convert(local, to: page)
        if activeTool == .selectComments {
            setSourceSelection(nil)
            window?.makeFirstResponder(self)
            if let annotation = selectedAnnotation, annotation.page === page {
                let corner = annotationCorners(annotation).firstIndex { corner in
                    let handle = convert(corner, from: page)
                    return hypot(handle.x - local.x, handle.y - local.y) <= 9
                }
                if let corner {
                    transform = Transform(annotation: annotation, page: page, start: point, bounds: annotation.bounds, corner: corner, lineStart: annotation.startPoint, lineEnd: annotation.endPoint,paths: (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath })
                    return
                }
            }
            let annotation = page.annotations.reversed().first { $0.shouldDisplay && !AnnotationMetadata.isContainer($0) && $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
            selectAnnotation(annotation)
            if let annotation = selectedAnnotation {
                if event.clickCount == 2 && annotation.type == "FreeText" { onEditText?(annotation); return }
                transform = Transform(annotation: annotation, page: page, start: point, bounds: annotation.bounds, corner: nil, lineStart: annotation.startPoint, lineEnd: annotation.endPoint,paths: (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath })
            }
            return
        }
        guard page.bounds(for: .cropBox).contains(point) else { return }
        switch activeTool {
        case .addText: window?.makeFirstResponder(self); onSourceTextRequest?(page,point,true,true)
        case .editText: window?.makeFirstResponder(self); onSourceTextRequest?(page,point,false,true)
        case .typewriter: onCreateText?(page, point, nil)
        case .note, .stamp, .formText, .formCheckbox, .formRadio, .formChoice, .formButton: onPlaceObject?(page,point,activeTool)
        case .eraser:
            let annotation = page.annotations.reversed().first { $0.shouldDisplay && !AnnotationMetadata.isContainer($0) && $0.bounds.insetBy(dx: -4,dy: -4).contains(point) }
            selectAnnotation(annotation); _ = deleteSelectedAnnotation()
        case .rectangle, .ellipse, .cloud, .pencil, .link, .marquee, .line, .arrow, .callout: preview = Preview(page: page, start: point, end: point, tool: activeTool); refreshOverlay()
        default: super.mouseDown(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        trackCursor(event)
        if sourceDragging,let inline = sourceInline {
            inline.drag(to: convert(convert(event.locationInWindow,from: nil),to: inline.page)); return
        }
        if var drawing = preview {
            let point = convert(convert(event.locationInWindow, from: nil), to: drawing.page)
            let crop = drawing.page.bounds(for: .cropBox)
            drawing.end = CGPoint(x: min(crop.maxX, max(crop.minX, point.x)), y: min(crop.maxY, max(crop.minY, point.y)))
            if drawing.tool == .pencil { if drawing.points.isEmpty { drawing.points.append(drawing.start) }; drawing.points.append(drawing.end) }
            preview = drawing; refreshOverlay(); return
        }
        if let change = transform {
            if !change.recordedHistory { onWillModify?(); transform?.recordedHistory = true }
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
            if change.corner != nil && change.annotation.type == "Ink" {
                for path in change.annotation.paths ?? [] { change.annotation.remove(path) }
                var affine = AffineTransform.identity; affine.scale(x: rect.width/max(1,change.bounds.width),y: rect.height/max(1,change.bounds.height))
                for original in change.paths { if let path = original.copy() as? NSBezierPath { path.transform(using: affine); change.annotation.add(path) } }
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
        if sourceDragging { sourceDragging = false; sourceInline?.endDrag(); return }
        if let drawing = preview {
            preview = nil; commitDrawing(drawing); refreshOverlay(); onAnnotationChanged?(); return
        }
        if transform != nil { transform = nil; onAnnotationChanged?(); return }
        if panPoint != nil {
            panPoint = nil; if cursorPushed { NSCursor.pop(); cursorPushed = false }; return
        }
        super.mouseUp(with: event)
    }
    func deleteSelectedAnnotation() -> Bool {
        guard let annotation = selectedAnnotation, let page = annotation.page else { return false }
        onWillModify?()
        if let group = AnnotationMetadata.group(of: annotation) {
            for component in page.annotations where AnnotationMetadata.group(of: component) == group { page.removeAnnotation(component) }
        } else { page.removeAnnotation(annotation) }
        selectAnnotation(nil); setNeedsDisplay(bounds); onAnnotationChanged?(); return true
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 6: onClipboardCommand?(.feature(event.modifierFlags.contains(.shift) ? "redo" : "undo")); return
            case 8: onClipboardCommand?(.copy); return
            case 7: onClipboardCommand?(.cut); return
            case 9: onClipboardCommand?(.paste); return
            default: break
            }
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if activeTool == .selectComments && deleteSelectedAnnotation() { return }
            if sourceSelection != nil { onClipboardCommand?(.deleteSelection); return }
        }
        if event.keyCode == 53 { selectAnnotation(nil); setSourceSelection(nil); preview = nil; transform = nil; refreshOverlay(); return }
        super.keyDown(with: event)
    }
    private func commitDrawing(_ drawing: Preview) {
        let start = drawing.start, end = drawing.end
        guard hypot(end.x - start.x, end.y - start.y) >= 3 else { return }
        let rect = CGRect(x: min(start.x, end.x) - 1, y: min(start.y, end.y) - 1, width: max(2, abs(end.x - start.x) + 2), height: max(2, abs(end.y - start.y) + 2))
        if drawing.tool == .marquee { zoom(to: rect,on: drawing.page); return }
        if drawing.tool == .link { pendingLinkBounds = rect; onPlaceObject?(drawing.page,rect.origin,.link); return }
        let subtype: PDFAnnotationSubtype
        switch drawing.tool { case .rectangle: subtype = .square; case .ellipse: subtype = .circle; case .pencil,.cloud: subtype = .ink; default: subtype = .line }
        let annotation = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
        if drawing.tool == .pencil || drawing.tool == .cloud {
            let path = NSBezierPath()
            if drawing.tool == .pencil {
                let points = drawing.points.isEmpty ? [start,end] : drawing.points
                for (index,p) in points.enumerated() { let local = CGPoint(x: p.x-rect.minX,y: p.y-rect.minY); if index == 0 { path.move(to: local) } else { path.line(to: local) } }
            } else {
                let inset = max(3,strokeWidth*2),box = CGRect(x: inset,y: inset,width: max(3,rect.width-inset*2),height: max(3,rect.height-inset*2))
                let radius = min(12,max(3,min(box.width,box.height)/8))
                let edges = [(CGPoint(x: box.minX,y: box.minY),CGPoint(x: box.maxX,y: box.minY)),(CGPoint(x: box.maxX,y: box.minY),CGPoint(x: box.maxX,y: box.maxY)),(CGPoint(x: box.maxX,y: box.maxY),CGPoint(x: box.minX,y: box.maxY)),(CGPoint(x: box.minX,y: box.maxY),CGPoint(x: box.minX,y: box.minY))]
                path.move(to: edges[0].0)
                for (a,b) in edges {
                    let length = hypot(b.x-a.x,b.y-a.y),count = max(1,Int(ceil(length/(radius*2))))
                    for i in 0..<count {
                        let t = CGFloat(i)/CGFloat(count),u = CGFloat(i+1)/CGFloat(count)
                        let from = CGPoint(x: a.x+(b.x-a.x)*t,y: a.y+(b.y-a.y)*t),to = CGPoint(x: a.x+(b.x-a.x)*u,y: a.y+(b.y-a.y)*u)
                        let dx = to.x-from.x,dy = to.y-from.y,normal = CGPoint(x: dy*0.55,y: -dx*0.55)
                        path.curve(to: to,controlPoint1: CGPoint(x: from.x+dx*0.25+normal.x,y: from.y+dy*0.25+normal.y),controlPoint2: CGPoint(x: from.x+dx*0.75+normal.x,y: from.y+dy*0.75+normal.y))
                    }
                }; path.close()
            }; annotation.add(path)
        }
        if drawing.tool == .rectangle || drawing.tool == .ellipse { annotation.interiorColor = fillEnabled ? strokeColor.withAlphaComponent(strokeColor.alphaComponent*0.25) : nil }
        annotation.color = strokeColor
        AnnotationMetadata.setOpacity(Double(strokeColor.alphaComponent), on: annotation)
        if drawing.tool == .callout { AnnotationMetadata.setGroup(UUID().uuidString, on: annotation) }
        let border = PDFBorder(); border.lineWidth = strokeWidth; annotation.border = border
        if [.line,.arrow,.callout].contains(drawing.tool) {
            annotation.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            annotation.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
            if drawing.tool == .arrow { annotation.endLineStyle = .openArrow }
            if drawing.tool == .callout { annotation.startLineStyle = .openArrow }
        }
        onWillModify?(); drawing.page.addAnnotation(annotation)
        if drawing.tool == .callout { onCreateText?(drawing.page, end, annotation) }
        else { selectAnnotation(annotation) }
        setNeedsDisplay(bounds)
    }
    private func applyScroll(_ event: NSEvent) {
        guard let scroll = internalScrollView else { return }
        let clip = scroll.contentView
        let factorX = event.hasPreciseScrollingDeltas ? 1 : max(10, scroll.horizontalLineScroll)
        let factorY = event.hasPreciseScrollingDeltas ? 1 : max(10, scroll.verticalLineScroll)
        let deltaInView = CGPoint(x: -event.scrollingDeltaX * factorX,
                                  y: (isFlipped ? -1 : 1) * event.scrollingDeltaY * factorY)
        let delta = clip.convert(deltaInView, from: self) - clip.convert(.zero, from: self)
        if lastScrollOrigin != clip.bounds.origin || event.phase.contains(.began) {
            requestedScrollOrigin = clip.bounds.origin
        }
        let previous = requestedScrollOrigin ?? clip.bounds.origin
        var proposed = CGPoint(x: previous.x + delta.x, y: previous.y + delta.y)
        if let document = scroll.documentView {
            let content = document.frame
            if content.width > clip.bounds.width {
                proposed.x = min(max(content.minX, proposed.x), content.maxX - clip.bounds.width)
            } else { proposed.x = clip.bounds.minX }
            if content.height > clip.bounds.height {
                proposed.y = min(max(content.minY, proposed.y), content.maxY - clip.bounds.height)
            } else { proposed.y = clip.bounds.minY }
        }
        // Keep sub-point deltas between events when AppKit aligns clip origins.
        requestedScrollOrigin = proposed
        clip.setBoundsOrigin(proposed)
        lastScrollOrigin = clip.bounds.origin
        clip.needsDisplay = true
        scroll.reflectScrolledClipView(clip)
        refreshOverlay(); onViewportChange?()
    }
    private func queueMagnification(_ delta: CGFloat,at point: CGPoint) {
        guard delta.isFinite,delta != 0 else { return }
        pendingZoom += delta; zoomAnchor = point
        guard !zoomScheduled else { return }; zoomScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushMagnification() }
    }
    private func flushMagnification() {
        zoomScheduled = false
        let delta = pendingZoom,point = zoomAnchor; pendingZoom = 0; zoomAnchor = nil
        if let point { applyMagnification(delta,at: point) }
    }
    private func applyMagnification(_ delta: CGFloat, at anchor: CGPoint) {
        requestedScrollOrigin = nil; lastScrollOrigin = nil
        guard delta.isFinite, delta != 0 else { return }
        let page = page(for: anchor, nearest: true)
        let pagePoint = page.map { convert(anchor, to: $0) }
        autoScales = false
        scaleFactor = min(maxScaleFactor, max(minScaleFactor, scaleFactor * exp(delta)))
        layoutDocumentView()
        if let page, let pagePoint, let scroll = internalScrollView {
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
                // Retain fractional coordinates where supported. Older AppKit
                // releases may align the resulting origin to clip-space pixels.
                clip.setBoundsOrigin(origin)
                clip.needsDisplay = true
                scroll.reflectScrolledClipView(clip)
            }
        }
        refreshOverlay(); onViewportChange?()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            queueMagnification(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08),at: HoverEventLocation.point(for: event,in: self) ?? convert(event.locationInWindow,from: nil))
        } else {
            if internalScrollView != nil { applyScroll(event) } else { super.scrollWheel(with: event) }
        }
    }
    override func magnify(with event: NSEvent) {
        queueMagnification(event.magnification,at: HoverEventLocation.point(for: event,in: self) ?? convert(event.locationInWindow,from: nil))
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backgroundColor = NSColor(calibratedWhite: effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? 0.12 : 0.82,alpha: 1)
    }
    override func viewDidEndLiveResize() { super.viewDidEndLiveResize(); onViewportChange?() }
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        Task { @MainActor [weak self] in self?.onViewportChange?(); self?.refreshOverlay() }
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

@MainActor
private enum PDFDialogs {
    static func prompt(_ title: String, fields: [(String,String)], completion: @escaping ([String]) -> Void) {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel / Отмена")
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
            let inputs = fields.map { label,value -> NSTextField in
                stack.addArrangedSubview(NSTextField(labelWithString: label))
                let input = NSTextField(string: value); input.frame.size = CGSize(width: 340,height: 24); stack.addArrangedSubview(input); return input
            }
            stack.frame = CGRect(x: 0,y: 0,width: 340,height: CGFloat(fields.count*52)); alert.accessoryView = stack
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { completion(inputs.map(\.stringValue)) }
            }
        }
    }
    static func save(_ name: String, type: UTType, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        panel.begin { response in if response == .OK,let url = panel.url { completion(url) } }
    }
    static func open(_ types: [UTType], completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.allowsMultipleSelection = true
        panel.begin { response in if response == .OK { completion(panel.urls) } }
    }
}

@MainActor
private extension DocumentManager {
    func createBlankDocument() {
        let document = PDFDocument(); let page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); document.insert(page,at: 0)
        let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf"),document: document); entry.isUntitled = true; insertDocument(entry)
    }
    func insertDocument(_ entry: PDFDocumentItem) { documents.append(entry); select(entry.id) }
    func activateMarkup(_ next: PDFTool) {
        guard finishSourceEditing?() != false else { return }
        if ![PDFTool.highlight,.underline,.strike].contains(tool) {
            annotationColor = next == .highlight ? .yellow : .red
            annotationOpacity = next == .highlight ? 0.45 : 0.85
        }
        tool = next; panels.select(.properties)
        send(next == .underline ? .underline : (next == .strike ? .strike : .highlight))
    }
    func bookmarkRoot() -> PDFOutline? {
        guard let document = selected?.document else { return nil }
        if document.outlineRoot == nil { document.outlineRoot = PDFOutline() }
        return document.outlineRoot
    }
    func bookmarkNodes(_ root: PDFOutline? = nil) -> [PDFOutline] {
        guard let root = root ?? selected?.document.outlineRoot else { return [] }
        var nodes: [PDFOutline] = []
        for index in 0..<root.numberOfChildren { if let child = root.child(at: index) { nodes.append(child); nodes += bookmarkNodes(child) } }
        return nodes
    }
    func addBookmark(title: String,page: PDFPage,parent: PDFOutline? = nil) {
        guard let root = parent ?? bookmarkRoot() else { return }
        let node = PDFOutline(); node.label = title; node.destination = PDFDestination(page: page,at: CGPoint(x: page.bounds(for: .cropBox).minX,y: page.bounds(for: .cropBox).maxY))
        if let item = selected { recordUndo(item,group: "bookmarks") }
        root.insertChild(node,at: root.numberOfChildren); selectedOutline = node; send(.refresh)
    }
    func addBookmarkPrompt(parent: PDFOutline? = nil) {
        guard let page = selected?.document.page(at: selected?.pageIndex ?? 0) else { return }
        PDFDialogs.prompt(language == .ru ? "Новая закладка" : "New bookmark",fields: [(language == .ru ? "Название" : "Title","Page \((selected?.pageIndex ?? 0)+1)")]) { [weak self] values in
            self?.addBookmark(title: values[0],page: page,parent: parent)
        }
    }
    func renameBookmark(_ node: PDFOutline) {
        PDFDialogs.prompt(language == .ru ? "Имя закладки" : "Bookmark title",fields: [("",node.label ?? "")]) { [weak self] values in if let self,let item = self.selected { self.recordUndo(item,group: "bookmarks") }; node.label = values[0]; self?.send(.refresh) }
    }
    func deleteBookmark(_ node: PDFOutline) { if let item = selected { recordUndo(item,group: "bookmarks") }; node.removeFromParent(); selectedOutline = nil; send(.refresh) }
    func editLink(_ annotation: PDFAnnotation) {
        let old = (annotation.action as? PDFActionURL)?.url?.absoluteString ?? "https://"
        PDFDialogs.prompt(language == .ru ? "Ссылка" : "Link",fields: [("URL",old)]) { [weak self] values in
            guard let url = URL(string: values[0]),["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") else { self?.say("Invalid URL","Некорректный URL"); return }
            if let self,let item = self.selected { self.recordUndo(item,group: "link") }
            annotation.action = PDFActionURL(url: url); self?.send(.refresh)
        }
    }
}

@MainActor
private enum PDFRasterizer {
    private static let backingDocuments = NSMapTable<PDFPage,PDFDocument>.weakToStrongObjects()
    static func image(_ page: PDFPage,size: CGSize) -> NSImage {
        NSImage(size: size,flipped: false) { rect in
            guard let ref = page.pageRef,let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.saveGState()
            context.concatenate(ref.getDrawingTransform(.cropBox,rect: rect,rotate: 0,preserveAspectRatio: true)); context.drawPDFPage(ref)
            for annotation in page.annotations where annotation.shouldDisplay && !AnnotationMetadata.isContainer(annotation) { annotation.draw(with: .cropBox,in: context) }
            context.restoreGState(); return true
        }
    }
    static func textPage(_ text: String) -> PDFPage? {
        let data = NSMutableData(); var box = CGRect(x: 0,y: 0,width: 612,height: 792)
        guard let consumer = CGDataConsumer(data: data),let context = CGContext(consumer: consumer,mediaBox: &box,nil) else { return nil }
        context.beginPDFPage(nil); context.textMatrix = .identity
        let font = CTFontCreateWithName("Arial" as CFString,12,nil)
        let attributes: [NSAttributedString.Key:Any] = [NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):NSColor.black.cgColor]
        let attributed = NSAttributedString(string: text,attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var offset = 0,y: CGFloat = 748
        while offset < attributed.length && y > 40 {
            let count = max(1,CTTypesetterSuggestLineBreak(typesetter,offset,532))
            let line = CTTypesetterCreateLine(typesetter,CFRange(location: offset,length: count))
            context.textPosition = CGPoint(x: 40,y: y); CTLineDraw(line,context)
            y -= 16; offset += count
        }
        context.endPDFPage(); context.closePDF()
        guard let document = PDFDocument(data: data as Data),let page = document.page(at: 0)?.copy() as? PDFPage else { return nil }
        backingDocuments.setObject(document,forKey: page)
        return page
    }
}

@MainActor
private extension PDFViewer.Coordinator {
    func placeObject(_ tool: PDFTool,on page: PDFPage,point: CGPoint,view: PDFViewerView) {
        if [.formText,.formCheckbox,.formRadio,.formChoice,.formButton].contains(tool) {
            PDFDialogs.prompt(manager.language == .ru ? "Поле формы" : "Form field",fields: [("Name / Имя","Field-"+UUID().uuidString.prefix(6)),("Choices / Варианты (через ;)","Yes;No")]) { [weak self,weak view] values in
                guard let self,let view else { return }
                let crop = page.bounds(for: .cropBox),small = tool == .formCheckbox || tool == .formRadio
                let width: CGFloat = small ? 24 : min(220,crop.width),height: CGFloat = 28
                let rect = CGRect(x: min(max(crop.minX,point.x),crop.maxX-width),y: min(max(crop.minY,point.y-height),crop.maxY-height),width: width,height: height)
                let annotation = PDFWidgetFactory.make(tool,bounds: rect,name: values[0],choices: values[1].components(separatedBy: ";"))
                if let item = self.manager.selected { self.manager.recordUndo(item,group: "form") }
                page.addAnnotation(annotation); view.selectAnnotation(annotation); self.manager.tool = .textSelection; self.manager.send(.refresh)
            }; return
        }
        if tool == .link {
            let bounds = view.pendingLinkBounds ?? CGRect(x: point.x,y: point.y,width: 140,height: 24); view.pendingLinkBounds = nil
            let annotation = PDFAnnotation(bounds: bounds,forType: .link,withProperties: nil)
            PDFDialogs.prompt(manager.language == .ru ? "Добавить ссылку" : "Add link",fields: [("URL","https://")]) { [weak self,weak view] values in
                guard let url = URL(string: values[0]),["http","https","mailto"].contains(url.scheme?.lowercased() ?? "") else { self?.manager.say("Invalid URL","Некорректный URL"); return }
                annotation.action = PDFActionURL(url: url); annotation.color = .systemBlue
                let border = PDFBorder(); border.lineWidth = 1; annotation.border = border
                if let self,let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") }
                page.addAnnotation(annotation); view?.selectAnnotation(annotation); view?.setNeedsDisplay(view?.bounds ?? .zero); self?.manager.send(.refresh)
            }; return
        }
        let note = tool == .note
        let title = manager.language == .ru ? (note ? "Заметка" : "Штамп") : (note ? "Note" : "Stamp")
        PDFDialogs.prompt(title,fields: [(manager.language == .ru ? "Текст" : "Text",note ? "" : manager.stampText)]) { [weak self,weak view] values in
            guard let self,let view else { return }
            let crop = page.bounds(for: .cropBox)
            let width: CGFloat = note ? 24 : min(230,crop.width),height: CGFloat = note ? 24 : 52
            let rect = CGRect(x: min(max(crop.minX,point.x),crop.maxX-width),y: min(max(crop.minY,point.y-height),crop.maxY-height),width: width,height: height)
            let annotation = PDFAnnotation(bounds: rect,forType: note ? .text : .freeText,withProperties: nil)
            annotation.contents = values[0]; annotation.userName = BotPlusBrand.name
            if note { annotation.iconType = .note; annotation.color = NSColor(self.manager.annotationColor) }
            else {
                self.manager.stampText = values[0]; annotation.font = NSFont.boldSystemFont(ofSize: 18); annotation.fontColor = view.strokeColor; annotation.color = .clear; annotation.alignment = .center
                let border = PDFBorder(); border.lineWidth = 2; annotation.border = border
            }
            AnnotationMetadata.setOpacity(self.manager.annotationOpacity,on: annotation)
            if let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") }
            page.addAnnotation(annotation); view.selectAnnotation(annotation); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
        }
    }
    func performFeature(_ id: String,on view: PDFViewerView,item: PDFDocumentItem) {
        guard finishSourceEditor() else { return }
        let tools: [String:PDFTool] = ["cloud":.cloud,"pencil":.pencil,"eraser":.eraser,"sticky":.note,"note":.note,"addComment":.note,"stamp":.stamp,"addLink":.link,"marquee":.marquee,"textField":.formText,"checkbox":.formCheckbox,"radio":.formRadio,"dropdown":.formChoice,"button":.formButton]
        if let tool = tools[id] {
            if tool == .stamp { manager.annotationColor = .red; manager.annotationOpacity = 1 }
            if tool == .note { manager.annotationColor = .yellow; manager.annotationOpacity = 1 }
            manager.tool = tool; manager.panels.select(.properties); manager.send(.refresh); return }
        let page = view.currentPage ?? item.document.page(at: item.pageIndex)
        if ["bookmarkCase","bookmarkZoom","bookmarkActions","bookmarkSort","bookmarkMerge","bookmarkTOC","bookmarkSortPages","bookmarkLinks","swap","clear"].contains(id) { manager.recordUndo(item,group: id) }
        switch id {
        case "strike": manager.activateMarkup(.strike)
        case "edit","editContent": manager.tool = .editText; manager.send(.refresh)
        case "editLink":
            manager.tool = .selectComments
            if let annotation = view.selectedAnnotation,annotation.type == "Link" { manager.editLink(annotation) }
            else { manager.say("Select a link, then choose Edit Links.","Выберите ссылку и нажмите «Изменить ссылки».") }
        case "list","showComments": manager.panels.toggleDrawer(.comments)
        case "deleteComment": _ = view.deleteSelectedAnnotation()
        case "wordCount":
            let text = (0..<item.pageCount).compactMap { item.document.page(at: $0)?.string }.joined(separator: "\n")
            let count = text.split { $0.isWhitespace || $0.isNewline }.count
            manager.say("Words: \(count); characters: \(text.count)","Слов: \(count); знаков: \(text.count)")
        case "read":
            if manager.speech.isPaused { manager.speech.continueSpeaking() }
            else if !manager.speech.isSpeaking,let text = page?.string {
                let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: manager.language == .ru ? "ru-RU" : "en-US"); manager.speech.speak(utterance)
            }
        case "pauseRead": manager.speech.pauseSpeaking(at: .word)
        case "bookmarkAdd": manager.addBookmarkPrompt()
        case "bookmarkDelete": if let node = manager.selectedOutline { manager.deleteBookmark(node) }
        case "bookmarkFromPageText":
            guard let page else { return }
            let title = view.currentSelection?.string ?? page.string?.split(separator: "\n").first.map(String.init) ?? "Page \(item.pageIndex+1)"
            manager.addBookmark(title: String(title.prefix(160)),page: page); manager.panels.select(.bookmarks)
        case "bookmarkEveryN":
            PDFDialogs.prompt(manager.language == .ru ? "Закладки через N страниц" : "Bookmarks every N pages",fields: [("N","1"),(manager.language == .ru ? "Префикс" : "Prefix",manager.language == .ru ? "Страница" : "Page")]) { [weak self] values in
                guard let self,let step = Int(values[0]),step > 0 else { return }
                for index in stride(from: 0,to: item.pageCount,by: step) { if let page = item.document.page(at: index) { self.manager.addBookmark(title: "\(values[1]) \(index+1)",page: page) } }
                self.manager.panels.select(.bookmarks)
            }
        case "bookmarkFromTOC":
            guard let text = page?.string else { return }
            let regex = try! NSRegularExpression(pattern: "^(.+?)\\s*[.·…\\s]+(\\d+)\\s*$")
            var added = 0
            for line in text.components(separatedBy: .newlines) {
                let string = line as NSString
                if let match = regex.firstMatch(in: line,range: NSRange(location: 0,length: string.length)),let number = Int(string.substring(with: match.range(at: 2))),let target = item.document.page(at: number-1) {
                    manager.addBookmark(title: string.substring(with: match.range(at: 1)),page: target); added += 1
                }
            }
            manager.say("Created \(added) bookmarks from this page.","Создано закладок: \(added). Используется текст текущей страницы.")
        case "bookmarkFromFile":
            PDFDialogs.open([.plainText]) { [weak self] urls in
                guard let self,let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data,encoding: .utf8) ?? String(data: data,encoding: .utf16) ?? String(data: data,encoding: .windowsCP1251) else { throw PDFSourceError.content }
                    let lines = text.components(separatedBy: .newlines)
                    for (offset,line) in lines.enumerated() where !line.isEmpty {
                        let parts = line.components(separatedBy: "\t"); let index = parts.count > 1 ? (Int(parts[0]) ?? 0)-1 : offset
                        if let page = item.document.page(at: index) { self.manager.addBookmark(title: parts.count > 1 ? parts.dropFirst().joined(separator: "\t") : line,page: page) }
                    }
                    self.manager.panels.select(.bookmarks)
                } catch { self.manager.say("Cannot read UTF-8 text file.","Не удалось прочитать текстовый файл UTF-8.") }
            }
        case "bookmarkAddText","bookmarkFind":
            PDFDialogs.prompt(manager.language == .ru ? "Изменить закладки" : "Modify bookmarks",fields: id == "bookmarkFind" ? [("Find / Найти",""),("Replace / Заменить","")] : [("Prefix / Префикс",""),("Suffix / Суффикс","")]) { [weak self] values in
                guard let self else { return }
                self.manager.recordUndo(item,group: "bookmarks")
                let nodes = self.manager.selectedOutline.map { [$0]+self.manager.bookmarkNodes($0) } ?? self.manager.bookmarkNodes()
                for node in nodes { let label = node.label ?? ""; node.label = id == "bookmarkFind" ? (values[0].isEmpty ? label : label.replacingOccurrences(of: values[0],with: values[1])) : values[0]+label+values[1] }; self.manager.send(.refresh)
            }
        case "bookmarkCase":
            PDFDialogs.prompt("Case / Регистр",fields: [("1: UPPER / ВЕРХНИЙ; 2: lower / нижний; 3: Title / Заглавные","1")]) { [weak self] values in
                guard let self else { return }; self.manager.recordUndo(item,group: "bookmarks")
                for node in self.manager.selectedOutline.map({ [$0]+self.manager.bookmarkNodes($0) }) ?? self.manager.bookmarkNodes() {
                    let text = node.label ?? ""; node.label = values[0] == "2" ? text.lowercased() : (values[0] == "3" ? text.capitalized : text.uppercased())
                }; self.manager.send(.refresh)
            }
        case "bookmarkZoom":
            for node in manager.selectedOutline.map({ [$0]+manager.bookmarkNodes($0) }) ?? manager.bookmarkNodes() { node.destination?.zoom = view.scaleFactor }; manager.send(.refresh)
        case "bookmarkActions":
            for node in manager.selectedOutline.map({ [$0]+manager.bookmarkNodes($0) }) ?? manager.bookmarkNodes() { node.action = nil; node.destination = nil }; manager.send(.refresh)
        case "bookmarkSort":
            if let root = manager.selectedOutline ?? manager.bookmarkRoot() { sortBookmarks(root) }; manager.send(.refresh)
        case "bookmarkMerge":
            if let root = manager.bookmarkRoot() { mergeBookmarks(root,document: item.document) }; manager.send(.refresh)
        case "bookmarkValidate":
            let nodes = manager.bookmarkNodes(),invalid = nodes.filter { $0.destination?.page == nil || item.document.index(for: $0.destination!.page!) == NSNotFound }.count
            manager.say("Bookmarks: \(nodes.count); invalid page targets: \(invalid)","Закладок: \(nodes.count); недействительных целей: \(invalid)")
        case "bookmarkText","bookmarkHTML": exportBookmarks(html: id == "bookmarkHTML",item: item)
        case "bookmarkTOC": createTOC(item: item,view: view)
        case "bookmarkLinks":
            guard let page else { return }
            for node in manager.bookmarkNodes() {
                guard let destination = node.destination,let title = node.label,!title.isEmpty else { continue }
                for selection in item.document.findString(title,withOptions: .caseInsensitive) where selection.pages.contains(page) {
                    let bounds = selection.bounds(for: page); guard !bounds.isEmpty else { continue }
                    let link = PDFAnnotation(bounds: bounds,forType: .link,withProperties: nil); link.action = PDFActionGoTo(destination: destination); page.addAnnotation(link)
                }
            }; view.setNeedsDisplay(view.bounds); manager.send(.refresh)
        case "bookmarkSortPages": sortPagesByBookmarks(item: item,view: view)
        case "blank": manager.createBlankDocument()
        case "fromFiles","insert": importPages(item: item,view: view)
        case "extract","split": exportPage(item: item,all: id == "split")
        case "swap":
            let index = item.pageIndex
            guard index+1 < item.pageCount else { return }; item.document.exchangePage(at: index,withPageAt: index+1); reload(view,document: item,pageIndex: index+1); manager.send(.refresh)
        case "crop":
            guard let page else { return }
            PDFDialogs.prompt("Crop / Обрезка",fields: [("Inset, pt / Отступ, pt","18")]) { [weak self,weak view] values in
                guard let self,let view,let inset = Double(values[0]),inset >= 0 else { return }
                let box = page.bounds(for: .mediaBox).insetBy(dx: inset,dy: inset); guard box.width > 1,box.height > 1 else { return }
                page.setBounds(box,for: .cropBox); self.reload(view,document: item,pageIndex: item.pageIndex); self.manager.send(.refresh)
            }
        case "images": exportImages(item: item)
        case "exportComments": exportComments(item: item)
        case "importComments": importComments(item: item,view: view)
        case "clear":
            for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" { field.widgetStringValue = ""; field.buttonWidgetState = .offState } }; view.setNeedsDisplay(view.bounds); manager.send(.refresh)
        case "fill": manager.tool = .textSelection; view.isInMarkupMode = false
        case "selectFields": manager.tool = .selectComments
        case "export": exportFormData(item: item)
        case "import": importFormData(item: item,view: view)
        case "watermark","header","bates": decoratePages(id,item: item,view: view)
        case "addImage": importImage(page: page,view: view)
        case "newWindow": PDFWindowPool.shared.open()
        case "cascade": for (index,window) in NSApp.windows.filter({ $0 is NSPanel == false }).enumerated() { window.setFrameOrigin(CGPoint(x: 100+index*24,y: 120+index*24)) }
        default: manager.say("Feature in development","Функция в разработке")
        }
    }
    func sortBookmarks(_ root: PDFOutline) {
        let children = (0..<root.numberOfChildren).compactMap { root.child(at: $0) }.sorted { ($0.label ?? "").localizedStandardCompare($1.label ?? "") == .orderedAscending }
        children.forEach { $0.removeFromParent() }
        for child in children { root.insertChild(child,at: root.numberOfChildren); sortBookmarks(child) }
    }
    func mergeBookmarks(_ root: PDFOutline,document: PDFDocument) {
        var seen: [String:PDFOutline] = [:]
        for child in (0..<root.numberOfChildren).compactMap({ root.child(at: $0) }) {
            let key = (child.label ?? "")+"|"+String(child.destination?.page.map { document.index(for: $0) } ?? -1)
            if let existing = seen[key] {
                let descendants = (0..<child.numberOfChildren).compactMap { child.child(at: $0) }
                for nested in descendants { nested.removeFromParent(); existing.insertChild(nested,at: existing.numberOfChildren) }; child.removeFromParent()
            } else { seen[key] = child }; mergeBookmarks(seen[key]!,document: document)
        }
    }
    func exportBookmarks(html: Bool,item: PDFDocumentItem) {
        let rows = makeBookmarkRows(root: manager.bookmarkRoot()!,document: item.document)
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: "\"",with: "&quot;") }
        let content: String
        if html {
            let lang = manager.language == .ru ? "ru" : "en"
            var result = "<!doctype html><html lang=\""+lang+"\"><meta charset=\"utf-8\"><title>Bookmarks</title><body><h1>"
            result += escape(item.filename)+"</h1><ul>"
            for row in rows { result += "<li>"+escape(row.title)+" — "+String(row.pageIndex+1)+"</li>" }
            result += "</ul></body></html>"; content = result
        } else {
            var lines: [String] = []
            for row in rows { let indent = String(repeating: "  ",count: row.depth); lines.append(String(row.pageIndex+1)+"\t"+indent+row.title) }
            content = lines.joined(separator: "\n")
        }
        PDFDialogs.save("Bookmarks."+(html ? "html" : "txt"),type: html ? .html : .plainText) { [weak self] url in
            do { try content.write(to: url,atomically: true,encoding: .utf8) } catch { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func createTOC(item: PDFDocumentItem,view: PDFViewerView) {
        guard let root = manager.bookmarkRoot() else { return }
        let rows = makeBookmarkRows(root: root,document: item.document).filter { $0.pageIndex >= 0 }
        guard !rows.isEmpty else { manager.say("Create bookmarks first.","Сначала создайте закладки."); return }
        let font = NSFont.systemFont(ofSize: 12)
        var batches: [[BookmarkRow]] = [],batch: [BookmarkRow] = [],used: CGFloat = 0
        for row in rows {
            let sample = String(repeating: "  ",count: min(8,row.depth))+row.title+" .... 9999"
            let height = (sample as NSString).boundingRect(with: CGSize(width: 532,height: 10000),options: [.usesLineFragmentOrigin,.usesFontLeading],attributes: [.font: font]).height+18
            if !batch.isEmpty && used+height > 650 { batches.append(batch); batch = []; used = 0 }
            batch.append(row); used += height
        }
        if !batch.isEmpty { batches.append(batch) }
        let pages = batches.count
        for batch in batches.reversed() {
            let text = (manager.language == .ru ? "СОДЕРЖАНИЕ" : "TABLE OF CONTENTS")+"\n\n"+batch.map { String(repeating: "  ",count: min(8,$0.depth))+$0.title+" .... \($0.pageIndex+pages+1)" }.joined(separator: "\n\n")
            if let page = PDFRasterizer.textPage(text) { item.document.insert(page,at: 0) }
        }; reload(view,document: item,pageIndex: 0); manager.send(.refresh)
    }
    func sortPagesByBookmarks(item: PDFDocumentItem,view: PDFViewerView) {
        let indices = manager.bookmarkNodes().compactMap { $0.destination?.page.map { item.document.index(for: $0) } }.filter { $0 >= 0 && $0 < item.pageCount }
        var order: [Int] = []; for index in indices+Array(0..<item.pageCount) where !order.contains(index) { order.append(index) }
        let old = (0..<item.pageCount).compactMap { item.document.page(at: $0) }
        let links = manager.bookmarkNodes().compactMap { node -> (PDFOutline,Int,CGPoint)? in guard let destination = node.destination,let page = destination.page else { return nil }; return (node,item.document.index(for: page),destination.point) }
        let copies = old.compactMap { $0.copy() as? PDFPage }; guard copies.count == old.count else { return }
        for (source,copy) in zip(old,copies) { AnnotationMetadata.copy(from: source,to: copy) }
        while item.document.pageCount > 0 { item.document.removePage(at: 0) }
        for index in order { item.document.insert(copies[index],at: item.document.pageCount) }
        for (node,index,point) in links where copies.indices.contains(index) { node.destination = PDFDestination(page: copies[index],at: point) }
        reload(view,document: item,pageIndex: 0); manager.send(.refresh)
    }
    func importPages(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.pdf]) { [weak self,weak view] urls in
            guard let self,let view else { return }; var target = item.pageIndex+1
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let doc = PDFDocument(url: url) else { continue }; AnnotationMetadata.restore(doc)
                for index in 0..<doc.pageCount { if let page = doc.page(at: index),let copy = page.copy() as? PDFPage { AnnotationMetadata.copy(from: page,to: copy); item.document.insert(copy,at: target); target += 1 } }
            }; self.reload(view,document: item,pageIndex: item.pageIndex); self.manager.send(.refresh)
        }
    }
    func exportPage(item: PDFDocumentItem,all: Bool) {
        if all {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.begin { [weak self] response in
                guard response == .OK,let folder = panel.url else { return }
                let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
                var failed = false
                for index in 0..<item.pageCount {
                    guard let source = item.document.page(at: index),let copy = source.copy() as? PDFPage else { failed = true; continue }
                    AnnotationMetadata.copy(from: source,to: copy); let doc = PDFDocument(); doc.insert(copy,at: 0); AnnotationMetadata.prepareForSave(doc)
                    var url = folder.appendingPathComponent(String(format: "Page-%03d.pdf",index+1))
                    if FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("Page-\(index+1)-"+UUID().uuidString.prefix(6)+".pdf") }
                    if !doc.write(to: url) { failed = true }
                }; self?.manager.say(failed ? "Some pages could not be exported" : "Pages split into separate PDF files",failed ? "Не все страницы удалось экспортировать" : "Страницы сохранены отдельными PDF")
            }; return
        }
        PDFDialogs.save(all ? "Split.pdf" : "Page-\(item.pageIndex+1).pdf",type: .pdf) { [weak self] url in
            let export = PDFDocument()
            let indices = all ? Array(0..<item.pageCount) : [item.pageIndex]
            for index in indices { if let source = item.document.page(at: index),let copy = source.copy() as? PDFPage { AnnotationMetadata.copy(from: source,to: copy); export.insert(copy,at: export.pageCount) } }
            AnnotationMetadata.prepareForSave(export)
            if !export.write(to: url,withOptions: [PDFDocumentWriteOption.saveTextFromOCROption:false]) { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func exportImages(item: PDFDocumentItem) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK,let folder = panel.url else { return }
            let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                for index in 0..<item.pageCount {
                    guard let page = item.document.page(at: index) else { continue }; let box = page.bounds(for: .cropBox)
                    let scale = min(2,4096/max(box.width,box.height)); let image = PDFRasterizer.image(page,size: CGSize(width: box.width*scale,height: box.height*scale))
                    guard let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data: tiff),let png = bitmap.representation(using: .png,properties: [:]) else { continue }
                    var url = folder.appendingPathComponent(String(format:"Page-%03d.png",index+1))
                    if FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("Page-\(index+1)-"+UUID().uuidString.prefix(6)+".png") }
                    try png.write(to: url)
                }; self?.manager.say("Images exported","Изображения экспортированы")
            } catch { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func exportComments(item: PDFDocumentItem) {
        PDFDialogs.save("Comments.pdf",type: .pdf) { [weak self] url in
            let result = PDFDocument()
            for index in 0..<item.pageCount {
                guard let source = item.document.page(at: index) else { continue }; let page = PDFPage(); page.setBounds(source.bounds(for: .mediaBox),for: .mediaBox); page.setBounds(source.bounds(for: .cropBox),for: .cropBox)
                for annotation in source.annotations where !AnnotationMetadata.isContainer(annotation) { if let copy = annotation.copy() as? PDFAnnotation { copy.page = nil; AnnotationMetadata.transfer(from: [annotation],to: [copy]); page.addAnnotation(copy) } }; result.insert(page,at: result.pageCount)
            }; AnnotationMetadata.prepareForSave(result)
            if !result.write(to: url) { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func importComments(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.pdf]) { [weak self,weak view] urls in
            guard let self,let view else { return }
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let source = PDFDocument(url: url) else { continue }; AnnotationMetadata.restore(source)
                for index in 0..<min(source.pageCount,item.pageCount) { guard let page = item.document.page(at: index) else { continue }
                    for annotation in source.page(at: index)?.annotations ?? [] where !AnnotationMetadata.isContainer(annotation) {
                        if let copy = annotation.copy() as? PDFAnnotation { copy.page = nil; AnnotationMetadata.transfer(from: [annotation],to: [copy]); page.addAnnotation(copy) }
                    }
                }
            }; view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
        }
    }
    func decoratePages(_ id: String,item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.prompt(manager.language == .ru ? "Оформление страниц" : "Page decoration",fields: [("Text / Текст",id == "watermark" ? "DRAFT" : "BotPlus")]) { [weak self,weak view] values in
            guard let self,let view else { return }
            for index in 0..<item.pageCount { guard let page = item.document.page(at: index) else { continue }; let crop = page.bounds(for: .cropBox),watermark = id == "watermark"
                let rect = CGRect(x: crop.minX+20,y: watermark ? crop.midY-25 : crop.maxY-40,width: crop.width-40,height: 30)
                let annotation = PDFAnnotation(bounds: rect,forType: .freeText,withProperties: nil); annotation.contents = values[0]+(id == "bates" ? String(format:"-%06d",index+1) : ""); annotation.color = .clear; annotation.fontColor = NSColor(self.manager.annotationColor).withAlphaComponent(watermark ? 0.2 : 1); annotation.font = NSFont.boldSystemFont(ofSize: watermark ? 28 : 12); annotation.alignment = .center; AnnotationMetadata.setOpacity(watermark ? 0.2 : 1,on: annotation); page.addAnnotation(annotation)
            }; view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
        }
    }
    func importImage(page: PDFPage?,view: PDFViewerView) {
        guard let page else { return }
        PDFDialogs.open([.image]) { [weak self,weak view] urls in
            guard let self,let view,let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let image = NSImage(contentsOf: url),image.size.width > 0 else { return }
            let crop = page.bounds(for: .cropBox),width = min(240,crop.width*0.7),height = min(crop.height*0.7,width*image.size.height/image.size.width)
            guard let item = self.manager.selected,let cgImage = image.cgImage(forProposedRect: nil,context: nil,hints: nil) else { return }
            let index = item.document.index(for: page),rect = CGRect(x: crop.midX-width/2,y: crop.midY-height/2,width: width,height: height)
            do {
                let data = try PDFSourceSession.insertingImage(data: self.sourceData(item),pageIndex: index,image: cgImage,bounds: rect)
                try self.installSourceData(data,item: item,index: index,view: view,bounds: rect)
                self.manager.selectedContent = PDFSourceSession.ContentObject(kind: "image",bounds: rect,pixelSize: CGSize(width: cgImage.width,height: cgImage.height)); self.manager.panels.select(.properties)
            } catch { self.sourceError(error) }
        }
    }
}


private extension PDFViewerView {
    func zoom(to rect: CGRect,on page: PDFPage) {
        let viewport = bounds.size,current = convert(rect,from: page)
        guard current.width > 0,current.height > 0 else { return }
        autoScales = false; scaleFactor = min(maxScaleFactor,max(minScaleFactor,scaleFactor*min(viewport.width/current.width,viewport.height/current.height)*0.95))
        go(to: PDFDestination(page: page,at: CGPoint(x: rect.minX,y: rect.maxY))); onViewportChange?()
    }
}

@MainActor
private final class PDFWindowPool: NSObject,NSWindowDelegate {
    static let shared = PDFWindowPool()
    private var windows: [NSWindow] = []
    func open() {
        let window = NSWindow(contentRect: CGRect(x: 80,y: 80,width: 1280,height: 820),styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
        window.contentView = NSHostingView(rootView: ContentView().frame(minWidth: 1060,minHeight: 700)); window.title = BotPlusBrand.name; window.isReleasedWhenClosed = false; window.delegate = self
        windows.append(window); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { if let window = notification.object as? NSWindow { windows.removeAll { $0 === window } } }
}

@MainActor
private enum PDFWidgetFactory {
    static func make(_ tool: PDFTool,bounds: CGRect,name: String,choices: [String]) -> PDFAnnotation {
        let field = PDFAnnotation(bounds: bounds,forType: .widget,withProperties: nil)
        field.fieldName = name; field.color = .white; field.font = NSFont.systemFont(ofSize: 14); field.fontColor = .black
        let border = PDFBorder(); border.lineWidth = 1; field.border = border
        switch tool {
        case .formText: field.widgetFieldType = .text; field.widgetStringValue = ""
        case .formChoice: field.widgetFieldType = .choice; field.choices = choices; field.isListChoice = false; field.widgetStringValue = choices.first ?? ""
        default:
            field.widgetFieldType = .button
            field.widgetControlType = tool == .formRadio ? .radioButtonControl : (tool == .formButton ? .pushButtonControl : .checkBoxControl)
            field.buttonWidgetStateString = tool == .formRadio ? UUID().uuidString : "Yes"; field.buttonWidgetState = .offState
            if tool == .formButton { field.caption = name; field.action = PDFActionResetForm() }
        }
        field.fieldName = name
        field.font = NSFont.systemFont(ofSize: 14); field.fontColor = .black
        return field
    }
}

@MainActor
private extension PDFViewer.Coordinator {
    func formValues(_ item: PDFDocumentItem) -> [String:String] {
        var values: [String:String] = [:]
        for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" {
            guard let name = field.fieldName else { continue }
            if field.widgetFieldType == .button {
                if field.buttonWidgetState == .onState { values[name] = field.buttonWidgetStateString }
                else if values[name] == nil { values[name] = "Off" }
            } else { values[name] = field.widgetStringValue ?? "" }
        } }; return values
    }
    func exportFormData(item: PDFDocumentItem) {
        guard let data = try? JSONEncoder().encode(formValues(item)) else { return }
        PDFDialogs.save("FormData.json",type: .json) { [weak self] url in do { try data.write(to: url) } catch { self?.manager.say("Export failed","Ошибка экспорта") } }
    }
    func importFormData(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.json]) { [weak self,weak view] urls in
            guard let self,let view,let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try JSONDecoder().decode([String:String].self,from: Data(contentsOf: url))
                for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" {
                    guard let name = field.fieldName,let value = values[name] else { continue }
                    if field.widgetFieldType == .button { field.buttonWidgetState = field.buttonWidgetStateString == value ? .onState : .offState }
                    else { field.widgetStringValue = value }
                } }; view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
            } catch { self.manager.say("Invalid form JSON file","Некорректный JSON-файл формы") }
        }
    }
}

@MainActor
private extension DocumentManager {
    func snapshot(_ item: PDFDocumentItem) -> PDFDocumentItem.Snapshot? {
        AnnotationMetadata.prepareForSave(item.document); defer { AnnotationMetadata.removeContainers(item.document) }
        guard let data = try? PDFDocumentSerializer.data(item.document) else { return nil }
        return PDFDocumentItem.Snapshot(data: data,page: item.pageIndex,zoom: item.zoom,bookmarks: PDFBookmarkStore.capture(item.document))
    }
    func recordUndo(_ item: PDFDocumentItem,group: String) {
        let now = Date()
        if item.historyGroup == group && now.timeIntervalSince(item.historyDate) < 0.4 { item.historyDate = now; return }
        guard let state = snapshot(item) else { return }
        item.undoHistory.append(state); item.redoHistory.removeAll(); item.historyGroup = group; item.historyDate = now
        while item.undoHistory.count > 1 && item.undoHistory.reduce(0,{ $0+$1.data.count }) > 64*1024*1024 { item.undoHistory.removeFirst() }
    }
    func undoDocument(redo: Bool) {
        if textProperties.active,let editor = NSApp.keyWindow?.firstResponder as? NSTextView,let undo = editor.undoManager {
            if redo && undo.canRedo { undo.redo(); return }
            if !redo && undo.canUndo { undo.undo(); return }
        }
        guard finishSourceEditing?() != false,let item = selected,let current = snapshot(item) else { return }
        guard let state = redo ? item.redoHistory.popLast() : item.undoHistory.popLast(),let document = PDFDocument(data: state.data) else { return }
        if redo { item.undoHistory.append(current) } else { item.redoHistory.append(current) }
        AnnotationMetadata.restore(document); PDFBookmarkStore.restore(state.bookmarks,on: document)
        selectedOutline = nil; selectedAnnotation = nil; selectedContent = nil
        item.document = document; item.pageIndex = min(max(0,state.page),document.pageCount-1); item.zoom = state.zoom
        item.historyGroup = ""; item.historyDate = .distantPast; pageText = String(item.pageIndex+1); send(.refresh)
    }
}

private extension PDFViewerView {
    func resetPagePadding() {
        let margin = pageBreakMargins
        if margin.top != 8 || margin.bottom != 8 { pageBreakMargins = NSEdgeInsets(top: 8,left: 8,bottom: 8,right: 8) }
    }
}

@MainActor
private enum PDFDocumentSerializer {
    static func save(_ document: PDFDocument,to url: URL) throws {
        let data = try self.data(document)
        if !FileManager.default.isUbiquitousItem(at: url) { try data.write(to: url,options: .atomic); return }
        var coordinationError: NSError?,writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url,options: .forReplacing,error: &coordinationError) { target in
            do { try data.write(to: target,options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
    }
    static func data(_ document: PDFDocument) throws -> Data {
        let bookmarks = PDFBookmarkStore.capture(document),copy = PDFDocument()
        // Copy the current pages and annotations rather than PDFKit's cached
        // dataRepresentation, which can omit live outline/form changes.
        for index in 0..<document.pageCount {
            guard let original = document.page(at: index),let cloned = original.copy() as? PDFPage else { throw PDFSourceError.page }
            AnnotationMetadata.copy(from: original,to: cloned); copy.insert(cloned,at: copy.pageCount)
        }
        copy.documentAttributes = document.documentAttributes
        PDFBookmarkStore.restore(bookmarks,on: copy); AnnotationMetadata.prepareForSave(copy)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlusSnapshot-"+UUID().uuidString+".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        guard copy.write(to: url,withOptions: [PDFDocumentWriteOption.saveTextFromOCROption:false]) else { throw PDFSourceError.save }
        return try PDFSourceSession.validEmptyPageStreams(Data(contentsOf: url))
    }
}

@MainActor
private enum PDFBookmarkStore {
    struct Record {
        let title: String
        let page: Int?
        let point: CGPoint
        let zoom: CGFloat
        let action: PDFAction?
        let children: [Record]
    }
    static func capture(_ document: PDFDocument) -> [Record]? {
        guard let root = document.outlineRoot else { return nil }
        @MainActor func children(_ parent: PDFOutline,depth: Int) -> [Record] {
            guard depth < 64 else { return [] }
            return (0..<parent.numberOfChildren).compactMap { index in
                guard let node = parent.child(at: index) else { return nil }
                let candidate = node.destination?.page.map { document.index(for: $0) }
                let page = candidate.flatMap { $0 >= 0 && $0 < document.pageCount ? $0 : nil }
                return Record(title: node.label ?? "",page: page,point: node.destination?.point ?? .zero,zoom: node.destination?.zoom ?? 0,action: page == nil ? node.action?.copy() as? PDFAction : nil,children: children(node,depth: depth+1))
            }
        }
        return children(root,depth: 0)
    }
    static func restore(_ records: [Record]?,on document: PDFDocument) {
        guard let records else { document.outlineRoot = nil; return }
        let root = PDFOutline()
        @MainActor func append(_ records: [Record],to parent: PDFOutline) {
            for record in records {
                let node = PDFOutline(); node.label = record.title
                if let index = record.page,let page = document.page(at: index) { let destination = PDFDestination(page: page,at: record.point); destination.zoom = record.zoom; node.destination = destination }
                else { node.action = record.action }
                append(record.children,to: node); parent.insertChild(node,at: parent.numberOfChildren)
            }
        }
        append(records,to: root); document.outlineRoot = root
    }
}

@MainActor
private extension DocumentManager {
    func createFromFiles() {
        PDFDialogs.open([.pdf]) { [weak self] urls in
            guard let self else { return }; let document = PDFDocument(); var bookmarks: [PDFBookmarkStore.Record] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let source = PDFDocument(url: url),!source.isLocked else { continue }; AnnotationMetadata.restore(source)
                let offset = document.pageCount
                for index in 0..<source.pageCount {
                    if let page = source.page(at: index),let copy = page.copy() as? PDFPage { AnnotationMetadata.copy(from: page,to: copy); document.insert(copy,at: document.pageCount) }
                }
                @MainActor func shifted(_ record: PDFBookmarkStore.Record) -> PDFBookmarkStore.Record {
                    PDFBookmarkStore.Record(title: record.title,page: record.page.map { $0+offset },point: record.point,zoom: record.zoom,action: record.action,children: record.children.map(shifted))
                }
                let children = (PDFBookmarkStore.capture(source) ?? []).map(shifted)
                if offset < document.pageCount { bookmarks.append(PDFBookmarkStore.Record(title: url.lastPathComponent,page: offset,point: CGPoint(x: 0,y: document.page(at: offset)?.bounds(for: .cropBox).maxY ?? 792),zoom: 0,action: nil,children: children)) }
            }
            guard document.pageCount > 0 else { self.say("No readable PDF pages selected.","Не выбраны доступные страницы PDF."); return }
            PDFBookmarkStore.restore(bookmarks,on: document)
            let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf"),document: document); entry.isUntitled = true; self.insertDocument(entry)
        }
    }
}

@MainActor
private struct ThumbnailGestureRegion: NSViewRepresentable {
    @ObservedObject var manager: DocumentManager
    func makeNSView(context: Context) -> ThumbnailGestureView {
        let view = ThumbnailGestureView(frame: .zero); view.manager = manager; return view
    }
    func updateNSView(_ view: ThumbnailGestureView,context: Context) { view.manager = manager }
    static func dismantleNSView(_ view: ThumbnailGestureView,coordinator: ()) { view.stop() }
}

@MainActor
private final class ThumbnailGestureView: NSView {
    weak var manager: DocumentManager?
    private var monitor: Any?
    private var pendingValue: Double?
    private var scheduled = false
    private var detailWork: DispatchWorkItem?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop(); guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify,.scrollWheel]) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated {
                guard let self,let point = HoverEventLocation.point(for: event,in: self),self.visibleRect.contains(point) else { return }
                if event.type == .magnify { self.adjust(Double(event.magnification)); handled = true }
                else if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) {
                    self.adjust(Double(-event.scrollingDeltaY)*(event.hasPreciseScrollingDeltas ? 0.01 : 0.12)); handled = true
                }
            }
            return handled ? nil : event
        }
    }
    func adjust(_ delta: Double) {
        guard delta.isFinite,let manager else { return }
        if !manager.thumbnailGestureActive { manager.thumbnailGestureActive = true }
        detailWork?.cancel()
        let work = DispatchWorkItem { [weak manager] in manager?.thumbnailGestureActive = false }
        detailWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18,execute: work)
        pendingValue = Self.zoom((pendingValue ?? manager.thumbnailZoom),delta: delta)
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }
    func flush() {
        scheduled = false
        if let value = pendingValue { pendingValue = nil; manager?.thumbnailZoom = value }
    }
    static func zoom(_ value: Double,delta: Double) -> Double { min(1,max(0,value+delta*0.75)) }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; pendingValue = nil; detailWork = nil }
}

@MainActor
private final class PDFThumbnailCache {
    static let shared = PDFThumbnailCache()
    private final class Raster {
        let image: NSImage; let resolution: Int
        init(_ image: NSImage,resolution: Int) { self.image = image; self.resolution = resolution }
    }
    private let cache = NSCache<NSString,Raster>()
    private(set) var renderCount = 0
    init() { cache.totalCostLimit = 48*1024*1024; cache.countLimit = 240 }
    func image(page: PDFPage,documentID: UUID,index: Int,revision: Int,width: CGFloat,ratio: CGFloat,interactive: Bool = false) -> NSImage {
        let bucket = min(1280,max(128,Int(ceil(width*2/128))*128))
        let key = "\(documentID.uuidString)|\(index)|\(revision)" as NSString
        // During a gesture, immediately scale the current raster. Upgrade its
        // detail after the gesture settles, without storing every zoom size.
        if let raster = cache.object(forKey: key),interactive || raster.resolution >= bucket { return raster.image }
        let height = max(1,CGFloat(bucket)*max(0.1,min(12,ratio)))
        let factor = min(1,4096/max(CGFloat(bucket),height))
        let w = max(1,Int(CGFloat(bucket)*factor)),h = max(1,Int(height*factor))
        guard let ref = page.pageRef,let context = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: w*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(size: CGSize(width: width,height: width*ratio)) }
        let rect = CGRect(x: 0,y: 0,width: w,height: h)
        context.setFillColor(NSColor.white.cgColor); context.fill(rect)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context,flipped: false)
        context.concatenate(ref.getDrawingTransform(.cropBox,rect: rect,rotate: 0,preserveAspectRatio: true)); context.drawPDFPage(ref)
        for annotation in page.annotations where annotation.shouldDisplay && !AnnotationMetadata.isContainer(annotation) { annotation.draw(with: .cropBox,in: context) }
        NSGraphicsContext.restoreGraphicsState()
        guard let bitmap = context.makeImage() else { return NSImage(size: rect.size) }
        let image = NSImage(cgImage: bitmap,size: CGSize(width: width,height: width*ratio))
        cache.setObject(Raster(image,resolution: bucket),forKey: key,cost: w*h*4); renderCount += 1; return image
    }
}

@MainActor
private enum HoverEventLocation {
    static func point(for event: NSEvent,in view: NSView) -> CGPoint? {
        guard let window = view.window,window.isVisible,!view.isHiddenOrHasHiddenAncestor else { return nil }
        // Gesture delivery follows the responder chain, which may still point
        // at Search or a different pane. Route by the actual pointer instead.
        let screen = NSEvent.mouseLocation
        guard window.frame.contains(screen) else { return nil }
        if let modal = NSApp.modalWindow,modal !== window { return nil }
        if let eventWindow = event.window,eventWindow !== window,eventWindow.isKeyWindow { return nil }
        return view.convert(window.convertPoint(fromScreen: screen),from: nil)
    }
}
