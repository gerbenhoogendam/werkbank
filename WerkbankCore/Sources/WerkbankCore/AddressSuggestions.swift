import Foundation

// Adressen aanvullen bij het opstellen: uit verzonden en ontvangen mail, Contacten en de klantenlijst. Typ de eerste
// letters van een naam, adres of domein, of de naam van een klant voor de mensen van die klant.

/// Een adres om aan te vullen.
public struct AddressCandidate: Equatable, Hashable {
    public var name: String?
    /// In kleine letters.
    public var address: String
    /// De klant bij het domein van het adres.
    public var client: String?
    /// Hoe vaak en hoe recent er mail met dit adres was; hoger komt eerst.
    public var score: Double

    public init(name: String? = nil, address: String, client: String? = nil, score: Double = 0) {
        self.name = name
        self.address = address.lowercased()
        self.client = client
        self.score = score
    }

    public var mailAddress: MailAddress { MailAddress(name: name, address: address) }
}

public enum AddressSuggestions {
    /// Het adres waaraan nu getypt wordt: wat na de laatste komma of puntkomma staat (niet binnen aanhalingstekens).
    public static func currentToken(in text: String) -> String {
        String(text[tokenStart(in: text)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Zet het gekozen adres op de plaats van wat er getypt werd, met ", " erachter voor het volgende adres.
    public static func replacingCurrentToken(in text: String, with address: MailAddress) -> String {
        let head = String(text[..<tokenStart(in: text)]).trimmingCharacters(in: .whitespaces)
        return (head.isEmpty ? "" : head + " ") + fieldString(address) + ", "
    }

    /// Het adres zoals het in het veld komt; een naam met een komma of puntkomma tussen aanhalingstekens.
    public static func fieldString(_ address: MailAddress) -> String {
        guard var name = address.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return address.address }
        if name.rangeOfCharacter(from: CharacterSet(charactersIn: ",;\"<>")) != nil {
            name = "\"" + name.replacingOccurrences(of: "\"", with: "") + "\""
        }
        return "\(name) <\(address.address)>"
    }

    private static func tokenStart(in text: String) -> String.Index {
        var inQuotes = false
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes, character == "," || character == ";" {
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }
        return start
    }

    /// Adressen die bij `term` passen: eerst waar naam of adres mee begint, dan een woord in de naam of het adres,
    /// dan de klant of het domein. Binnen elke groep wie je het meest mailt eerst. Adressen in `excluding` (al
    /// ingevuld) vallen weg.
    public static func search(_ term: String, in candidates: [AddressCandidate], excluding: Set<String> = [],
                              limit: Int = 6) -> [AddressCandidate] {
        let query = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        func words(_ text: String) -> [Substring] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }
        }
        func rank(_ candidate: AddressCandidate) -> Int? {
            let name = (candidate.name ?? "").lowercased()
            let parts = candidate.address.split(separator: "@", maxSplits: 1)
            let local = parts.first.map(String.init) ?? candidate.address
            let domain = parts.count > 1 ? String(parts[1]) : ""
            if candidate.address.hasPrefix(query) || (!name.isEmpty && name.hasPrefix(query)) { return 0 }
            if words(name).contains(where: { $0.hasPrefix(query) }) || words(local).contains(where: { $0.hasPrefix(query) }) {
                return 1
            }
            if let client = candidate.client?.lowercased(),
               client.hasPrefix(query) || words(client).contains(where: { $0.hasPrefix(query) }) {
                return 2
            }
            if domain.hasPrefix(query) { return 2 }
            return nil
        }
        var seen = Set<String>()
        return candidates
            .compactMap { candidate -> (AddressCandidate, Int)? in
                guard !excluding.contains(candidate.address), seen.insert(candidate.address).inserted else { return nil }
                return rank(candidate).map { (candidate, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.score != rhs.0.score { return lhs.0.score > rhs.0.score }
                return lhs.0.address < rhs.0.address
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Hoe vaak er mail met elk adres was. Verzonden mail telt drie keer (daar kies je zelf de ontvangers), recente
    /// mail zwaarder (de helft per 90 dagen). Eigen adressen en afzenders die een machine zijn tellen niet.
    public static func scores(records: [MailActivityRecord], ownAddresses: Set<String>, now: Date) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in records {
            let days = max(0, now.timeIntervalSince(record.date)) / 86_400
            let weight = (record.isSent ? 3.0 : 1.0) * pow(0.5, days / 90)
            for address in Set(record.addresses) where !ownAddresses.contains(address) && !MailKind.isAutomatedSender(address) {
                result[address, default: 0] += weight
            }
        }
        return result
    }
}
