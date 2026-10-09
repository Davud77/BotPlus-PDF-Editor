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
    case hand, textSelection, selectComments, highlight
    var title: Bilingual {
        switch self {
        case .hand: Bilingual(en: "Hand", ru: "Рука")
        case .textSelection: Bilingual(en: "Text Selection", ru: "Выделить текст")
        case .selectComments: Bilingual(en: "Select Comments", ru: "Выделить комментарии")
        case .highlight: Bilingual(en: "Highlight Text", ru: "Подсветить текст")
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
}

private struct RulerMetrics: Equatable {
    var scale: CGFloat = 1
    var pageBounds = CGRect.zero
    var topLeft = CGPoint.zero
    var valid = false
}

@MainActor
private final class PanelWorkspaceModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var configurations: [WorkspacePanel: PanelConfiguration]
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
            configurations = defaults.merging(saved) { _, savedValue in savedValue }
        } else { configurations = defaults }
        super.init()
    }

    func configuration(for panel: WorkspacePanel) -> PanelConfiguration {
        configurations[panel] ?? PanelConfiguration(isVisible: false, dock: .left, width: 230)
    }

    func setVisible(_ visible: Bool, for panel: WorkspacePanel) { update(panel) { $0.isVisible = visible } }
    func setDock(_ dock: PanelDock, for panel: WorkspacePanel) { update(panel) { $0.dock = dock } }
    func setWidth(_ width: CGFloat, for panel: WorkspacePanel) { update(panel) { $0.width = Double(min(550, max(180, width))) } }
    func resize(_ panel: WorkspacePanel, translation: CGFloat) {
        let start = resizeStarts[panel] ?? CGFloat(configuration(for: panel).width)
        resizeStarts[panel] = start
        setWidth(start + translation, for: panel)
    }
    func endResize(_ panel: WorkspacePanel) { resizeStarts[panel] = nil }

    private func update(_ panel: WorkspacePanel, change: (inout PanelConfiguration) -> Void) {
        var next = configurations
        var configuration = self.configuration(for: panel)
        change(&configuration)
        next[panel] = configuration
        configurations = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: persistenceKey) }
    }

    func synchronizeFloatingWindows(manager: DocumentManager) {
        for panel in WorkspacePanel.allCases {
            let config = configuration(for: panel)
            if config.isVisible && config.dock == .floating {
                if let window = floatingWindows[panel] {
                    if window.title != manager.text(panel.title) { window.title = manager.text(panel.title) }
                    continue
                }
                let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: config.width, height: 400),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                     backing: .buffered, defer: false)
                window.title = manager.text(panel.title)
                window.isReleasedWhenClosed = false
                window.minSize = NSSize(width: 180, height: 180)
                window.maxSize = NSSize(width: 550, height: 1200)
                window.delegate = self
                window.contentView = NSHostingView(rootView: FloatingPanelContents(panel: panel, panels: self, manager: manager))
                window.setFrameAutosaveName("BotPlusPDFEditor.\(panel.rawValue).floating")
                window.makeKeyAndOrderFront(nil)
                floatingWindows[panel] = window
            } else if let window = floatingWindows[panel] {
                suppressedClose.insert(ObjectIdentifier(window))
                floatingWindows[panel] = nil
                window.close()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let identity = ObjectIdentifier(window)
        if suppressedClose.remove(identity) != nil { return }
        guard let panel = floatingWindows.first(where: { $0.value === window })?.key else { return }
        floatingWindows[panel] = nil
        setVisible(false, for: panel)
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
    let url: URL
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
    @Published var pageText = "1"
    @Published var searchText = ""
    @Published var notice: String?
    @Published var commandIndex = 0
    @Published var command: ViewerCommand = .refresh
    @Published var rulerMetrics = RulerMetrics()
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

    func save() {
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        guard selected.document.write(to: selected.url) else { say("Could not save the PDF.", "Не удалось сохранить PDF-файл."); return }
    }
    func saveAs() {
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = selected.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard selected.document.write(to: url) else { say("Could not save the PDF.", "Не удалось сохранить PDF-файл."); return }
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
        case .save: save()
        case .saveAs: saveAs()
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
        case .highlight: tool = .highlight; send(.highlight)
        case .toggleLanguage: language = language == .ru ? .en : .ru
        case .toggleRulers: rulersVisible.toggle()
        case .panels: break
        case .languagePicker: break
        case .about: isAboutPresented = true
        case .development: say("Feature in development", "Функция в разработке")
        }
    }
}

