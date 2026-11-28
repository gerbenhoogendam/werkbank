import SwiftUI

// Onderdelen van het thema Etiket: zwart (of gebroken wit) met één fel limoen, strak en rechthoekig, smalle kapitalen
// voor koppen en cijfers (Bebas Neue) en kleine kapitalen met een streepje ervoor als bijschrift. Limoen staat alleen
// als vlak met inkt erop of als lijn op zwart: als tekst op licht is het onleesbaar, daar is het olijfgroen (`accent`).

enum Etiket {
    static let limeHex: UInt32 = 0xD4FF1E
    static let oliveHex: UInt32 = 0x4F5E00
    /// Etiket blauw: blauw in plaats van limoen, donkerblauw in plaats van olijf.
    static let blueHex: UInt32 = 0x2EC5FF
    static let navyHex: UInt32 = 0x004E73
    static let inkHex: UInt32 = 0x0B0B0B
    static var isBlue: Bool { ThemeStore.shared.theme.id == WerkbankTheme.etiketBlauw.id }
    /// Het limoen (of blauw) als vlak; wat erop staat is altijd `ink`.
    static var lime: Color { Color(hex: isBlue ? blueHex : limeHex) }
    /// Olijf (of donkerblauw): het accent als tekst of lijn op licht.
    static var olive: Color { Color(hex: isBlue ? navyHex : oliveHex) }
    static var ink: Color { Color(hex: inkHex) }
    /// De rand van een knopje of veld: iets sterker dan de haarlijn.
    static var edge: Color { ThingsColor.textPrimary.opacity(0.18) }
}

/// Een bijschrift: een kort streepje en kleine kapitalen, in de accentkleur ("—— 3 ONGELEZEN").
struct EtiketEyebrow: View {
    let text: String
    var color: Color = ThingsColor.accent
    var line: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: line, height: 1).accessibilityHidden(true)
            Text(text.uppercased())
                .font(.werk(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

/// Kleine kapitalen met letterafstand (weekdagen, "Totaal", klantnamen).
struct EtiketLabel: View {
    let text: String
    var color: Color = ThingsColor.textSecondary
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.werk(size: size, weight: .semibold))
            .tracking(size * 0.12)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Een vierkant knopje met een dunne rand (de plus in een kolom, de pijlen in de agenda).
struct EtiketKey: View {
    let symbol: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.werk(size: size * 0.4, weight: .semibold))
            .foregroundStyle(ThingsColor.accent)
            .frame(width: size, height: size)
            .overlay(Rectangle().strokeBorder(Etiket.edge, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Twee limoen blokjes op de hoeken linksboven en rechtsonder: wat nu loopt. In licht met een olijfgroene rand, anders
/// verdwijnt het limoen tegen het wit.
struct EtiketCorners: View {
    var size: CGFloat = 7
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -size / 2, y: -size / 2)
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: size / 2, y: size / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        Rectangle().fill(Etiket.lime)
            .overlay(Rectangle().strokeBorder(Etiket.olive, lineWidth: scheme == .dark ? 0 : 1))
            .frame(width: size, height: size)
    }
}
