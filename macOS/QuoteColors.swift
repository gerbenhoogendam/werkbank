import AppKit
import SwiftUI

/// Voorkeuren › Mail › Gesprekken: of geciteerde tekst per niveau een kleur krijgt, en welke (drie niveaus, daarna weer
/// van voren af), zoals in Apple Mail. Uit: een grijze streep en de tekstkleur van de mail zelf.
enum QuoteColors {
    static let enabledKey = "mail.quoteColorsOn"
    /// De kleuren van niveau één, twee en drie, met komma's ("purple,teal,green"); leeg: `defaults`.
    static let colorsKey = "mail.quoteColors"
    static let defaults: [QuoteColor] = [.purple, .teal, .green]

    enum QuoteColor: String, CaseIterable, Identifiable {
        case blue, green, purple, red, orange, yellow, teal, gray

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blue: "Blauw"
            case .green: "Groen"
            case .purple: "Paars"
            case .red: "Rood"
            case .orange: "Oranje"
            case .yellow: "Geel"
            case .teal: "Groenblauw"
            case .gray: "Grijs"
            }
        }

        /// De streep, zoals in Apple Mail.
        var bar: String {
            switch self {
            case .blue: "#007AFF"
            case .green: "#5ABE32"
            case .purple: "#5856D6"
            case .red: "#FF3B30"
            case .orange: "#FF9500"
            case .yellow: "#FFCC00"
            case .teal: "#4AA9C9"
            case .gray: "#8E8E93"
            }
        }

        /// De tekst: donker genoeg voor de witte mail (minstens 4,5:1).
        var text: String {
            switch self {
            case .blue: "#1F5FC9"
            case .green: "#2E7D1A"
            case .purple: "#5856D6"
            case .red: "#C0261C"
            case .orange: "#B25E00"
            case .yellow: "#8A6D00"
            case .teal: "#1E7A99"
            case .gray: "#5F5F64"
            }
        }
    }

    static func colors(from raw: String) -> [QuoteColor] {
        let parsed = raw.split(separator: ",").compactMap { QuoteColor(rawValue: String($0)) }
        return parsed.count == 3 ? parsed : defaults
    }

    static func raw(_ colors: [QuoteColor]) -> String { colors.map(\.rawValue).joined(separator: ",") }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var current: [QuoteColor] { colors(from: UserDefaults.standard.string(forKey: colorsKey) ?? "") }

    /// Verandert als de keuze verandert: open mails worden dan opnieuw getekend.
    static var signature: String { (isEnabled ? "aan:" : "uit:") + raw(current) }

    /// CSS voor zes niveaus `quote` (een selector voor één citaatblok), ook over een streep en grijze tekst die de
    /// afzender zelf gaf; tekst die zelf een kleur heeft, houdt die.
    static func css(quote: String) -> String {
        let enabled = isEnabled
        let chosen = current
        return (1...6).map { level -> String in
            let selector = Array(repeating: quote, count: level).joined(separator: " ")
            let color = chosen[(level - 1) % chosen.count]
            let bar = enabled ? color.bar : "#C8C8CC"
            let text = enabled ? "color: \(color.text) !important; " : ""
            return "\(selector) { margin: 8px 0 8px 2px !important; padding: 0 0 0 12px !important; "
                + "border: none !important; border-left: 2px solid \(bar) !important; \(text)}"
        }.joined(separator: "\n")
    }

    /// Een gekleurd vierkantje voor in het keuzemenu (menu's tonen SF Symbols alleen in één kleur).
    static func swatch(_ color: QuoteColor) -> NSImage {
        let size = NSSize(width: 22, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            NSColor(hexString: color.bar).setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Voorkeuren › Mail › Gesprekken: de kleuren van citaten.
struct QuoteColorsSection: View {
    @AppStorage(QuoteColors.enabledKey) private var enabled = true
    @AppStorage(QuoteColors.colorsKey) private var raw = ""

    var body: some View {
        Toggle("Ken kleur toe aan geciteerde tekst", isOn: $enabled)
        ForEach(0..<3, id: \.self) { level in
            Picker("Niveau \(level + 1)", selection: binding(level)) {
                ForEach(QuoteColors.QuoteColor.allCases) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: QuoteColors.swatch(color)) }
                        .tag(color)
                }
            }
            .disabled(!enabled)
        }
    }

    private func binding(_ level: Int) -> Binding<QuoteColors.QuoteColor> {
        Binding(get: { QuoteColors.colors(from: raw)[level] }, set: { color in
            var colors = QuoteColors.colors(from: raw)
            colors[level] = color
            raw = QuoteColors.raw(colors)
        })
    }
}

private extension NSColor {
    /// "#5856D6"
    convenience init(hexString: String) {
        let value = UInt32(hexString.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
