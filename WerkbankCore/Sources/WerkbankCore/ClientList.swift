import Foundation

/// Een klant uit de klantenlijst: de naam, de overige kolommen (bijv. debiteurnummer, plaats) en de eigen domeinen.
public struct ClientRecord: Equatable, Hashable {
    public var name: String
    public var details: [String]
    /// Eigen domeinen (uit een kolom Domein of Website, of uit de e-mailadressen; freemail telt niet), voor het logo en
    /// het herkennen van de klant bij een mail.
    public var domains: [String]
    /// "failliet", "geen klant meer" of "niet gebruiken" als dat in de naam stond (dan staat het er niet meer in).
    public var status: String?

    public init(name: String, details: [String] = [], domains: [String] = [], status: String? = nil) {
        self.name = name
        self.details = details
        self.domains = domains
        self.status = status
    }

    public var isInactive: Bool { status != nil }
}

/// Klantenlijst uit een .csv (zoals Excel of Numbers hem bewaart) en zoeken daarin.
public enum ClientList {
    /// Kolomkoppen die de naam van de klant aanwijzen.
    private static let nameHeaders: Set<String> = [
        "naam", "klant", "klantnaam", "bedrijf", "bedrijfsnaam", "organisatie", "relatie", "relatienaam",
        "name", "company", "client", "customer",
    ]
    /// Kolomkoppen met een domein, website of e-mailadres (van een adres telt alleen het domein).
    private static let domainHeaders: Set<String> = [
        "domein", "domeinnaam", "domain", "website", "web", "url", "maildomein", "e-maildomein",
        "e-mail", "e mail", "email", "e-mailadres", "e mailadres", "emailadres", "mail", "mailadres", "e-mail adres",
    ]
    /// Markeringen in de naam voor klanten die niet meer actief zijn (ook de spelling "falliet").
    private static let statusPrefixes = ["geen klant meer", "failliet", "falliet"]
    private static let statusPhrases = ["niet gebruiken", "failliet", "falliet", "faillissement"]

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
        var domainColumns: [Int] = []
        let header = table[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if let index = header.firstIndex(where: nameHeaders.contains) {
            nameColumn = index
            domainColumns = header.indices.filter { domainHeaders.contains(header[$0]) }
            table.removeFirst()
        }
        // Zonder herkenbare kop: de kolommen waarin de meeste cellen een e-mailadres zijn.
        if domainColumns.isEmpty {
            let width = table.map(\.count).max() ?? 0
            domainColumns = (0..<width).filter { column in
                column != nameColumn && {
                    let filled = table.compactMap { column < $0.count ? $0[column] : nil }.filter { !$0.isEmpty }
                    return !filled.isEmpty && filled.filter { $0.contains("@") }.count * 2 > filled.count
                }()
            }
        }

        // Dezelfde klant op meer regels (bijv. twee adressen): één klant met alle domeinen.
        var index: [String: Int] = [:]
        var records: [ClientRecord] = []
        for row in table {
            let cells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard nameColumn < cells.count else { continue }
            let (name, status) = splitStatus(cells[nameColumn])
            guard !name.isEmpty else { continue }
            // E-mailadressen gaan er niet in: daarvan blijft alleen het eigen domein over.
            let details = cells.enumerated()
                .filter { $0.offset != nameColumn && !domainColumns.contains($0.offset) && !$0.element.isEmpty }
                .map(\.element)
            let domains = domainColumns.flatMap { $0 < cells.count ? customDomains(in: cells[$0]) : [] }
            let key = fold(name)
            if let existing = index[key] {
                for domain in domains where !records[existing].domains.contains(domain) {
                    records[existing].domains.append(domain)
                }
                if status != nil { records[existing].status = status }
            } else {
                index[key] = records.count
                records.append(ClientRecord(name: name, details: details, domains: unique(domains), status: status))
            }
        }
        return records
    }

