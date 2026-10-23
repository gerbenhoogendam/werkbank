import Foundation

/// Een klant uit de klantenlijst (.csv): de naam en de overige kolommen (bijv. debiteurnummer, plaats, domein).
public struct ClientRecord: Equatable, Hashable {
    public var name: String
    public var details: [String]

    public init(name: String, details: [String] = []) {
        self.name = name
        self.details = details
    }
}

/// Klantenlijst uit een .csv (zoals Excel of Numbers hem bewaart) en zoeken daarin.
public enum ClientList {
    /// Kolomkoppen die de naam van de klant aanwijzen.
    private static let nameHeaders: Set<String> = [
        "naam", "klant", "klantnaam", "bedrijf", "bedrijfsnaam", "organisatie", "relatie", "relatienaam",
        "name", "company", "client", "customer",
    ]

    /// Scheidingsteken (`;`, `,` of tab) wordt uit de eerste regel afgeleid. Heeft de eerste regel een kolomkop als
    /// "Naam" of "Klant", dan is dat de kop en die kolom de naam; anders is de eerste kolom de naam.
    public static func parseCSV(_ text: String) -> [ClientRecord] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let candidates: [Character] = [";", ",", "\t"]
        let separator = candidates.max { count($0, in: firstLine) < count($1, in: firstLine) } ?? ","
        var table = rows(of: text, separator: count(separator, in: firstLine) > 0 ? separator : ",")
        guard !table.isEmpty else { return [] }

        var nameColumn = 0
        let header = table[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if let index = header.firstIndex(where: nameHeaders.contains) {
            nameColumn = index
            table.removeFirst()
        }

        var seen = Set<String>()
        var records: [ClientRecord] = []
        for row in table {
            let cells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard nameColumn < cells.count else { continue }
            let name = cells[nameColumn]
            guard !name.isEmpty, seen.insert(fold(name)).inserted else { continue }
            let details = cells.enumerated().filter { $0.offset != nameColumn && !$0.element.isEmpty }.map(\.element)
            records.append(ClientRecord(name: name, details: details))
        }
        return records
    }

    /// Beste treffers eerst: naam gelijk, naam begint ermee, een woord in de naam begint ermee, naam bevat het,
    /// een andere kolom bevat het. Meerdere woorden: elk woord moet ergens voorkomen. Hoofdletters en accenten tellen niet.
    public static func search(_ query: String, in records: [ClientRecord], limit: Int = 8) -> [ClientRecord] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }
        let tokens = q.split(separator: " ").map(String.init)

        var scored: [(score: Int, record: ClientRecord)] = []
        for record in records {
            let name = fold(record.name)
            let all = ([name] + record.details.map(fold)).joined(separator: " ")
            let score: Int
            if name == q {
                score = 0
            } else if name.hasPrefix(q) {
                score = 1
            } else if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
                score = 2
            } else if name.contains(q) {
                score = 3
            } else if tokens.allSatisfy({ all.contains($0) }) {
                score = 4
            } else {
                continue
            }
            scored.append((score, record))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.record.name.localizedCaseInsensitiveCompare($1.record.name) == .orderedAscending }
            .prefix(limit)
            .map(\.record)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
    }

    private static func count(_ character: Character, in line: String) -> Int {
        var inQuotes = false
        var total = 0
        for c in line {
            if c == "\"" { inQuotes.toggle() } else if c == character, !inQuotes { total += 1 }
        }
        return total
    }

    /// Regels en cellen, met aanhalingstekens ("" binnen een cel is één ") en regeleinden binnen een cel.
    private static func rows(of text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { cell.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == separator {
                row.append(cell)
                cell = ""
            } else if c.isNewline {
                row.append(cell)
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
                cell = ""
            } else {
                cell.append(c)
            }
        }
        row.append(cell)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows
    }
}
