import AppKit
import Foundation

/// De handelingen in de mailmodus met hun toets (ook een combinatie zoals ⇧⌘R). De toetsen, en welke knoppen in de
/// mail staan, zijn aan te passen in Voorkeuren › Mail en gaan mee naar je andere Macs.
enum MailModeAction: String, CaseIterable, Identifiable {
    case archive, task, time, plan, reply, follow, claude, scope, search, next, previous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .archive: "Archiveren"
        case .task: "Taak maken"
        case .time: "Tijd schrijven"
        case .plan: "Inplannen"
        case .reply: "Beantwoorden"
        case .follow: "Opvolgen"
        case .claude: "Claude-concept"
        case .scope: "Volgende mailbox of combinatie"
        case .search: "Zoeken"
        case .next: "Volgende mail"
        case .previous: "Vorige mail"
        }
    }

    var defaultKey: String {
        switch self {
        case .archive: "E"
        case .task: "T"
        case .time: "S"
        case .plan: "P"
        case .reply: "R"
        case .follow: "F"
        case .claude: "C"
        case .scope: MailModeKeys.tab
        case .search: "/"
        case .next: "J"
        case .previous: "K"
        }
    }
}

enum MailModeKeys {
    static let storageKey = "mailMode.keys"
    /// Handelingen waarvan de knop niet in de mail staat (Voorkeuren › Mail); de sneltoets werkt wel.
    static let hiddenButtonsKey = "mailMode.hiddenButtons"
    /// Zo staat de tabtoets in de voorkeuren.
    static let tab = "⇥"

    /// De handelingen die als knop in de mail staan, in die volgorde.
    static let buttons: [MailModeAction] = [.archive, .reply, .task, .time, .plan, .follow, .claude]

    /// Combinaties die van macOS of de app zelf zijn (kopiëren, plakken, ongedaan maken, zoeken, ⌘1 werkbank en
    /// ⌘2 mail …).
    static let reserved: Set<String> = ["⌘C", "⌘V", "⌘X", "⌘A", "⌘Z", "⇧⌘Z", "⌘Q", "⌘W", "⌘H", "⌘M", "⌘,", "⌘F", "⌘⇥",
                                        "⌘1", "⌘2"]

    /// De toets van een handeling: je eigen keuze, anders de standaard.
    static func key(for action: MailModeAction) -> String {
        let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        return stored[action.rawValue] ?? action.defaultKey
    }

    static func set(_ key: String, for action: MailModeAction) {
        var stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        stored[action.rawValue] = key == action.defaultKey ? nil : key
        UserDefaults.standard.set(stored, forKey: storageKey)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// De handeling die al op `key` staat (behalve `action` zelf).
    static func conflict(_ key: String, excluding action: MailModeAction) -> MailModeAction? {
        MailModeAction.allCases.first { $0 != action && self.key(for: $0) == key }
    }

    /// Met ⌘, ⌃ of ⌥: werkt ook terwijl je typt (een losse letter is dan voor het tekstveld).
    static func hasModifiers(_ key: String) -> Bool {
        key.contains("⌘") || key.contains("⌃") || key.contains("⌥")
    }

    /// De toets zoals hij in de voorkeuren staat, uit een toetsaanslag: ⌃, ⌥, ⇧ en ⌘ (in die volgorde) voor de toets
    /// zelf, bijvoorbeeld "⇧⌘R". ⇧ telt alleen naast een van de andere (zonder is een hoofdletter gewoon de letter).
    /// `nil` voor toetsen die niet kunnen (pijlen, functietoetsen, spatie).
    static func key(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let base: String
        if event.keyCode == 48 {
            base = tab
        } else {
            guard let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
                  characters.count == 1, let scalar = characters.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar), scalar != " ",
                  !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
            base = characters.uppercased()
        }
        let others = !flags.intersection([.control, .option, .command]).isEmpty
        var prefix = ""
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift), others { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        return prefix + base
    }

    /// De handeling bij een toetsaanslag (met of zonder ⌘, ⌃, ⌥).
    static func action(for event: NSEvent) -> MailModeAction? {
        guard let key = key(from: event) else { return nil }
        return MailModeAction.allCases.first { self.key(for: $0) == key }
    }

    // MARK: Knoppen in de mail

    /// `hidden`: de opgeslagen tekst (namen met komma's), zodat een view hem met @AppStorage kan volgen.
    static func showsButton(_ action: MailModeAction, hidden: String) -> Bool {
        !hidden.split(separator: ",").contains { $0 == action.rawValue }
    }

    /// De nieuwe tekst voor `hiddenButtonsKey`.
    static func hidden(_ hidden: String, showing shown: Bool, _ action: MailModeAction) -> String {
        var names = Set(hidden.split(separator: ",").map(String.init))
        if shown { names.remove(action.rawValue) } else { names.insert(action.rawValue) }
        return names.sorted().joined(separator: ",")
    }
}