    /// Eigen domeinen in een cel met één of meer adressen of websites ("a@bedrijf.nl; b@mail.bedrijf.nl") →
    /// ["bedrijf.nl"]. Freemail (gmail.com, hotmail.com, providers) valt weg.
    public static func customDomains(in cell: String) -> [String] {
        let parts = cell.split(whereSeparator: { $0 == ";" || $0 == "," || $0.isWhitespace })
        var domains: [String] = []
        for part in parts {
            guard let domain = normalizedDomain(String(part)).map(ClientNaming.registrableDomain(of:)),
                  !ClientNaming.freemailDomains.contains(domain), !domains.contains(domain) else { continue }
            domains.append(domain)
        }
        return domains
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// "FAILLIET Romex Benelux" → ("Romex Benelux", "failliet"); "Bakkerij Jansen (falliet)" → ("Bakkerij Jansen",
    /// "falliet").
    static func splitStatus(_ raw: String) -> (name: String, status: String?) {
        var name = raw
        var status: String?
        for prefix in statusPrefixes where name.lowercased().hasPrefix(prefix + " ") {
            name = String(name.dropFirst(prefix.count + 1))
            status = prefix
        }
        for phrase in statusPhrases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
            if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                name.removeSubrange(range)
                status = phrase
            }
        }
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()[]-–,:"))
        let cleaned = name.replacingOccurrences(of: "()", with: "")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: edges)
        return (cleaned, status)
    }

    /// "https://www.Bedrijf.nl/contact" → "bedrijf.nl".
    static func normalizedDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) { value.removeFirst(scheme.count) }
        if value.hasPrefix("www.") { value.removeFirst(4) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value.contains(".") && !value.contains(" ") ? value : nil
    }

    /// Domein → klantnaam, voor het herkennen van de klant bij een mail. Freemail (gmail.com en dergelijke) en
    /// domeinen die bij verschillende actieve klanten horen, vallen weg.
    public static func domainMap(_ records: [ClientRecord]) -> [String: String] {
        var byDomain: [String: [ClientRecord]] = [:]
        for record in records {
            for domain in record.domains where !ClientNaming.freemailDomains.contains(domain) {
                byDomain[domain, default: []].append(record)
            }
        }
        var map: [String: String] = [:]
        for (domain, owners) in byDomain {
            let active = owners.filter { !$0.isInactive }
            let candidates = Set((active.isEmpty ? owners : active).map(\.name))
            if candidates.count == 1, let name = candidates.first { map[domain] = name }
        }
        return map
    }

    /// Beste treffers eerst: naam gelijk, naam begint ermee, een woord in de naam begint ermee, naam bevat het,
    /// een andere kolom bevat het, en daarna treffers met een tikfout (vanaf 4 tekens één fout, vanaf 8 twee): eerst
    /// een verkeerde letter in de naam ("ecom" → Willegom), dan een letter te veel of te weinig, dan in een andere kolom.
    /// Meerdere woorden: elk woord moet ergens voorkomen. Hoofdletters, accenten, apostrofs en punten tellen niet;
    /// klanten die niet meer actief zijn komen achteraan.
    public static func search(_ query: String, in records: [ClientRecord], limit: Int = 8) -> [ClientRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = fold(trimmed)
        guard !q.isEmpty else { return [] }
        let tokens = q.split(separator: " ").map(String.init)
        // In andere kolommen (domeinen) blijven punten staan: "corporate.com" mag niet op "ecom" treffen.
        let detailTokens = fold(trimmed, keepingDots: true).split(separator: " ").map(String.init)

        var scored: [(score: Int, record: ClientRecord)] = []
        for record in records {
            let name = fold(record.name)
            let all = ([record.name] + record.details + record.domains).map { fold($0, keepingDots: true) }
                .joined(separator: " ")
            // Tikfouten per woord, zodat een spatie niet als letter meetelt.
            let nameWords = words(name)
            let allWords = words(all)
            var score: Int
            if name == q {
                score = 0
            } else if name.hasPrefix(q) {
                score = 1
            } else if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
                score = 2
            } else if name.contains(q) {
                score = 3
            } else if detailTokens.allSatisfy({ all.contains($0) }) {
                score = 4
            } else if tokens.allSatisfy({ token in
                name.contains(token) || nameWords.contains { fuzzyContains($0, token, substitutionsOnly: true) }
            }) {
                score = 5
            } else if tokens.allSatisfy({ token in name.contains(token) || nameWords.contains { fuzzyContains($0, token) } }) {
                score = 6
            } else if detailTokens.allSatisfy({ token in all.contains(token) || allWords.contains { fuzzyContains($0, token) } }) {
                score = 7
            } else {
                continue
            }
            if record.isInactive { score += 10 }
            scored.append((score, record))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.record.name.localizedCaseInsensitiveCompare($1.record.name) == .orderedAscending }
            .prefix(limit)
            .map(\.record)
    }

    /// Sleutel om dezelfde klant te herkennen: zonder hoofdletters, accenten, apostrofs en punten.
    public static func key(_ name: String) -> String {
        fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Kleine letters, zonder accenten, apostrofs en (in namen) punten ("Paula’s B.V." → "paulas bv").
    static func fold(_ text: String, keepingDots: Bool = false) -> String {
        let removed = keepingDots ? "'’`´" : "'’`´."
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
            .filter { !removed.contains($0) }
    }

    /// Komt `pattern` met hooguit één (vanaf 8 tekens: twee) tikfouten ergens in `text` voor?
    /// `substitutionsOnly`: alleen verkeerde letters, geen letters te veel of te weinig.
    static func fuzzyContains(_ text: String, _ pattern: String, substitutionsOnly: Bool = false) -> Bool {
        let p = Array(pattern), t = Array(text)
        guard p.count >= 4 else { return false }
        let allowed = p.count >= 8 ? 2 : 1
        if substitutionsOnly {
            guard t.count >= p.count else { return false }
            for start in 0...(t.count - p.count) {
                var mismatches = 0
                for i in 0..<p.count where t[start + i] != p[i] {
                    mismatches += 1
                    if mismatches > allowed { break }
                }
                if mismatches <= allowed { return true }
            }
            return false
        }
        // Afstand van het patroon tot het best passende stuk tekst (begin en eind vrij).
        var previous = Array(0...p.count)
        var best = previous[p.count]
        for character in t {
            var current = [0] + Array(repeating: 0, count: p.count)
            for i in 1...p.count {
                current[i] = min(previous[i] + 1, current[i - 1] + 1, previous[i - 1] + (p[i - 1] == character ? 0 : 1))
            }
            best = min(best, current[p.count])
            previous = current
        }
        return best <= allowed
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
