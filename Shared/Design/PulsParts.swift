import SwiftUI

// Puls: zwart als een sporthorloge, grijze tegels en per soort een felle kleur die zacht in de achtergrond doorschemert.
// Kleur betekent altijd hetzelfde: groen is werk, geel loopt nu, rood is nu en vandaag, blauw is mail, cyaan is agenda,
// paars (licht: fuchsia) zijn klanten, oranje is te laat. Roze komt zo min mogelijk voor.

/// Een felle kleur van Puls, in licht en donker.
struct PulsHue {
    private let base: (light: UInt32, dark: UInt32)
    /// Vlak: staaf, ring, knop.
    let solid: Color
    /// Kleine tekst (haalt 4,5:1 op de tegel en op wit).
    let text: Color
    /// Cijfers vanaf 24 pt.
    let big: Color
    /// Het verloop van een staaf, van boven naar onder.
    let top: Color
    let bottom: Color
    /// Een label: licht een vol vlak met zwarte of witte letters, donker een tint met gekleurde letters.
    let chipFill: Color
    let chipInk: Color

    init(base: (UInt32, UInt32), solid: (UInt32, UInt32), text: (UInt32, UInt32), big: (UInt32, UInt32),
         top: (UInt32, UInt32), bottom: (UInt32, UInt32), chip: (fill: UInt32, ink: UInt32)) {
        self.base = (base.0, base.1)
        self.solid = .dynamic(light: solid.0, dark: solid.1)
        self.text = .dynamic(light: text.0, dark: text.1)
        self.big = .dynamic(light: big.0, dark: big.1)
        self.top = .dynamic(light: top.0, dark: top.1)
        self.bottom = .dynamic(light: bottom.0, dark: bottom.1)
        chipFill = .dynamic(light: chip.fill, dark: base.1, darkOpacity: 0.2)
        chipInk = .dynamic(light: chip.ink, dark: text.1)
    }

    /// De kleur met een eigen dekking per weergave (gloed, tint, spoor van een ring).
    func opacity(light: CGFloat, dark: CGFloat) -> Color {
        .dynamic(light: base.light, dark: base.dark, lightOpacity: light, darkOpacity: dark)
    }

    var tint: Color { opacity(light: 0.18, dark: 0.2) }
    var track: Color { opacity(light: 0.22, dark: 0.22) }
    var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
}

enum Puls {
    static let blauw = PulsHue(base: (0x0A5CFF, 0x0A9BF0), solid: (0x0A5CFF, 0x2FA6FF), text: (0x0050E6, 0x3AAEFF),
                               big: (0x0A5CFF, 0x3AAEFF), top: (0x4D8DFF, 0x4CCBFF), bottom: (0x0A5CFF, 0x0A9BF0),
                               chip: (0x0A5CFF, 0xFFFFFF))
    static let groen = PulsHue(base: (0x9EF500, 0x96F000), solid: (0x9EF500, 0xA6FF00), text: (0x2E8500, 0xB4FF2A),
                               big: (0x3F9600, 0xB4FF2A), top: (0xC6FF3D, 0xC6FF3D), bottom: (0x8BE800, 0x7EE000),
                               chip: (0x9EF500, 0x000000))
    static let cyaan = PulsHue(base: (0x00A6E0, 0x00CDF0), solid: (0x00B4E6, 0x00D5F0), text: (0x007BB0, 0x2CE4F5),
                               big: (0x0090C8, 0x2CE4F5), top: (0x38D6F5, 0x5EF3FF), bottom: (0x00A6E0, 0x00B8E6),
                               chip: (0x00C8F0, 0x000000))
    static let paars = PulsHue(base: (0xF0149B, 0x9687FF), solid: (0xF0149B, 0xA99CFF), text: (0xC8007A, 0xAFA3FF),
                               big: (0xE6007E, 0xAFA3FF), top: (0xFF5CC8, 0xC3BAFF), bottom: (0xF0149B, 0x8C7CFF),
                               chip: (0xD1008A, 0xFFFFFF))
    static let geel = PulsHue(base: (0xFFC300, 0xFFD60A), solid: (0xFFC300, 0xFFE21F), text: (0x8C6D00, 0xFFE21F),
                              big: (0xA07D00, 0xFFE21F), top: (0xFFE14D, 0xFFEE70), bottom: (0xFFC300, 0xFFD60A),
                              chip: (0xFFD60A, 0x000000))
    static let rood = PulsHue(base: (0xFF3B30, 0xFF3B30), solid: (0xFF3B30, 0xFF3B30), text: (0xD70015, 0xFF453A),
                              big: (0xE5241B, 0xFF453A), top: (0xFF6B5E, 0xFF6B5E), bottom: (0xFF3B30, 0xFF3B30),
                              chip: (0xE0190F, 0xFFFFFF))
    static let oranje = PulsHue(base: (0xF26B1D, 0xFF7A2E), solid: (0xF26B1D, 0xFF7A2E), text: (0xC2410C, 0xFF7A2E),
                                big: (0xD9480F, 0xFF7A2E), top: (0xFF9A4D, 0xFFA060), bottom: (0xF26B1D, 0xFF6A1A),
                                chip: (0xFF7A1A, 0x000000))

    /// Iets dieper rood voor witte letters (de datum van vandaag, het tijdlabel van nu): 4,9:1.
    static let redLabel = Color(hex: 0xE0190F)

