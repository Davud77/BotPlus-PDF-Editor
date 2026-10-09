import Foundation

struct MeasurementRepository {
    func sidecarURL(for pdfURL: URL) -> URL {
        pdfURL.deletingPathExtension().appendingPathExtension("blueprint-measurements.json")
    }

    func load(for pdfURL: URL) -> MeasurementDocument {
        let url = sidecarURL(for: pdfURL)
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(MeasurementDocument.self, from: data) else { return MeasurementDocument() }
        return document
    }

    func save(_ document: MeasurementDocument, for pdfURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: sidecarURL(for: pdfURL), options: .atomic)
    }
}
