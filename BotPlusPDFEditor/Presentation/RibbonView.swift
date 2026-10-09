import SwiftUI

struct RibbonView: View {
    @ObservedObject var model: PDFWorkspaceModel
    private let tabs = RibbonTab.allCases

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.blue).font(.title3)
                Button { model.openDocument() } label: { Label("Open", systemImage: "folder") }.help("Open PDF")
                Button { model.savePDF() } label: { Label("Save", systemImage: "square.and.arrow.down") }.disabled(model.selectedDocument == nil)
                Button { model.measurement.undo() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo measurement")
                Button { } label: { Image(systemName: "arrow.uturn.forward") }.disabled(true).help("Redo")
                Button { model.printDocument() } label: { Image(systemName: "printer") }.disabled(model.selectedDocument == nil).help("Print")
                Spacer()
                Text("BLUEPRINT PDF").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Button { model.leftPanelVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle navigation sidebar")
                Button { model.rightPanelVisible.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle properties")
            }
            .buttonStyle(.borderless).padding(.horizontal, 14).frame(height: 38)
            HStack(spacing: 18) {
                ForEach(tabs) { tab in
                    Button { model.selectedTab = tab } label: {
                        Text(tab.rawValue).font(.system(size: 13, weight: model.selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(model.selectedTab == tab ? Color.accentColor : Color.primary)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { if model.selectedTab == tab { Rectangle().fill(Color.accentColor).frame(height: 2) } }
                    }.buttonStyle(.plain)
                }
                Spacer()
                if model.selectedTab == .measurement { calibrationControls }
            }.padding(.horizontal, 16).frame(height: 37)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            toolContent.padding(.horizontal, 14).frame(height: model.selectedTab == .measurement ? 66 : 62)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var toolContent: some View {
        HStack(spacing: 8) {
            switch model.selectedTab {
            case .home: toolButtons([.hand, .textSelection, .snapshot])
            case .view:
                Button { model.twoPageSpread.toggle() } label: { Label(model.twoPageSpread ? "Continuous" : "Two Page", systemImage: "rectangle.split.2x1") }
                Menu("Zoom") { ForEach([50.0, 75, 100, 125, 150, 200], id: \.self) { value in Button("\(Int(value))%") { model.setZoom(value) } } }
                Spacer()
            case .comment: toolButtons([.highlight, .underline, .freehand])
            case .measurement: toolButtons([.distance, .perimeter, .area])
            case .pages:
                Button { model.navigatePage(-1) } label: { Label("Previous Page", systemImage: "chevron.left") }
                Button { model.navigatePage(1) } label: { Label("Next Page", systemImage: "chevron.right") }
                Spacer()
            case .tools:
                Button { model.savePDFAs() } label: { Label("Save As…", systemImage: "square.and.arrow.up") }
                Text("PDFKit document tools").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func toolButtons(_ tools: [EditorTool]) -> some View {
        HStack(spacing: 6) {
            ForEach(tools) { tool in
                Button { model.measurement.setTool(tool) } label: {
                    VStack(spacing: 3) { Image(systemName: tool.symbol).font(.system(size: 17)); Text(tool.rawValue).font(.system(size: 10)) }
                        .frame(width: 64, height: 54)
                        .background(model.measurement.activeTool == tool ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help("Select \(tool.rawValue)")
            }
            Spacer()
        }
    }

    private var calibrationControls: some View {
        HStack(spacing: 7) {
            Text("Scale").font(.caption).foregroundStyle(.secondary)
            TextField("Drawing mm", text: Binding(get: { model.measurement.calibrationDrawingLength }, set: { model.measurement.calibrationDrawingLength = $0 })).frame(width: 76)
            Text("mm =").font(.caption)
            TextField("Real mm", text: Binding(get: { model.measurement.calibrationRealLength }, set: { model.measurement.calibrationRealLength = $0 })).frame(width: 76)
            Text("mm real").font(.caption)
            TextField("Label", text: Binding(get: { model.measurement.calibrationLabel }, set: { model.measurement.calibrationLabel = $0 })).frame(width: 110)
            Button("Set") { model.measurement.configureCalibration() }.buttonStyle(.borderedProminent).controlSize(.small)
        }.textFieldStyle(.roundedBorder).font(.caption)
    }
}
