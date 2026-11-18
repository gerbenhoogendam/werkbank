import Foundation

/// Eén ontvanger in een adresveld (Aan, Cc, Bcc) als blokje: de naam, of het adres als er geen naam is. Wat geen
/// geldig adres is blijft staan zoals het getypt is (`isValid` is dan `false`), zodat je ziet dat het niet klopt.
public struct RecipientToken: Equatable, Identifiable {
    public var id: UUID
    public var name: String?
    /// Het adres; bij een ongeldig blokje de tekst zoals die getypt is.
    public var address: String
    public var isValid: Bool

    public init(id: UUID = UUID(), name: String? = nil, address: String, isValid: Bool = true) {
        self.id = id
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        self.name = trimmed.isEmpty ? nil : trimmed
        self.address = address
        self.isValid = isValid
    }

    public init(_ address: MailAddress) {
        self.init(name: address.name, address: address.address)
    }

    /// Wat er op het blokje staat.
    public var label: String { name ?? address }

    /// Zoals de ontvanger in de tekst van het veld staat ("Naam <adres>", een naam met een komma tussen
    /// aanhalingstekens).
    public var fieldText: String {
        isValid ? AddressSuggestions.fieldString(MailAddress(name: name, address: address)) : address
    }
}

/// Een adresveld als blokjes en een stukje tekst waaraan nog getypt wordt. Het veld zelf blijft één tekst
/// ("Naam <adres>, adres"), zodat versturen, concepten en beantwoorden er niets van merken.
public enum RecipientTokens {
    /// Splitst op komma's, puntkomma's en regeleinden (niet binnen aanhalingstekens of <>): de afgesloten stukken en
    /// wat er na het laatste scheidingsteken staat.
    static func split(_ text: String) -> (closed: [String], tail: String) {
        var closed: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for character in text {
            switch character {
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "<" where !inQuotes:
                inAngle = true
                current.append(character)
            case ">" where !inQuotes:
                inAngle = false
                current.append(character)
            case ",", ";", "\n", "\r", "\r\n":
                if inQuotes || (inAngle && !character.isNewline) {
                    current.append(character)
                } else {
                    closed.append(current)
                    current = ""
                    inAngle = false
                }
            default:
                current.append(character)
            }
        }
        return (closed, current)
    }

    /// De stukken van een veld, op volgorde en zonder lege stukken.
    public static func pieces(_ text: String) -> [String] {
        let parts = split(text)
        return (parts.closed + [parts.tail])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Eén stuk als blokje: een adres (met of zonder naam), of ongeldig met de tekst zoals die er stond.
    public static func token(_ piece: String) -> RecipientToken {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = MailAddress.parse(trimmed)
        if parsed.valid.count == 1, parsed.invalid.isEmpty { return RecipientToken(parsed.valid[0]) }
        return RecipientToken(address: trimmed, isValid: false)
    }

    /// Een heel veld als blokjes (bij het openen van een antwoord of concept).
    public static func tokens(from text: String) -> [RecipientToken] {
        pieces(text).map(token)
    }

    /// De tekst van het veld: de blokjes en daarachter wat er nog getypt wordt.
    public static func text(_ tokens: [RecipientToken], draft: String = "") -> String {
        let typing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tokens.map(\.fieldText) + (typing.isEmpty ? [] : [typing])).joined(separator: ", ")
    }

    /// Een compleet adres ("a@b.nl" of "Naam <a@b.nl>"): daarna sluit een spatie het blokje.
    public static func isComplete(_ text: String) -> Bool {
        let parsed = MailAddress.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return parsed.valid.count == 1 && parsed.invalid.isEmpty
    }

    /// Wat er getypt of geplakt is, verwerkt: alles vóór een komma, puntkomma of regeleinde wordt een blokje, de rest
    /// blijft staan om aan verder te typen. Staat er een compleet adres met een spatie erachter, dan sluit dat ook
    /// (een naam typ je met spaties, die sluit dus niet).
    public static func absorb(_ draft: String) -> (tokens: [RecipientToken], draft: String) {
        let parts = split(draft)
        var tokens = parts.closed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(token)
        var rest = parts.closed.isEmpty ? parts.tail : String(parts.tail.drop { $0 == " " })
        if let last = rest.last, last.isWhitespace, isComplete(rest) {
            tokens.append(token(rest))
            rest = ""
        }
        return (tokens, rest)
    }
}
