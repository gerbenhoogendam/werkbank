import Foundation
import Observation
import SwiftUI

/// Wat Claude moet onthouden: onze vaste werkwijze, standaardroutes en producten. Eén punt per regel in
/// iCloud Drive/Werkbank/Claude-geheugen.md (ook zelf te bewerken); gaat mee in elke vraag aan Claude.
@MainActor
@Observable
final class ClaudeMemory {
    static let shared = ClaudeMemory()
    static let fileName = "Claude-geheugen.md"

    private(set) var items: [String] = []
    @ObservationIgnored private var loaded = false
    /// Schrijfacties die nog lopen: dan niet inlezen (anders komt een net toegevoegd punt even terug als oud bestand).
    @ObservationIgnored private var writing = 0

    private var url: URL { WerkbankFolder.url.appendingPathComponent(Self.fileName) }

    /// Opnieuw inlezen (bij het starten, bij terugkomen in de app en elke minuut: een andere Mac kan iets toevoegen).
    func reload() async {
        await WerkbankFolder.prepare()
        guard writing == 0 else { return }
        let url = self.url
        let localURL = WerkbankFolder.local.appendingPathComponent(Self.fileName)
        let usesICloud = WerkbankFolder.iCloud != nil
        let (current, local) = await Task.detached(priority: .utility) { () -> ([String]?, [String]) in
            let current = CloudFile.read(url).flatMap(CloudFile.text).map(ClaudeMemory.parse)
            // Van vóór iCloud Drive lokaal bewaard: gaat mee naar iCloud.
            var local: [String] = []
            if usesICloud, let text = try? String(contentsOf: localURL, encoding: .utf8) { local = ClaudeMemory.parse(text) }
            return (current, local)
        }.value
        guard writing == 0 else { return }

        var merged = current ?? items
        if !loaded {
            // Toegevoegd voordat het bestand voor het eerst gelezen was.
            for item in items where !merged.contains(item) { merged.append(item) }
        }
        for item in local where !merged.contains(item) { merged.append(item) }
        let needsSave = merged != (current ?? [])
        loaded = true
        if merged != items { items = merged }
        if needsSave { save() }
        if !local.isEmpty { try? FileManager.default.removeItem(at: localURL) }
    }

    func add(_ text: String) {
        let item = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !item.isEmpty, !items.contains(item) else { return }
        items.append(item)
        save()
    }

    func remove(_ item: String) {
        items.removeAll { $0 == item }
        save()
    }

    func fileURL() -> URL { url }

    private func save() {
        guard loaded else { return }   // pas na het eerste inlezen, anders gaat het bestand verloren
        let data = Data(Self.render(items).utf8)
        let url = self.url
        writing += 1
        Task { [weak self] in
            _ = await Task.detached(priority: .utility) { CloudFile.write(data, to: url) }.value
            self?.writing -= 1
        }
    }

    /// Het stuk dat in de vraag aan Claude komt; leeg als er niets onthouden is.
    var promptSection: String {
        guard !items.isEmpty else { return "" }
        return """
        Onze vaste werkwijze, standaarden en voorkeuren. Volg deze altijd. Raad geen andere producten, routes of \
        oplossingen aan als hier een standaard voor staat, en noem geen alternatieven die wij niet gebruiken:
        """ + "\n" + items.map { "- \($0)" }.joined(separator: "\n")
    }

    nonisolated static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var item = line.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty, !item.hasPrefix("#") else { return nil }
            for bullet in ["- ", "* ", "• "] where item.hasPrefix(bullet) {
                item = String(item.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
            }
            return item.isEmpty ? nil : item
        }
    }

    nonisolated static func render(_ items: [String]) -> String {
        "# Claude-geheugen\n\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
}

/// Veld onder een analyse: iets vastleggen dat Claude voortaan moet weten (een standaardroute, ons vaste product).
struct MemoryInputRow: View {
    @State private var text = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Geheugen")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit(save)
            Button("Onthoud", action: save)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func save() {
        let item = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else { return }
        ClaudeMemory.shared.add(item)
        text = ""
        AppState.shared.announce("Onthouden voor Claude")
    }
}