    /// Grijs glas: knoppen in een kop en het spoor van een gesegmenteerde keuze.
    static let glass = Color.dynamic(light: 0x767680, dark: 0x767680, lightOpacity: 0.10, darkOpacity: 0.18)
    static let track = Color.dynamic(light: 0x767680, dark: 0x767680, lightOpacity: 0.12, darkOpacity: 0.24)
    /// De gekozen waarde van een gesegmenteerde keuze.
    static let segment = Color.dynamic(light: 0xFFFFFF, dark: 0x636366)
    /// De grijze cirkel achter een plus of pijltje (zoals het knopje rechtsboven op een tegel).
    static let circle = Color.dynamic(light: 0xE5E5EA, dark: 0x5A5A5F)
    static let circleGlyph = Color.dynamic(light: 0x636366, dark: 0x1C1C1E)
    /// Een lege dag in een maandbalkje.
    static let emptyDay = Color.dynamic(light: 0xE5E5EA, dark: 0x2C2C2E)

    /// Kolommen van het board krijgen om de beurt een kleur voor hun aantal.
    static func columnHue(_ index: Int) -> PulsHue {
        let hues = [blauw, rood, paars, cyaan, groen, oranje]
        return hues[((index % hues.count) + hues.count) % hues.count]
    }
}

/// Een getal met de eenheid erachter in hoofdletters, zoals "6:15 /8 U" of "7 ONGELEZEN": ronde cijfers met gelijke
/// breedte, de eenheid op 44% van de grootte, in dezelfde kleur en dikte.
struct PulsValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 24
    var color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
            Text(value)
                .font(.werkNumbers(size: size, weight: .bold))
                .kerning(-size * 0.022)
                .monospacedDigit()
            if !unit.isEmpty {
                Text(unit)
                    .font(.werkNumbers(size: max(9, size * 0.44), weight: .bold))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Een voortgangsring met een spoor in dezelfde kleur, ronde uiteinden en (vanaf 30 pt) een pijltje bij het begin.
struct PulsRing: View {
    let fraction: Double
    var hue: PulsHue
    var size: CGFloat = 34
    var lineWidth: CGFloat? = nil
    /// Twee pijltjes (Tijd schrijven) in plaats van één.
    var double = false

    var body: some View {
        let width = lineWidth ?? max(2.5, size * 0.16)
        ZStack {
            Circle().stroke(hue.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(hue.solid, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if size >= 30 {
                PulsRingArrow(double: double)
                    .stroke(Color.dynamic(light: 0xFFFFFF, dark: 0x000000),
                            style: StrokeStyle(lineWidth: max(1.2, width * 0.18), lineCap: .round, lineJoin: .round))
                    .frame(width: width * 0.62, height: width * 0.62)
                    .offset(y: -(size - width) / 2)
            }
        }
        .padding(width / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Een pijltje naar rechts (of twee), op het begin van een ring.
private struct PulsRingArrow: Shape {
    var double: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height
        let w = h * 0.45
        let starts: [CGFloat] = double ? [rect.midX - w * 0.95, rect.midX + w * 0.05] : [rect.midX - w / 2]
        for x in starts {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + w, y: rect.midY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

/// Licht dat op de achtergrond valt, niet om iets heen: een zachte ovale waas die naar buiten wegvalt.
struct PulsGlow: View {
    let hue: PulsHue
    var width: CGFloat = 470
    var height: CGFloat = 320
    /// Sterkte in het midden; licht en donker apart (donker heeft meer nodig om op zwart te lezen).
    var light: CGFloat = 0.2
    var dark: CGFloat = 0.2

    var body: some View {
        EllipticalGradient(stops: [
            .init(color: hue.opacity(light: light, dark: dark), location: 0),
            .init(color: hue.opacity(light: light * 0.4, dark: dark * 0.35), location: 0.45),
            .init(color: hue.opacity(light: 0, dark: 0), location: 1),
        ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// De afgelopen dagen als één balkje, oud links en vandaag rechts: gevuld als er die dag contact was, leeg bij stilte.
struct PulsMonthStrip: View {
    let days: [Bool]
    var filled: Color
    var empty: Color = Puls.emptyDay
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, on in
                RoundedRectangle(cornerRadius: min(2, height / 3), style: .continuous)
                    .fill(on ? filled : empty)
                    .frame(height: height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(days.filter { $0 }.count) van de laatste \(days.count) dagen contact")
    }
}

/// Staven per dag op een stippellijn (de nul), met de dag van vandaag in een halo; eronder de dagletters.
struct PulsDayBars: View {
    let values: [Double]
    let labels: [String]
    var hue: PulsHue
    /// Welke staaf vandaag is (krijgt een halo en een gekleurd label).
    var today: Int?
    var maximum: Double
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                PulsDottedLine(color: hue.opacity(light: 0.55, dark: 0.4))
                    .frame(height: 3)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2,
                                               topTrailingRadius: 4, style: .continuous)
                            .fill(hue.gradient)
                            .frame(width: 14, height: value <= 0 ? 0 : max(6, height * CGFloat(min(1, value / maximum))))
                            .shadow(color: index == today ? hue.opacity(light: 0.35, dark: 0.45) : .clear, radius: 9)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 1)
                    }
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.werk(size: 10, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(index == today ? hue.text : ThingsColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Een rij stipjes als nullijn onder staven.
struct PulsDottedLine: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 1.5
            while x < size.width {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: size.height / 2 - 1.1, width: 2.2, height: 2.2)),
                             with: .color(color))
                x += 6
            }
        }
        .allowsHitTesting(false)
    }
}

/// Een grijze cirkel met een plus of pijltje erin, zoals het knopje rechtsboven op een tegel.
struct PulsCircleIcon: View {
    let symbol: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.werk(size: size * 0.42, weight: .bold))
            .foregroundStyle(Puls.circleGlyph)
            .frame(width: size, height: size)
            .background(Circle().fill(Puls.circle))
    }
}
