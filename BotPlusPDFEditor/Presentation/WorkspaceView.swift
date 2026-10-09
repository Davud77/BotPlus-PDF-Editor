import SwiftUI

struct WorkspaceView: View {
    @StateObject private var model = PDFWorkspaceModel()

    var body: some View {
        VStack(spacing: 0) {
            RibbonView(model: model)
            documentTabs
            HStack(spacing: 0) {
                if model.leftPanelVisible { LeftSidebarView(model: model) }
                PDFCanvas(model: model).background(Color(nsColor: .underPageBackgroundColor))
                if model.rightPanelVisible { PropertiesInspector(model: model) }
            }
            StatusBarView(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenDocument)) { _ in model.openDocument() }
        .alert("BotPlus PDF Editor", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var documentTabs: some View {
        HStack(spacing: 0) {
            if model.documents.isEmpty {
                Text("No document open").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 32)
            } else {
                ForEach(model.documents) { document in
                    HStack(spacing: 8) {
                        Button { model.selectDocument(document.id) } label: {
                            HStack(spacing: 6) { Image(systemName: "doc.text"); Text(document.title).lineLimit(1); if document.isDirty { Circle().fill(.orange).frame(width: 5, height: 5) } }
                                .font(.system(size: 11, weight: model.selectedDocumentID == document.id ? .medium : .regular))
                                .foregroundStyle(model.selectedDocumentID == document.id ? Color.primary : Color.secondary)
                                .frame(maxWidth: 180).padding(.horizontal, 10).frame(height: 31)
                                .background(model.selectedDocumentID == document.id ? Color(nsColor: .controlBackgroundColor) : .clear)
                        }.buttonStyle(.plain)
                        Button { model.closeDocument(document.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary) }.buttonStyle(.plain).padding(.trailing, 8)
                    }.overlay(alignment: .trailing) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 17) }
                }
            }
            Button { model.openDocument() } label: { Image(systemName: "plus").font(.system(size: 11)).frame(width: 28, height: 30) }.buttonStyle(.plain).help("Open another PDF")
            Spacer()
            if let calibration = model.measurement.calibration { Text(calibration.label).font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 12) }
        }.background(Color(nsColor: .windowBackgroundColor)).overlay(alignment: .bottom) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
    }
}
