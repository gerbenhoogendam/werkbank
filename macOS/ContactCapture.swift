import Contacts
import SwiftUI
import WerkbankCore

/// De velden van het contactpaneel, in de volgorde waarin ze staan.
enum ContactField: CaseIterable, Hashable {
    case givenName, familyName, organization, jobTitle, email, workPhone, mobilePhone, website, street, postalCode,
         city, country

    var label: String {
        switch self {
        case .givenName:    "Voornaam"
        case .familyName:   "Achternaam"
        case .organization: "Bedrijf"
        case .jobTitle:     "Functie"
        case .email:        "E-mail"
        case .workPhone:    "Telefoon"
        case .mobilePhone:  "Mobiel"
        case .website:      "Website"
        case .street:       "Straat"
        case .postalCode:   "Postcode"
        case .city:         "Plaats"
        case .country:      "Land"
        }
    }

    var keyPath: WritableKeyPath<ContactCard, String> {
        switch self {
        case .givenName:    \.givenName
        case .familyName:   \.familyName
        case .organization: \.organization
        case .jobTitle:     \.jobTitle
        case .email:        \.email
        case .workPhone:    \.workPhone
        case .mobilePhone:  \.mobilePhone
        case .website:      \.website
        case .street:       \.street
        case .postalCode:   \.postalCode
        case .city:         \.city
        case .country:      \.country
        }
    }
}

/// Afzender van een mail in Contacten: naam en adres uit het van-veld, de rest haalt Claude uit de handtekening.
/// Alles is na te kijken en aan te passen; één klik bewaart. Staat het adres al in Contacten, dan wordt dat contact
/// aangevuld (lege velden, nieuwe nummers, website en adres) in plaats van een tweede aangemaakt.
struct ContactCaptureView: View {
    let ref: MailRef
    let onClose: () -> Void

    private enum Phase: Equatable { case loading, reading, ready, saving }