private enum ViewerCommand: Equatable {
    case refresh, zoomIn, zoomOut, actualSize, fitPage, fitWidth, rotate(Int), page(Int), highlight, print
    case setZoom(CGFloat)
}

private enum RibbonAction {
    case open, save, saveAs, close, print, settings
    case tool(PDFTool), layout(PageLayout), zoomIn, zoomOut, actualSize, fitPage, fitWidth
    case rotateLeft, rotateRight, previous, next, first, last, highlight, toggleLanguage, toggleRulers
    case panels, languagePicker, about, development
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
        .foregroundStyle(Palette.text)
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenPDF)) { _ in manager.openPanel() }
        .onReceive(manager.panels.$configurations) { _ in manager.panels.synchronizeFloatingWindows(manager: manager) }
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
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent).padding(.horizontal, 5)
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
                    TextField(manager.language == .ru ? "Быстрый поиск…" : "Quick Search...", text: $manager.searchText, onCommit: { manager.send(.refresh) })
                        .textFieldStyle(.plain).frame(width: 135)
                }.padding(.horizontal, 8).frame(height: 25).background(Palette.raised, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 37).background(Palette.ribbon)
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
                RibbonGroupSpec("comment", "Comment", "Комментарий", [cmd("typewriter", "Typewriter", "Печатная машинка", "character.cursor.ibeam"), RibbonCommand("highlight", "Highlight Text", "Подсветить текст", "highlighter", .highlight), cmd("underline", "Underline", "Подчёркивание", "underline"), cmd("stamp", "Stamp", "Штамп", "seal"), cmd("sticky", "Sticky Note", "Заметка", "note.text")]),
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
                RibbonGroupSpec("text", "Text", "Текст", [cmd("typewriter", "Typewriter", "Печатная машинка", "character.cursor.ibeam"), cmd("textBox", "Text Box", "Текстовое поле", "text.alignleft"), cmd("callout", "Callout", "Выноска", "text.bubble")]),
                RibbonGroupSpec("note", "Note", "Заметка", [cmd("note", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("markup", "Text Markup", "Разметка текста", [RibbonCommand("highlight", "Highlight", "Подсветка", "highlighter", .highlight), cmd("strike", "Strikethrough", "Зачёркивание", "strikethrough"), cmd("underline", "Underline", "Подчёркивание", "underline")]),
                RibbonGroupSpec("drawing", "Drawing", "Рисование", [cmd("line", "Line", "Линия", "line.diagonal"), cmd("arrow", "Arrow", "Стрелка", "arrow.up.right"), cmd("rect", "Rectangle", "Прямоугольник", "rectangle"), cmd("cloud", "Cloud", "Облако", "cloud"), cmd("pencil", "Pencil", "Карандаш", "pencil.tip"), cmd("eraser", "Eraser", "Ластик", "eraser")]),
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
            return [RibbonGroupSpec("pages", "Pages", "Страницы", [cmd("insert", "Insert", "Вставить", "doc.badge.plus"), cmd("delete", "Delete", "Удалить", "trash"), cmd("extract", "Extract", "Извлечь", "doc.zipper"), cmd("replace", "Replace", "Заменить", "arrow.2.squarepath"), cmd("split", "Split", "Разделить", "scissors"), cmd("swap", "Swap", "Поменять", "arrow.left.arrow.right")]),
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
    let command: RibbonCommand
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
    private var leftPanels: [WorkspacePanel] {
        WorkspacePanel.allCases.filter { let config = manager.panels.configuration(for: $0); return config.isVisible && config.dock == .left }
    }
    private var rightPanels: [WorkspacePanel] {
        WorkspacePanel.allCases.filter { let config = manager.panels.configuration(for: $0); return config.isVisible && config.dock == .right }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(leftPanels) { panel in PanelSlot(panel: panel, manager: manager, resizeFromLeft: true) }
            if manager.selected != nil {
                viewer
            } else { EmptyWorkspace(manager: manager) }
            ForEach(rightPanels) { panel in PanelSlot(panel: panel, manager: manager, resizeFromLeft: false) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewer: some View {
        HStack(spacing: 0) {
            if manager.rulersVisible {
                RulerBar(axis: .vertical, manager: manager).frame(width: 30)
            }
            VStack(spacing: 0) {
                if manager.rulersVisible { RulerBar(axis: .horizontal, manager: manager).frame(height: 25) }
                PDFViewer(manager: manager).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(white: 0.12))
    }
}

private struct PanelSlot: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    let resizeFromLeft: Bool
    var body: some View {
        let config = manager.panels.configuration(for: panel)
        HStack(spacing: 0) {
            if !resizeFromLeft { PanelResizeHandle(panel: panel, manager: manager, direction: -1) }
            VStack(spacing: 0) {
                PanelHeader(panel: panel, manager: manager)
                PanelBody(panel: panel, manager: manager)
            }
            .frame(width: CGFloat(config.width)).frame(maxHeight: .infinity)
            .background(Color(red: 0.20, green: 0.20, blue: 0.20))
            .overlay(alignment: resizeFromLeft ? .trailing : .leading) { Palette.separator.frame(width: 1) }
            if resizeFromLeft { PanelResizeHandle(panel: panel, manager: manager, direction: 1) }
        }
    }
}

private struct PanelResizeHandle: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    let direction: CGFloat
    var body: some View {
        Rectangle().fill(Color.clear).frame(width: 6).contentShape(Rectangle())
            .overlay(Palette.separator.opacity(0.7).frame(width: 1))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    manager.panels.resize(panel, translation: direction * value.translation.width)
                }
                .onEnded { _ in manager.panels.endResize(panel) })
            .help(manager.language == .ru ? "Перетащите, чтобы изменить ширину" : "Drag to resize panel")
    }
}

private struct PanelHeader: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: panel.symbol).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text(manager.text(panel.title)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 2)
            Menu {
                ForEach(PanelDock.allCases) { dock in
                    Button {
                        manager.panels.setDock(dock, for: panel)
                        manager.panels.setVisible(true, for: panel)
                    } label: {
                        if manager.panels.configuration(for: panel).dock == dock {
                            Label(manager.text(dock.title), systemImage: "checkmark")
                        } else { Text(manager.text(dock.title)) }
                    }
                }
            } label: { Image(systemName: "rectangle.leadingthird.inset.filled").font(.system(size: 10)).frame(width: 22, height: 20) }
                .menuStyle(.borderlessButton).help(manager.language == .ru ? "Положение панели" : "Panel docking")
            Button { manager.panels.setVisible(false, for: panel) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
            }.buttonStyle(.plain).help(manager.language == .ru ? "Закрыть панель" : "Close panel")
        }.padding(.horizontal, 8).frame(height: 30).background(Palette.raised)
            .overlay(alignment: .bottom) { Palette.separator.frame(height: 1) }
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
                    return page.annotations.map { (index, $0) }
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
        }.frame(minWidth: 180, minHeight: 180)
    }
}

