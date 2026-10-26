import Foundation

/// Een contactpersoon uit een mail: het van-veld plus wat er in de handtekening staat. Leeg = onbekend.
public struct ContactCard: Equatable, Sendable {
    public var givenName = ""
    public var familyName = ""
    public var organization = ""
    public var jobTitle = ""
    public var email = ""
    public var workPhone = ""
    public var mobilePhone = ""
    public var website = ""
    public var street = ""
    public var postalCode = ""
    public var city = ""
    public var country = ""

    public init(givenName: String = "", familyName: String = "", organization: String = "", jobTitle: String = "",
                email: String = "", workPhone: String = "", mobilePhone: String = "", website: String = "",
                street: String = "", postalCode: String = "", city: String = "", country: String = "") {
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.email = email
        self.workPhone = workPhone
        self.mobilePhone = mobilePhone
        self.website = website
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    /// Naam en adres uit het van-veld ("Jan van der Berg <jan@x.nl>", "Berg, Jan <jan@x.nl>").
    public static func fromHeader(_ from: String) -> ContactCard {
        guard let sender = MailAddress.parse(from).valid.first else { return ContactCard() }
        var card = ContactCard(email: sender.address.lowercased())
        let name = (sender.name ?? "").trimmingCharacters(in: .whitespaces)
        // Geen naam, of alleen het adres nog eens: dan geen naam.
        guard !name.isEmpty, !name.contains("@") else { return card }
        let split = splitName(name)
        card.givenName = split.given
        card.familyName = split.family
        return card
    }

    /// "Jan van der Berg" → Jan / van der Berg; "Berg, Jan" → Jan / Berg; één woord is de voornaam.
    public static func splitName(_ name: String) -> (given: String, family: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let comma = trimmed.firstIndex(of: ",") {
            let family = trimmed[..<comma].trimmingCharacters(in: .whitespaces)
            let given = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if !family.isEmpty, !given.isEmpty { return (given, family) }
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return (trimmed, "") }
        return (words[0], words.dropFirst().joined(separator: " "))
    }

    /// De eigen tekst van de laatste mail (zonder het geciteerde gesprek eronder), het eind eerst bewaard: daar staat
    /// de handtekening.
    public static func signatureText(html: String, subject: String, limit: Int = 4000) -> String {
        let main = QuoteSplitter.split(html: html, subject: subject).main
        let text = MIMEBody.tidy(MIMEBody.htmlToText(main))
        return text.count > limit ? String(text.suffix(limit)) : text
    }

    public var displayName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