    @State private var card = ContactCard()
    /// Wat Claude uit de handtekening haalde; een veld met precies die waarde krijgt een vonkje.
    @State private var extracted = ContactCard()
    @State private var phase: Phase = .loading
    @State private var existing: CNContact?
    @State private var error: String?
    @State private var subject = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if phase == .reading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Claude leest de handtekening…")
                                .thingsFont(.metadata)
                                .foregroundStyle(ThingsColor.textSecondary)
                        }
                    }
                    if let existing {
                        Label("Staat al in Contacten: \(ContactBook.name(of: existing))", systemImage: "person.crop.circle")
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                    if let error {
                        Text(error)
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.error)
                            .textSelection(.enabled)
                    }
                    fields
                }
                .padding(18)
            }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            footer
        }
        .background(ThingsColor.backgroundContent)
        .task { await load() }
        .onAppear { PanelStore.shared.markEngaged(PanelKind.contact(ref).id) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.werk(size: 20))
                .foregroundStyle(ThingsColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Contact opslaan")
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text(subject.isEmpty ? ref.subject : subject)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Sluit", action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(ContactField.allCases, id: \.self) { field in
                GridRow {
                    Text(field.label)
                        .font(.werk(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fieldLabel)
                        .gridColumnAlignment(.trailing)
                    TextField("", text: binding(field))
                        .textFieldStyle(.roundedBorder)
                        .disabled(phase == .loading || phase == .saving)
                    Group {
                        if isFromSignature(field) {
                            ClaudeSpark().frame(width: 12, height: 12).help("Uit de handtekening")
                        } else {
                            Color.clear.frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if phase == .saving { ProgressView().controlSize(.small) }
            Spacer()
            Button("Annuleer", action: onClose)
            Button(existing == nil ? "Bewaar in Contacten" : "Aanvullen in Contacten", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(phase == .loading || phase == .saving || !hasSomething)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var hasSomething: Bool {
        ![card.givenName, card.familyName, card.organization, card.email]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func binding(_ field: ContactField) -> Binding<String> {
        Binding(get: { card[keyPath: field.keyPath] }, set: { card[keyPath: field.keyPath] = $0 })
    }

    private func isFromSignature(_ field: ContactField) -> Bool {
        let value = extracted[keyPath: field.keyPath]
        return !value.isEmpty && card[keyPath: field.keyPath] == value
    }

    // MARK: Ophalen

    private func load() async {
        let gmail = GmailSession.shared
        gmail.note(account: ref.account, forMessageID: ref.messageID)
        let content: MailContent
        do {
            let raw = try await gmail.rawMessageData(id: ref.messageID)
            content = await Task.detached(priority: .userInitiated) { MailContentParser.parse(raw) }.value
        } catch {
            self.error = "Mail ophalen mislukt: \(error.localizedDescription)"
            phase = .ready
            return
        }
        subject = content.subject
        let fromHeader = ContactCard.fromHeader(content.from)
        card = fromHeader
        if await ContactBook.access() {
            existing = ContactBook.existing(email: fromHeader.email)
        } else {
            error = "Geen toegang tot Contacten (Systeeminstellingen › Privacy en beveiliging › Contacten)"
        }

        guard ClaudeKeychain.read() != nil else {
            phase = .ready
            return
        }
        phase = .reading
        let text = ContactCard.signatureText(html: content.displayHTML, subject: content.subject)
        if let found = await ContactExtractor.extract(from: content.from, text: text) {
            var merged = card
            for field in ContactField.allCases {
                let value = found[keyPath: field.keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
                // Het adres uit het van-veld blijft; wat je intussen zelf hebt aangepast ook.
                guard !value.isEmpty, field != .email || merged.email.isEmpty,
                      card[keyPath: field.keyPath] == fromHeader[keyPath: field.keyPath] else { continue }
                merged[keyPath: field.keyPath] = value
                extracted[keyPath: field.keyPath] = value
            }
            card = merged
        } else if error == nil {
            error = "Claude kon de handtekening niet lezen; vul aan wat ontbreekt."
        }
        phase = .ready
    }

    // MARK: Bewaren

    private func save() {
        phase = .saving
        error = nil
        Task {
            guard await ContactBook.access() else {
                error = "Geen toegang tot Contacten (Systeeminstellingen › Privacy en beveiliging › Contacten)"
                phase = .ready
                return
            }
            do {
                // Opnieuw zoeken: het adres kan zijn aangepast.
                let target = ContactBook.existing(email: card.email.trimmingCharacters(in: .whitespaces))
                try ContactBook.save(card, into: target)
                let name = card.displayName.isEmpty ? card.organization : card.displayName
                AppState.shared.announce(target == nil ? "In Contacten: \(name)" : "Aangevuld in Contacten: \(name)")
                onClose()
            } catch {
                self.error = "Bewaren mislukt: \(error.localizedDescription)"
                phase = .ready
            }
        }
    }
}

// MARK: - Claude

/// Haalt met Claude de contactgegevens van de afzender uit de tekst van de mail (vooral de handtekening).
enum ContactExtractor {
    private struct Answer: Decodable {
        let givenName, familyName, organization, jobTitle, email: String
        let workPhone, mobilePhone, website, street, postalCode, city, country: String
    }

    private static let keys = ["givenName", "familyName", "organization", "jobTitle", "email", "workPhone",
                               "mobilePhone", "website", "street", "postalCode", "city", "country"]

    @MainActor
    static func extract(from: String, text: String) async -> ContactCard? {
        guard let key = ClaudeKeychain.read() else { return nil }
        let model = ClaudeSettings.model
        let context = ClaudeSettings.context
        do {
            let result = try await ClaudeStreamer.run(
                key: key,
                makeBody: { useFallbacks in
                    body(from: from, text: text, context: context, model: model, useFallbacks: useFallbacks)
                },
                onText: { _ in })
            guard result.stopReason != "refusal", let data = result.text.data(using: .utf8),
                  let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
            return ContactCard(givenName: answer.givenName, familyName: answer.familyName,
                               organization: answer.organization, jobTitle: answer.jobTitle, email: answer.email,
                               workPhone: answer.workPhone, mobilePhone: answer.mobilePhone, website: answer.website,
                               street: answer.street, postalCode: answer.postalCode, city: answer.city,
                               country: answer.country)
        } catch {
            return nil
        }
    }

    nonisolated static func body(from: String, text: String, context: String, model: ClaudeModel,
                                 useFallbacks: Bool) -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "properties": Dictionary(uniqueKeysWithValues: keys.map { ($0, ["type": "string"]) }),
            "required": keys,
            "additionalProperties": false,
        ]
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 4_000,
            "stream": true,
            "system": systemPrompt(context: context),
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": [["type": "text", "text": "Van: \(from)\n\n\(text)"]]]],
        ]
        if useFallbacks { body["fallbacks"] = "default" }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    nonisolated static func systemPrompt(context: String) -> String {
        """
        Je krijgt een mail: het van-veld en de tekst die de afzender zelf schreef (zonder het geciteerde gesprek). \
        Haal de contactgegevens van de afzender eruit, vooral uit de handtekening onderaan, voor het adresboek.

        Over de ontvanger (niet de afzender, neem hiervan niets over):
        \(context)

        - Alleen gegevens van de afzender zelf; niet van anderen die in de tekst genoemd worden.
        - givenName en familyName: voornaam en achternaam, tussenvoegsels (van, de, van der) bij de achternaam.
        - organization: het bedrijf van de afzender; jobTitle: de functie.
        - email: het adres uit het van-veld, tenzij de handtekening een ander persoonlijk adres geeft.
        - workPhone: het vaste of algemene nummer; mobilePhone: een mobiel nummer (in Nederland 06…). Schrijf ze zoals \
        ze er staan.
        - website: zoals hij er staat. street (met huisnummer), postalCode, city, country: alleen als ze er staan.
        Laat leeg wat er niet staat. Verzin niets.
        """
    }
}

// MARK: - Contacten

/// Lezen en schrijven in Contacten (macOS-adresboek).
@MainActor
enum ContactBook {
    private static let store = CNContactStore()

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
        CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey,
    ].map { $0 as CNKeyDescriptor }

    /// Vraagt de eerste keer om toegang.
    static func access() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestAccess(for: .contacts)) ?? false
        default:
            return false
        }
    }

    /// Een contact met dit e-mailadres, als dat er al is.
    static func existing(email: String) -> CNContact? {
        guard email.contains("@") else { return nil }
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        return try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first
    }

    static func name(of contact: CNContact) -> String {
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? contact.organizationName : name
    }

    /// Nieuw contact, of `existing` aanvullen: lege velden invullen en nummers, adres, website en e-mail toevoegen die
    /// er nog niet in staan. Niets wat er al staat wordt overschreven.
    static func save(_ card: ContactCard, into existing: CNContact?) throws {
        let contact = (existing?.mutableCopy() as? CNMutableContact) ?? CNMutableContact()
        let clean = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }

        if contact.givenName.isEmpty { contact.givenName = clean(card.givenName) }
        if contact.familyName.isEmpty { contact.familyName = clean(card.familyName) }
        if contact.organizationName.isEmpty { contact.organizationName = clean(card.organization) }
        if contact.jobTitle.isEmpty { contact.jobTitle = clean(card.jobTitle) }

        let email = clean(card.email)
        if !email.isEmpty,
           !contact.emailAddresses.contains(where: { ($0.value as String).caseInsensitiveCompare(email) == .orderedSame }) {
            contact.emailAddresses.append(CNLabeledValue(label: CNLabelWork, value: email as NSString))
        }

        let digits = { (text: String) in text.filter(\.isNumber) }
        for (number, label) in [(clean(card.workPhone), CNLabelWork), (clean(card.mobilePhone), CNLabelPhoneNumberMobile)]
        where !number.isEmpty && !contact.phoneNumbers.contains(where: { digits($0.value.stringValue) == digits(number) }) {
            contact.phoneNumbers.append(CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: number)))
        }

        let website = clean(card.website)
        if !website.isEmpty,
           !contact.urlAddresses.contains(where: { ($0.value as String).caseInsensitiveCompare(website) == .orderedSame }) {
            contact.urlAddresses.append(CNLabeledValue(label: CNLabelWork, value: website as NSString))
        }

        let street = clean(card.street)
        let postalCode = clean(card.postalCode)
        let city = clean(card.city)
        let country = clean(card.country)
        if !(street + postalCode + city).isEmpty,
           !contact.postalAddresses.contains(where: { $0.value.street.caseInsensitiveCompare(street) == .orderedSame
               && $0.value.city.caseInsensitiveCompare(city) == .orderedSame }) {
            let address = CNMutablePostalAddress()
            address.street = street
            address.postalCode = postalCode
            address.city = city
            address.country = country
            contact.postalAddresses.append(CNLabeledValue<CNPostalAddress>(label: CNLabelWork, value: address))
        }

        let request = CNSaveRequest()
        if existing == nil {
            request.add(contact, toContainerWithIdentifier: nil)
        } else {
            request.update(contact)
        }
        try store.execute(request)
    }
}