private struct StatusBar: View {
    @ObservedObject var manager: DocumentManager
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
    private let drafting = Color(red: 0.125, green: 0.125, blue: 0.125)
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(drafting))
            guard manager.rulerMetrics.valid, manager.rulerMetrics.scale > 0 else {
                drawEdge(in: &context, size: size)
                return
            }
            switch axis {
            case .horizontal: drawHorizontal(in: &context, size: size)
            case .vertical: drawVertical(in: &context, size: size)
            }
            drawEdge(in: &context, size: size)
        }
        .background(drafting)
        .accessibilityLabel(manager.language == .ru ? "Линейка документа в пунктах PDF" : "PDF point ruler")
    }

    private func drawHorizontal(in context: inout GraphicsContext, size: CGSize) {
        let metrics = manager.rulerMetrics
        let scale = metrics.scale
        let start = metrics.pageBounds.minX + (0 - metrics.topLeft.x) / scale
        let end = metrics.pageBounds.minX + (size.width - metrics.topLeft.x) / scale
        let major = rulerInterval(for: 78 / scale)
        let fine = major / 10
        let first = floor(start / fine) * fine
        var value = first
        var count = 0
        while value <= end + fine && count < 2500 {
            let x = metrics.topLeft.x + (value - metrics.pageBounds.minX) * scale
            if x >= 0 && x <= size.width {
                let isMajor = abs(value / major - (value / major).rounded()) < 0.0001
                let isMedium = !isMajor && abs(value / (major / 2) - (value / (major / 2)).rounded()) < 0.0001
                let length: CGFloat = isMajor ? 15 : (isMedium ? 10 : 5)
                var tick = Path(); tick.move(to: CGPoint(x: x, y: size.height)); tick.addLine(to: CGPoint(x: x, y: size.height - length))
                context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.8 : 0.42)), lineWidth: 1)
                if isMajor {
                    let label = Text(String(format: "%.0f", value)).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.82))
                    context.draw(label, at: CGPoint(x: x + 3, y: 7), anchor: .topLeading)
                }
            }
            value += fine
            count += 1
        }
    }

    private func drawVertical(in context: inout GraphicsContext, size: CGSize) {
        let metrics = manager.rulerMetrics
        let scale = metrics.scale
        let topY = size.height - metrics.topLeft.y
        let start = metrics.pageBounds.maxY - (0 - topY) / scale
        let end = metrics.pageBounds.maxY - (size.height - topY) / scale
        let low = min(start, end), high = max(start, end)
        let major = rulerInterval(for: 78 / scale)
        let fine = major / 10
        var value = floor(low / fine) * fine
        var count = 0
        while value <= high + fine && count < 2500 {
            let y = topY + (metrics.pageBounds.maxY - value) * scale
            if y >= 0 && y <= size.height {
                let isMajor = abs(value / major - (value / major).rounded()) < 0.0001
                let isMedium = !isMajor && abs(value / (major / 2) - (value / (major / 2)).rounded()) < 0.0001
                let length: CGFloat = isMajor ? 15 : (isMedium ? 10 : 5)
                var tick = Path(); tick.move(to: CGPoint(x: size.width, y: y)); tick.addLine(to: CGPoint(x: size.width - length, y: y))
                context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.8 : 0.42)), lineWidth: 1)
                if isMajor {
                    var labelContext = context
                    labelContext.translateBy(x: 8, y: y - 3)
                    labelContext.rotate(by: .degrees(90))
                    let label = Text(String(format: "%.0f", value)).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.82))
                    labelContext.draw(label, at: .zero, anchor: .center)
                }
            }
            value += fine
            count += 1
        }
    }

    private func drawEdge(in context: inout GraphicsContext, size: CGSize) {
        var edge = Path()
        if axis == .horizontal { edge.move(to: CGPoint(x: 0, y: size.height - 0.5)); edge.addLine(to: CGPoint(x: size.width, y: size.height - 0.5)) }
        else { edge.move(to: CGPoint(x: size.width - 0.5, y: 0)); edge.addLine(to: CGPoint(x: size.width - 0.5, y: size.height)) }
        context.stroke(edge, with: .color(Palette.separator), lineWidth: 1)
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
        view.pageShadowsEnabled = true
        view.autoScales = false
        disableLiveTextIfAvailable(on: view)
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ view: PDFViewerView, context: Context) {
        context.coordinator.manager = manager
        context.coordinator.update(view)
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
        var scaleObserver: NSKeyValueObservation?
        var lastSearchText = ""

        init(manager: DocumentManager) { self.manager = manager }
        func attach(_ view: PDFViewerView) {
            self.view = view
            view.delegate = self
            view.onViewportChange = { [weak self, weak view] in
                guard let self, let view else { return }
                self.scheduleViewportSync(for: view)
            }
            scaleObserver = view.observe(\.scaleFactor, options: [.new]) { [weak self] pdfView, _ in
                Task { @MainActor in
                    self?.scheduleViewportSync(for: pdfView)
                }
            }
        }

        func update(_ view: PDFViewerView) {
            if activeDocumentID != manager.selected?.id {
                activeDocumentID = manager.selected?.id
                lastSearchText = ""
                view.document = manager.selected?.document
                if let item = manager.selected {
                    view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, item.zoom))
                    if let page = item.document.page(at: item.pageIndex) { view.go(to: page) }
                }
            }
            view.displayMode = manager.layout.pdfMode
            view.displaysAsBook = manager.layout == .spread
            view.activeTool = manager.tool
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
            case .page(let index):
                if let page = item.document.page(at: index) { view.go(to: page) }
            case .highlight: addHighlight(on: view)
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
            Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self, let view, let item = self.manager.selected,
                      view.document === item.document else { return }
                self.syncPage()
                self.syncMetrics(for: view)
                if item.zoom != view.scaleFactor { item.zoom = view.scaleFactor }
            }
        }

        private func itemSearch(_ query: String, in document: PDFDocument?) -> PDFSelection? {
            document?.findString(query, withOptions: [.caseInsensitive]).first
        }

        private func addHighlight(on view: PDFViewerView) {
            guard let selection = view.currentSelection, !(selection.string ?? "").isEmpty else {
                manager.say("Select PDF text first, then choose Highlight Text.", "Сначала выделите текст в PDF, затем нажмите «Подсветить текст».")
                return
            }
            for page in selection.pages {
                let bounds = selection.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.48)
                page.addAnnotation(annotation)
            }
            view.setCurrentSelection(nil, animate: false)
        }

        private func syncPage() {
            guard let view, let item = manager.selected, let page = view.currentPage else { return }
            let index = max(0, item.document.index(for: page))
            if item.pageIndex != index { item.pageIndex = index }
            let pageValue = String(index + 1)
            if manager.pageText != pageValue { manager.pageText = pageValue }
        }

        private func syncMetrics(for view: PDFViewerView) {
            guard let page = view.currentPage else {
                let invalid = RulerMetrics(valid: false)
                if manager.rulerMetrics != invalid { manager.rulerMetrics = invalid }
                return
            }
            let box = page.bounds(for: view.displayBox)
            let topLeft = view.convert(CGPoint(x: box.minX, y: box.maxY), from: page)
            let metrics = RulerMetrics(scale: view.scaleFactor, pageBounds: box, topLeft: topLeft, valid: box.width > 0 && box.height > 0)
            if manager.rulerMetrics != metrics { manager.rulerMetrics = metrics }
        }

        func pdfViewPageChanged(_ notification: Notification) {
            if let view { scheduleViewportSync(for: view) }
        }
    }
}

