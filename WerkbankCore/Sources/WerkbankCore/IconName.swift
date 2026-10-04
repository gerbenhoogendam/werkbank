import Foundation

/// Een kolomicoon is een SF Symbol-naam (ASCII, bijv. "tray.fill") of een emoji.
public enum IconName {
    /// `true` als de tekst met een emoji (of ander niet-ASCII teken) begint; SF Symbol-namen zijn altijd ASCII.
    public static func isEmoji(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        return !first.isASCII
    }

    /// Het eerste emoji-teken (inclusief samengestelde, zoals vlaggen en gezinnen) uit getypte of geplakte tekst.
    /// Cijfers en gewone letters tellen niet mee, ook al hebben ze een emoji-variant.
    public static func firstEmoji(in text: String) -> String? {
        text.first { character in
            guard let scalar = character.unicodeScalars.first else { return false }
            return !scalar.isASCII && scalar.properties.isEmoji
        }.map(String.init)
    }
}
