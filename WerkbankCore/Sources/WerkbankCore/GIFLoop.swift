import Foundation

/// Bewegende GIF's één keer laten afspelen. Zonder de herhaalinstructie (de applicatie-extensie NETSCAPE2.0 of
/// ANIMEXTS1.0) speelt WebKit een animatie één keer en blijft hij op het laatste beeld staan. Voor de weergave van
/// mails: een bewegend logo in een handtekening blijft anders eindeloos herhalen.
public enum GIFLoop {
    /// Dezelfde GIF zonder herhaling. Geen GIF, geen herhaling of onleesbaar: ongewijzigd.
    public static func playOnce(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        // Kop (6 bytes) en schermbeschrijving (7 bytes); het pakbyte op 10 zegt of er een globale kleurtabel volgt.
        guard bytes.count > 13, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 else { return data }
        var index = 13 + colorTableSize(bytes[10])
        guard index <= bytes.count else { return data }
        var output = Array(bytes[0..<index])
        output.reserveCapacity(bytes.count)
        var removed = false

        while index < bytes.count {
            switch bytes[index] {
            case 0x3B:   // einde van het bestand
                output.append(contentsOf: bytes[index...])
                return removed ? Data(output) : data
            case 0x21:   // extensie: soort, dan subblokken
                guard index + 1 < bytes.count, let end = subBlocksEnd(bytes, from: index + 2) else { return data }
                if bytes[index + 1] == 0xFF, isLoopExtension(bytes, at: index + 2) {
                    removed = true
                } else {
                    output.append(contentsOf: bytes[index..<end])
                }
                index = end
            case 0x2C:   // beeld: 10 bytes beschrijving, eventueel een eigen kleurtabel, LZW-grootte, subblokken
                guard index + 10 <= bytes.count else { return data }
                let start = index + 10 + colorTableSize(bytes[index + 9])
                guard start < bytes.count, let end = subBlocksEnd(bytes, from: start + 1) else { return data }
                output.append(contentsOf: bytes[index..<end])
                index = end
            default:
                return data
            }
        }
        // Zonder eindbyte (komt voor): wat er is.
        return removed ? Data(output) : data
    }

    private static let dataURL = try! NSRegularExpression(pattern: #"data:image/gif;base64,([A-Za-z0-9+/=\s]+)"#,
                                                          options: [.caseInsensitive])

    /// Alle GIF's die als data-URL in de HTML staan (ingesloten afbeeldingen), zonder herhaling.
    public static func playOnce(inHTML html: String) -> String {
        guard html.range(of: "data:image/gif", options: .caseInsensitive) != nil else { return html }
        let ns = NSString(string: html)
        var result = html
        for match in dataURL.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let encoded = ns.substring(with: match.range(at: 1)).filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: encoded), let range = Range(match.range, in: result) else { continue }
            let once = playOnce(data)
            guard once != data else { continue }
            result.replaceSubrange(range, with: "data:image/gif;base64," + once.base64EncodedString())
        }
        return result
    }

    /// Grootte van een kleurtabel volgens het pakbyte (bit 7: aanwezig, bits 0-2: 2^(n+1) kleuren van 3 bytes).
    private static func colorTableSize(_ packed: UInt8) -> Int {
        packed & 0x80 == 0 ? 0 : 3 * (1 << (Int(packed & 0x07) + 1))
    }

    /// Positie direct na de subblokken die op `start` beginnen (inclusief het afsluitende blok van 0).
    private static func subBlocksEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index < bytes.count {
            let size = Int(bytes[index])
            index += 1
            if size == 0 { return index }
            index += size
        }
        return nil
    }

    private static func isLoopExtension(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 12 <= bytes.count, bytes[index] == 11 else { return false }
        let identifier = String(decoding: bytes[(index + 1)..<(index + 12)], as: UTF8.self)
        return identifier == "NETSCAPE2.0" || identifier == "ANIMEXTS1.0"
    }
}
