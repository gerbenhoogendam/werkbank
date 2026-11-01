import Contacts
import Foundation
import WerkbankCore

/// De adressen om aan te vullen bij het opstellen: wie je mailde (MailActivityStore, verzonden het zwaarst), de
/// mailadressen uit Contacten en bij elk adres de klant uit de klantenlijst.
@MainActor
final class AddressBook {
    static let shared = AddressBook()

    private struct Contact: Sendable {
        let name: String?
        let address: String
    }

    private var cached: [AddressCandidate]?
    private var cachedRecordCount = -1
    private var contacts: [Contact] = []
    private var contactsRequested = false
    private var syncing = false

    func candidates() -> [AddressCandidate] {
        let activity = MailActivityStore.shared
        activity.loadIfNeeded()
        if let cached, cachedRecordCount == activity.records.count { return cached }
        let own = GmailSession.shared.ownAddresses
        let map = ClientDirectory.shared.domainMap
        let scores = AddressSuggestions.scores(records: activity.records, ownAddresses: own, now: .now)
        var byAddress: [String: AddressCandidate] = [:]
        for (address, score) in scores {
            byAddress[address] = AddressCandidate(name: activity.names[address], address: address,
                                                  client: ClientActivity.client(forAddress: address, domainMap: map), score: score)
        }
        for contact in contacts {
            let address = contact.address.lowercased()
            guard !own.contains(address), address.contains("@") else { continue }
            if var existing = byAddress[address] {
                // De naam uit Contacten heb je zelf zo genoteerd: die gaat voor.
                if let name = contact.name { existing.name = name }
                byAddress[address] = existing
            } else {
                byAddress[address] = AddressCandidate(name: contact.name, address: address,
                                                      client: ClientActivity.client(forAddress: address, domainMap: map), score: 0.1)
            }
        }
        let result = Array(byAddress.values)
        cached = result
        cachedRecordCount = activity.records.count
        return result
    }

    /// Bij het eerste adresveld: Contacten inlezen (de eerste keer vraagt macOS toestemming) en ophalen wat er sinds
    /// de vorige keer gemaild is.
    func prepare() async {
        if !contactsRequested {
            contactsRequested = true
            if await ContactBook.access() {
                contacts = await Self.loadContacts()
                cached = nil
            }
        }
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        if await MailActivityStore.shared.syncIfStale() { cached = nil }
    }

    private nonisolated static func loadContacts() async -> [Contact] {
        await Task.detached(priority: .utility) {
            let store = CNContactStore()
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey].map { $0 as CNKeyDescriptor }
            var result: [Contact] = []
            try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for email in contact.emailAddresses {
                    result.append(Contact(name: name.isEmpty ? nil : name, address: email.value as String))
                }
            }
            return result
        }.value
    }
}
