import Foundation
import Observation
import WerkbankCore

/// De klantenlijst: alle .csv-bestanden in iCloud Drive/Werkbank. Wordt opnieuw gelezen als een bestand is gewijzigd
/// (bijvoorbeeld aangevuld op een andere Mac).
@MainActor
@Observable
final class ClientDirectory {
    static let shared = ClientDirectory()

    private(set) var records: [ClientRecord] = []
    @ObservationIgnored private var stamps: [String: Date] = [:]
    @ObservationIgnored private var isRefreshing = false

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await WerkbankFolder.prepare()
        let folder = WerkbankFolder.url
        let known = stamps
        let result = await Task.detached(priority: .utility) { () -> (records: [ClientRecord], stamps: [String: Date])? in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            else { return nil }
            var csvs: [URL] = []
            for file in files {
                let name = file.lastPathComponent
                if file.pathExtension.lowercased() == "csv" {
                    csvs.append(file)
                } else if name.hasPrefix("."), name.lowercased().hasSuffix(".csv.icloud") {
                    // Staat nog alleen in iCloud: ophalen, de volgende keer is hij er.
                    let real = folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                    try? fm.startDownloadingUbiquitousItem(at: real)
                }
            }
            var stamps: [String: Date] = [:]
            for file in csvs { stamps[file.lastPathComponent] = CloudFile.modificationDate(file) ?? .distantPast }
            guard stamps != known else { return nil }   // niets veranderd

            var seen = Set<String>()
            var records: [ClientRecord] = []
            for file in csvs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let data = CloudFile.read(file), let text = CloudFile.text(data) else { continue }
                for record in ClientList.parseCSV(text) where seen.insert(record.name.lowercased()).inserted {
                    records.append(record)
                }
            }
            return (records, stamps)
        }.value
        guard let result else { return }
        records = result.records
        stamps = result.stamps
    }

    /// Treffers uit de lijst, aangevuld met klantnamen die al in Werkbank voorkomen.
    func suggestions(for query: String, known: [String], limit: Int = 6) -> [ClientRecord] {
        var all = records
        let listed = Set(records.map { $0.name.lowercased() })
        for name in known where !listed.contains(name.lowercased()) {
            all.append(ClientRecord(name: name))
        }
        return ClientList.search(query, in: all, limit: limit)
    }
}
