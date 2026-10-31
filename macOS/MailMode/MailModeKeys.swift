import AppKit
import Foundation

/// De handelingen in de mailmodus met hun toets. De toetsen zijn aan te passen in Voorkeuren › Mail en gaan mee naar
/// je andere Macs.
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
    /// Zo staat de tabtoets in de voorkeuren en op de knoppen.
    static let tab = "⇥"

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

    /// De toets zoals hij in de voorkeuren staat, uit een toetsaanslag; `nil` voor toetsen die niet kunnen.
    static func key(from event: NSEvent) -> String? {
        if event.keyCode == 48 { return tab }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), scalar != " " else { return nil }
        return characters.uppercased()
    }

    /// De handeling bij een toetsaanslag zonder ⌘, ⌃ of ⌥.
    static func action(for event: NSEvent) -> MailModeAction? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = key(from: event) else { return nil }
        return MailModeAction.allCases.first { self.key(for: $0) == key }
    }
}
