import SwiftUI

// Onderdelen van het thema Diskette: een bureaucomputer uit de jaren tachtig, gezien door een hedendaagse drukproef.
// Crème papier op een platina-beige blad, één oranjerood, smalle schreefkoppen (Instrument Serif) en een paar details
// van een vroege vensteromgeving: de streepjes van een titelbalk, een vierkant knopje, een gekozen regel in omgekeerde
// kleuren. Alleen vorm, kleur en letter: geen merk, logo of afbeelding.

enum Diskette {
    /// De rand van een venster of knopje: de tekstkleur, iets teruggenomen. In donker wordt dat crème op zwart.
    static var line: Color { ThingsColor.textPrimary.opacity(0.78) }
    /// Zo breed is elk cijfer in `DisketteTime`, als deel van de lettergrootte (de breedste, de nul, is 0,46).
    static let digitWidth: CGFloat = 0.47
}

/// De streepjes van een titelbalk: dunne lijnen over de volle breedte.
struct Pinstripes: View {
    var lines = 6
    var color: Color = ThingsColor.textPrimary.opacity(0.5)

    var body: some View {
        Canvas { context, size in
            for index in 0..<max(lines, 0) {
                let line = CGRect(x: 0, y: CGFloat(index) * 2, width: size.width, height: 1)
                context.fill(Path(line), with: .color(color))
            }
        }
        .frame(minWidth: 10, maxWidth: .infinity)
        .frame(height: CGFloat(max(lines, 1)) * 2 - 1)
        .accessibilityHidden(true)
    }
}

/// Kleine kapitalen met letterafstand (weekdagen, "Loopt", bijschriften).
struct DisketteLabel: View {
    let text: String
    var color: Color = ThingsColor.textSecondary
    var size: CGFloat = 9.5

    var body: some View {
        Text(text.uppercased())
            .font(.werk(size: size, weight: .semibold))
            .tracking(size * 0.12)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Een keuze als knopje. Gekozen is omgekeerd: inkt met crème letters, zoals een gekozen regel in een vroeg menu.
struct DisketteChip: View {
    let text: String
    var isOn = false
    var size: CGFloat = 11.5

    var body: some View {
        Text(text)
            .font(.werk(size: size, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? ThingsColor.backgroundContent : ThingsColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? ThingsColor.textPrimary : Color.clear))
    }
}

/// Een vierkant knopje met een dunne rand, zoals het sluitvakje van een venster: voor de plus en de pijlen.
struct DisketteKey: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Image(systemName: symbol)
            .font(.werk(size: size * 0.45, weight: .bold))
            .foregroundStyle(ThingsColor.textPrimary)
            .frame(width: size, height: size)
            .background(shape.fill(ThingsColor.cardBackground))
            .overlay(shape.strokeBorder(Diskette.line, lineWidth: 1))
    }
}

/// Een tijd in de schreefletter met elk cijfer even breed, zodat een lopende tijd niet verspringt (de cijfers van
/// Instrument Serif zijn niet even breed).
struct DisketteTime: View {
    let text: String
    let size: CGFloat
    var color: Color = ThingsColor.today

    var body: some View {
        let slot = size * Diskette.digitWidth * ThemeStore.shared.scale
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.werkTitle(size: size))
                    .fixedSize()
                    .frame(width: character.isNumber ? slot : nil)
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Een papieren vlak met een dunne inktrand en een harde schaduw eronder, zoals een venster op een vroeg bureaublad.
struct DisketteWindow: View {
    var radius: CGFloat = 5
    var fill: Color = ThingsColor.cardBackground
    var border: Color = Diskette.line
    var lineWidth: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(fill)
            .overlay(shape.strokeBorder(border, lineWidth: lineWidth))
            .background(shape.fill(ThingsColor.cardShadow).offset(x: 1.5, y: 2))
    }
}
