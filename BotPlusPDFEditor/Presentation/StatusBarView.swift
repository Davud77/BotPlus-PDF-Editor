import SwiftUI

struct StatusBarView: View {
    @ObservedObject var model: PDFWorkspaceModel
    var body: some View {
        HStack(spacing: 10) {
            Button { model.navigatePage(-1) } label: { Image(systemName: "chevron.left") }.disabled(model.pageCount == 0)
            TextField("Page", text: $model.pageNumberInput, onCommit: model.goToEnteredPage)
                .textFieldStyle(.roundedBorder).frame(width: 44).multilineTextAlignment(.center).disabled(model.pageCount == 0)
            Text("/ \(max(model.pageCount, 1))").font(.system(size: 11)).foregroundStyle(.secondary)
            Button { model.navigatePage(1) } label: { Image(systemName: "chevron.right") }.disabled(model.pageCount == 0)
            Divider().frame(height: 16)
            Button { } label: { Image(systemName: "rotate.left") }.help("Rotate page left")
            Button { } label: { Image(systemName: "rotate.right") }.help("Rotate page right")
            Spacer()
            if let point = model.measurement.cursorPDFPoint {
                Text(String(format: "X %.1f pt  Y %.1f pt", point.x, point.y)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                if let calibration = model.measurement.calibration {
                    Text(String(format: "(%.2f, %.2f) mm", point.x * calibration.millimetersPerPDFPoint, point.y * calibration.millimetersPerPDFPoint)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Divider().frame(height: 16)
            Menu { ForEach([50.0, 75, 100, 125, 150, 200, 300, 400], id: \.self) { value in Button("\(Int(value))%") { model.setZoom(value) } } } label: { Text("\(Int(model.zoomPercent))%").font(.system(size: 11, design: .monospaced)).frame(width: 48, alignment: .trailing) }
            Slider(value: Binding(get: { model.zoomPercent }, set: { model.setZoom($0) }), in: 25...400).frame(width: 110)
        }.buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 30).background(Color(nsColor: .windowBackgroundColor))
    }
}
