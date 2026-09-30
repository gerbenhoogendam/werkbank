import Foundation

/// Resultaat van het parsen van een .eml-bestand (alleen wat Werkbank nodig heeft).
public struct ParsedMail: Equatable {
    public var subject: String
    public var fromName: String?
    public var fromAddress: String?

    public init(subject: String, fromName: String? = nil, fromAddress: String? = nil) {
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
    }

    /// "Naam · adres@domein.nl", of alleen het adres / de naam als het andere ontbreekt.
    public var senderLine: String? {
        switch (fromName, fromAddress) {
        case let (name?, address?): return "\(name) · \(address)"
        case let (nil, address?):   return address
        case let (name?, nil):      return name
        default:                    return nil
        }
    }
}

public enum EMLParser {
    public static let emptySubject = "(geen onderwerp)"

    /// Parst de headers van ruwe .eml-data. Het lichaam wordt niet gelezen.
    public static func parse(_ data: Data) -> ParsedMail {
        let headerData = headerSection(of: data)
        let text = String(data: headerData, encoding: .utf8)
            ?? String(data: headerData, encoding: .isoLatin1)
            ?? ""
        return parse(text)
    }

    public static func parse(_ text: String) -> ParsedMail {
        let fields = headers(from: text)

        let rawSubject = fields.first { $0.name.lowercased() == "subject" }?.value ?? ""
        let subject = decodeEncodedWords(rawSubject).trimmingCharacters(in: .whitespacesAndNewlines)

        var fromName: String?
        var fromAddress: String?
        if let rawFrom = fields.first(where: { $0.name.lowercased() == "from" })?.value {
            let parsed = parseAddress(rawFrom)
            fromName = parsed.name
            fromAddress = parsed.address
        }

        return ParsedMail(
            subject: subject.isEmpty ? emptySubject : subject,
            fromName: fromName,
            fromAddress: fromAddress
        )
    }

    // MARK: - Headers

    /// Knipt de data af bij de eerste lege regel (einde van de headers).
    static func headerSection(of data: Data) -> Data {
        let crlf = data.range(of: Data([13, 10, 13, 10]))?.lowerBound
        let lf = data.range(of: Data([10, 10]))?.lowerBound
        let end = [crlf, lf].compactMap { $0 }.min() ?? data.endIndex
        return data.subdata(in: data.startIndex..<end)
    }

    /// Headers tot de eerste lege regel, met ondersteuning voor gevouwen (doorlopende) regels.
    static func headers(from text: String) -> [(name: String, value: String)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var result: [(name: String, value: String)] = []
        for line in lines {
            if line.isEmpty { break }   // einde headers
            if let first = line.first, first == " " || first == "\t" {
                // Doorlopende regel: hoort bij de vorige header.
                guard !result.isEmpty else { continue }
                let continuation = line.trimmingCharacters(in: .whitespaces)
                result[result.count - 1].value += " " + continuation
            } else if let colon = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                result.append((name: name, value: value))
            }
        }
        return result
    }

    // MARK: - Adres

    /// Splitst een From-header in weergavenaam en e-mailadres.
    /// Ondersteunt `Naam <a@b.nl>`, `"Naam" <a@b.nl>`, `a@b.nl` en `a@b.nl (Naam)`.
    static func parseAddress(_ raw: String) -> (name: String?, address: String?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil) }

        var name: String?
        var address: String?

        if let open = value.lastIndex(of: "<"),
           let close = value.lastIndex(of: ">"), open < close {
            address = String(value[value.index(after: open)..<close])
            name = String(value[value.startIndex..<open])
        } else if let open = value.firstIndex(of: "("),
                  let close = value.lastIndex(of: ")"), open < close {
            name = String(value[value.index(after: open)..<close])
            address = String(value[value.startIndex..<open])
        } else {
            address = value
        }

        address = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let a = address, !a.contains("@") { address = a.isEmpty ? nil : a }
        if address?.isEmpty == true { address = nil }

        if var n = name {
            n = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.hasPrefix("\""), n.hasSuffix("\""), n.count >= 2 {
                n = String(n.dropFirst().dropLast())
                n = n.replacingOccurrences(of: "\\\"", with: "\"")
            }
            n = decodeEncodedWords(n).trimmingCharacters(in: .whitespacesAndNewlines)
            name = n.isEmpty ? nil : n
        }

        return (name, address)
    }

    // MARK: - RFC 2047

    private static let encodedWord = try! NSRegularExpression(
        pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#
    )

    /// Decodeert RFC 2047 encoded words (`=?UTF-8?B?…?=` en `=?ISO-8859-1?Q?…?=`).
    /// Witruimte tussen twee opeenvolgende encoded words wordt genegeerd, zoals de RFC voorschrijft.
    public static func decodeEncodedWords(_ input: String) -> String {
        let ns = NSString(string: input)
        let matches = encodedWord.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var output = ""
        var cursor = 0
        var previousWasEncoded = false

        for match in matches {
            let between = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isOnlyWhitespace = between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !(previousWasEncoded && isOnlyWhitespace) {
                output += between
            }

            let charset = ns.substring(with: match.range(at: 1))
            let method = ns.substring(with: match.range(at: 2)).uppercased()
            let payload = ns.substring(with: match.range(at: 3))

            if let bytes = decodePayload(payload, method: method),
               let decoded = string(from: bytes, charset: charset) {
                output += decoded
                previousWasEncoded = true
            } else {
                // Niet te decoderen: laat de originele tekst staan.
                output += ns.substring(with: match.range)
                previousWasEncoded = false
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    private static func decodePayload(_ payload: String, method: String) -> Data? {
        if method == "B" {
            var b64 = payload
            let remainder = b64.count % 4
            if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }
            return Data(base64Encoded: b64)
        }
        // Q-encoding: '_' is een spatie, =XX is een byte.
        var bytes = [UInt8]()
        let chars = Array(payload.utf8)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == UInt8(ascii: "_") {
                bytes.append(0x20)
                i += 1
            } else if c == UInt8(ascii: "="), i + 2 < chars.count {
                let hex = String(decoding: chars[(i + 1)...(i + 2)], as: UTF8.self)
                if let byte = UInt8(hex, radix: 16) {
                    bytes.append(byte)
                    i += 3
                } else {
                    bytes.append(c)
                    i += 1
                }
            } else {
                bytes.append(c)
                i += 1
            }
        }
        return Data(bytes)
    }

    private static func string(from data: Data, charset rawCharset: String) -> String? {
        // RFC 2231-taalaanduiding (`utf-8*nl`) negeren.
        let charset = rawCharset.split(separator: "*").first.map(String.init)?.lowercased() ?? rawCharset.lowercased()
        let encoding: String.Encoding?
        switch charset {
        case "utf-8", "utf8":                              encoding = .utf8
        case "us-ascii", "ascii":                          encoding = .ascii
        case "iso-8859-1", "latin1", "iso8859-1":          encoding = .isoLatin1
        case "iso-8859-2":                                 encoding = .isoLatin2
        case "windows-1250":                               encoding = .windowsCP1250
        case "windows-1251":                               encoding = .windowsCP1251
        case "windows-1252", "cp1252", "iso-8859-15":      encoding = .windowsCP1252
        default:                                           encoding = nil
        }
        if let encoding, let s = String(data: data, encoding: encoding) { return s }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