@MainActor
private final class PDFViewerView: PDFView {
    var activeTool: PDFTool = .hand { didSet { window?.invalidateCursorRects(for: self) } }
    var onViewportChange: (() -> Void)?
    private var previousDragPoint: NSPoint?

    override func resetCursorRects() {
        super.resetCursorRects()
        if activeTool == .hand { addCursorRect(visibleRect, cursor: .openHand) }
        if activeTool == .textSelection { addCursorRect(visibleRect, cursor: .iBeam) }
    }

    override func mouseDown(with event: NSEvent) {
        guard activeTool == .hand else { super.mouseDown(with: event); return }
        previousDragPoint = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeTool == .hand, let previousDragPoint, let clipView = enclosingScrollView?.contentView else {
            super.mouseDragged(with: event); return
        }
        let current = event.locationInWindow
        let delta = NSPoint(x: current.x - previousDragPoint.x, y: current.y - previousDragPoint.y)
        var origin = clipView.bounds.origin
        origin.x -= delta.x
        origin.y -= delta.y
        clipView.scroll(to: origin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
        self.previousDragPoint = current
    }

    override func mouseUp(with event: NSEvent) {
        guard activeTool == .hand else { super.mouseUp(with: event); return }
        previousDragPoint = nil
        NSCursor.pop()
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        Task { @MainActor [weak self] in self?.onViewportChange?() }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        Task { @MainActor [weak self] in self?.onViewportChange?() }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        onViewportChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard onViewportChange != nil else { return }
        Task { @MainActor [weak self] in self?.onViewportChange?() }
    }
}
