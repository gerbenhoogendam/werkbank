import Foundation

// De aanwijsmodus bij een verbetering op de Mac: terwijl je inspreekt, klik je op wat je bedoelt ("als ik hier klik …")
// of sleep je een kader. Elke markering krijgt een nummer en het moment in de opname; in de tekst komt [1] achter het
// woord dat je zei toen je klikte, op de screenshot staat hetzelfde nummer.

/// Een klik of kader op het venster.
public struct FeedbackMark: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case click, area }

    public var number: Int
    public var kind: Kind
    /// Genormaliseerd (0…1) op het venster, linksboven is 0,0. Een klik heeft breedte en hoogte 0.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Seconden na het begin van de opname.
    public var time: Double

    public init(number: Int, kind: Kind, x: Double, y: Double, width: Double = 0, height: Double = 0, time: Double) {
        self.number = number
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.time = time
    }

    public var id: Int { number }

    /// Waar op het venster: "linksboven", "in het midden", "rechts in het midden" …
    public var region: String {
        let centerX = x + width / 2
        let centerY = y + height / 2
        let column = centerX < 1.0 / 3 ? 0 : (centerX > 2.0 / 3 ? 2 : 1)
        let row = centerY < 1.0 / 3 ? 0 : (centerY > 2.0 / 3 ? 2 : 1)
        let names = [["linksboven", "boven in het midden", "rechtsboven"],
                     ["links in het midden", "in het midden", "rechts in het midden"],
                     ["linksonder", "onder in het midden", "rechtsonder"]]
        return names[row][column]
    }

    /// "[1] klik rechtsboven op 0:04".
    public var summary: String {
        let seconds = max(0, Int(time.rounded()))
        let what = kind == .click ? "klik" : "kader"
        return "[\(number)] \(what) \(region) op \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    public static func encode(_ marks: [FeedbackMark]) -> Data? {
        marks.isEmpty ? nil : try? JSONEncoder().encode(marks)
    }

    public static func decode(_ data: Data?) -> [FeedbackMark] {
        data.flatMap { try? JSONDecoder().decode([FeedbackMark].self, from: $0) } ?? []
    }
}

public enum FeedbackTranscript {
    /// Een woord met zijn tijd in de opname (van Whisper).
    public struct Word: Equatable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// De tekst met [n] achter het woord dat je zei toen je klikte of het kader losliet (het laatste woord dat vóór
    /// dat moment begon); markeringen vóór het eerste woord komen vooraan.
    public static func text(_ words: [Word], marks: [FeedbackMark]) -> String {
        var after: [Int: [Int]] = [:]   // woordindex → nummers; -1 = vooraan
        for mark in marks.sorted(by: { $0.time < $1.time }) {
            let index = words.lastIndex { $0.start <= mark.time } ?? -1
            after[index, default: []].append(mark.number)
        }
        func tags(_ index: Int) -> String {
            (after[index] ?? []).map { "[\($0)]" }.joined()
        }
        var result = tags(-1)
        for (index, word) in words.enumerated() {
            let piece = word.text.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            // Leestekens plakken aan het vorige woord.
            let glue = result.isEmpty || piece.first.map { ",.;:!?)".contains($0) } == true
            result += (glue ? "" : " ") + piece
            let marked = tags(index)
            if !marked.isEmpty { result += " " + marked }
        }
        if words.isEmpty, !marks.isEmpty { result = tags(-1) }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
