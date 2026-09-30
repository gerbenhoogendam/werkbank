import Foundation

/// Eén afgeronde tijdregel, klaar voor export naar een facturatiesysteem.
public struct BillingLine: Equatable {
    public var date: Date
    public var client: String
    public var title: String
    public var workDescription: String
    public var minutes: Int
    public var billedHours: Double
    public var source: String

    public init(date: Date, client: String, title: String, workDescription: String,
                minutes: Int, billedHours: Double, source: String) {
        self.date = date
        self.client = client
        self.title = title
        self.workDescription = workDescription
        self.minutes = minutes
        self.billedHours = billedHours
        self.source = source
    }
}

/// Aanknopingspunt voor een latere koppeling met het facturatiesysteem.
public protocol BillingExporter {
    var fileExtension: String { get }
    func export(_ lines: [BillingLine]) throws -> Data
}

/// CSV met puntkomma als scheidingsteken en komma als decimaalteken (Excel NL),
/// UTF-8 met BOM zodat Excel de tekens goed leest.
public struct CSVBillingExporter: BillingExporter {
    public init() {}
    public var fileExtension: String { "csv" }

    public static let header = ["datum", "klant", "titel", "omschrijving", "minuten", "afgeronde uren", "bron"]

    public func export(_ lines: [BillingLine]) throws -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var rows = [Self.header.map(Self.escape).joined(separator: ";")]
        for line in lines {
            let fields = [
                formatter.string(from: line.date),
                line.client,
                line.title,
                line.workDescription,
                String(line.minutes),
                Billing.formatHours(line.billedHours),
                line.source,
            ]
            rows.append(fields.map(Self.escape).joined(separator: ";"))
        }
        let text = rows.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    static func escape(_ field: String) -> String {
        guard field.unicodeScalars.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
