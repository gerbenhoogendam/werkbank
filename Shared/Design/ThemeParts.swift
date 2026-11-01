import SwiftUI

// Kleine onderdelen die per thema anders getekend worden (zie de schetsen in de canvas "Werkbank thema's").

/// Kop van een onderdeel (kolom, Tijd schrijven, Mail, Agenda) met een aantal of toelichting erachter.
struct ThemedHeading: View {
    let title: String
    var count: Int?
    /// Toelichting in plaats van een aantal ("Nog te factureren").
    var detail: String?
    var baseSize: CGFloat = 13
    /// Er loopt iets in deze kolom (Drukproef: het telcijfer wordt rood).
    var highlight = false
    /// Puls: de kleur van het aantal (elke kolom zijn eigen kleur).
    var tint: Color? = nil
    /// Puls: de eenheid achter het aantal ("KAARTEN").
    var unit: String? = nil

    private var look: ThemeLook { ThemeStore.shared.look }

    var body: some View {
        switch look {
        case .karmijn:
            // Smalle rode kapitalen met het aantal in cursieve schreef erachter.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(.werkDisplay(size: 28))
                    .foregroundStyle(ThingsColor.today)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .displayTight(28)
                if let count {
                    Text("\(count)")
                        .font(.werkSerif(size: 20, italic: true))
                        .foregroundStyle(ThingsColor.textPrimary)
                } else if let detail {
                    KarmijnLabel(text: detail)
                }
            }
        case .drukproef where count != nil:
            // Het aantal groot in Michroma rechtsboven, zoals 01 op een dia.
            HStack(alignment: .top, spacing: 10) {
                Text(title.uppercased())
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(ThingsColor.textPrimary)
                Spacer(minLength: 4)
                Text(String(format: "%02d", count ?? 0))
                    .font(.werkNumbers(size: 26))
                    .tracking(-1)
                    .foregroundStyle(highlight ? ThingsColor.today : ThingsColor.checkboxStroke)
            }
        case .drukproef:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased())
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(ThingsColor.textPrimary)
                if let count {
                    Text("(N°\(String(format: "%02d", count)))")
                        .font(.werk(size: 11))
                        .foregroundStyle(ThingsColor.textSecondary)
                } else if let detail {
                    Text(detail.uppercased())
                        .font(.werk(size: 11))
                        .foregroundStyle(ThingsColor.textSecondary)
                }
            }
        case .rekenmachine:
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.werk(size: 10))
                    .tracking(1)
                    .foregroundStyle(ThingsColor.textSecondary)
                if let count {
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.werk(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(RoundKey())
                }
            }
        case .spark:
            HStack(spacing: 7) {
                // Het uitklapijltje van de secties in de zijbalk van Spark.
                Image(systemName: "chevron.down")
                    .font(.werk(size: 8, weight: .bold))
                    .foregroundStyle(ThingsColor.textSecondary)
                Text(title.uppercased())
                    .font(.werk(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(ThingsColor.textSecondary)
                if let count { CountBadge(count: count) }
            }
        case .principes:
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(ThemeParts.rule).frame(height: 2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.werk(size: baseSize + 2, weight: .medium))
                        .foregroundStyle(ThingsColor.textPrimary)
                    if let count {
                        Text("\(count)")
                            .font(.werk(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(ThingsColor.textTertiary)
                    }
                }
            }
        case .tischsuper:
            SuperscriptTitle(title: title, superscript: count.map { "\($0)" } ?? detail ?? "")
        case .telemetrie:
            // Smalle kapitalen zoals de paneelkoppen van een besturingsscherm; het aantal met een voorloopnul, oranje als er
            // iets loopt.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(.werkNumbers(size: baseSize + 1, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                if let count {
                    Text(String(format: "%02d", count))
                        .font(.werkNumbers(size: baseSize + 1, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(highlight ? ThingsColor.running : ThingsColor.textTertiary)
                } else if let detail {
                    HUDLabel(text: detail)
                }
            }
        case .viertakt:
            // Een kort rood streepje erboven en de titel strak, met het aantal achter een rode punt ("Inbox · 12").
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(ThingsColor.today).frame(width: 22, height: 3)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .font(.werk(size: baseSize + 3, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    if let count {
                        Text("·")
                            .font(.werk(size: baseSize + 3, weight: .bold))
                            .foregroundStyle(ThingsColor.today)
                        Text("\(count)")
                            .font(.werk(size: baseSize + 3))
                            .monospacedDigit()
                            .foregroundStyle(highlight ? ThingsColor.running : ThingsColor.textSecondary)
                    } else if let detail {
                        EngineLabel(text: detail)
                    }
                }
            }
        case .puls:
            // De titel halfvet; het aantal groot en rond in de kleur van de kolom, met de eenheid erachter.
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.werk(size: baseSize + 2, weight: .semibold))
                    .kerning(-0.1)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                if let count {
                    PulsValue(value: "\(count)", unit: unit ?? "", size: 22, color: tint ?? Puls.blauw.big)
                } else if let detail {
                    Text(detail)
                        .font(.werk(size: 12))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                }
            }
        case .sneeuwwitje:
            // Rechts een paar luidsprekersleuven, zoals in de kast van de SK 4.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.werk(size: baseSize - 1.5, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                if let count {
                    Text("\(count)")
                        .font(.werk(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textTertiary)
                }
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(ThingsColor.textTertiary.opacity(0.6)).frame(height: 1.5)
                    }
                }
                .frame(width: 16)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                .accessibilityHidden(true)
            }
        case .wandklok:
            // Vet en strak zoals de koppen van het horlogeblad; het aantal dun erachter.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title)
                    .font(.werk(size: baseSize + 2, weight: .bold))
                    .kerning(-0.25)
                    .foregroundStyle(ThingsColor.textPrimary)
                if let count {
                    Text("\(count)")
                        .font(.werk(size: baseSize - 1.5, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textTertiary)
                }
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.werk(size: baseSize - 1.5, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                if let count {
                    Text("\(count)")
                        .font(.werk(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textTertiary)
                }
            }
        }
    }
}

/// Blauwe teller (Spark).
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.werk(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .frame(minWidth: 20)
            .background(Capsule().fill(ThingsColor.today))
    }
}

/// Bolle ronde toets (Rekenmachine).
struct RoundKey: View {
    var tint: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(fill)
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 1.5, y: 1)
            .overlay(Circle().strokeBorder(Color.white.opacity(scheme == .dark ? 0.06 : 0.6), lineWidth: 0.5))
    }

    private var fill: some ShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }
        let colors = scheme == .dark
            ? [Color(hex: 0x45403B), Color(hex: 0x2C2825)]
            : [Color(hex: 0xFFFFFF), Color(hex: 0xE2DED8)]
        return AnyShapeStyle(RadialGradient(colors: colors, center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 18))
    }
}

/// Grijsgroen schermpje (Rekenmachine): timer, totaal, "loopt".
struct LCDPanel<Content: View>: View {
    var radius: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(ThemeParts.lcdInk)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(ThemeParts.lcd)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
                            .blur(radius: 1.5)
                            .offset(y: 1)
                            .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
            )
    }
}

/// Schuifknop van de poster (Principes): zwarte knop met wit stipje, rechts in een spoor.
struct ToggleKnob: View {
    var height: CGFloat = 24

    var body: some View {
        Capsule()
            .fill(Color.black.opacity(0.14))
            .frame(width: height * 1.8, height: height)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(Color.black)
                    .padding(2)
                    .overlay(alignment: .trailing) {
                        Circle().fill(Color.white)
                            .frame(width: height * 0.18, height: height * 0.18)
                            .padding(.trailing, height * 0.3)
                    }
            }
    }
}

/// Speakerroostertje (Sneeuwwitje).
struct GrilleMark: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle().fill(ThingsColor.textTertiary).frame(height: 1.5)
            }
        }
        .padding(.horizontal, 7)
        .frame(width: 34, height: 26)
        .background(Capsule().fill(ThingsColor.tagBackground))
    }
}

// MARK: - Wandklok

/// Kleine wijzerplaat (Wandklok): twaalf streepjes, grafiet wijzers en een gele secondewijzer; de wijzers tonen de
/// verstreken tijd van de timer.
struct ClockFace: View {
    let elapsed: TimeInterval
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, area in
            let radius = min(area.width, area.height) / 2
            let center = CGPoint(x: area.width / 2, y: area.height / 2)
            func point(_ angle: Double, _ length: CGFloat) -> CGPoint {
                CGPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
            }
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(ThemeParts.face))
            context.stroke(Path(ellipseIn: disc.insetBy(dx: 0.5, dy: 0.5)), with: .color(ThingsColor.separator), lineWidth: 1)
            var ticks = Path()
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6
                ticks.move(to: point(angle, radius * (index % 3 == 0 ? 0.66 : 0.76)))
                ticks.addLine(to: point(angle, radius * 0.9))
            }
            context.stroke(ticks, with: .color(ThingsColor.textPrimary), lineWidth: max(1, radius * 0.08))
            let total = max(0, elapsed)
            let seconds = total.truncatingRemainder(dividingBy: 60)
            let minutes = (total / 60).truncatingRemainder(dividingBy: 60)
            let hours = (total / 3600).truncatingRemainder(dividingBy: 12)
            func hand(_ angle: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
                var path = Path()
                path.move(to: center)
                path.addLine(to: point(angle, length))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(hours * .pi / 6, radius * 0.5, radius * 0.11, ThemeParts.graphite)
            hand(minutes * .pi / 30, radius * 0.74, radius * 0.11, ThemeParts.graphite)
            hand(floor(seconds) * .pi / 30, radius * 0.82, max(0.8, radius * 0.05), ThingsColor.running)
            let cap = radius * 0.15
            context.fill(Path(ellipseIn: CGRect(x: center.x - cap, y: center.y - cap, width: cap * 2, height: cap * 2)),
                         with: .color(ThingsColor.running))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Een korte lijn en dan de tekst (Wandklok), zoals "——— available for" op het horlogeblad.
struct DashLabel: View {
    let text: String
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(ThingsColor.textPrimary).frame(width: 24, height: 1)
            Text(text)
                .font(.werk(size: size))
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Tischsuper

/// Titel met het aantal of de datum klein en licht erboven, zoals ¹⁹⁶³ naast "Tischsuper RT 20" (Tischsuper).
struct SuperscriptTitle: View {
    let title: String
    let superscript: String
    var size: CGFloat = 17

    var body: some View {
        (Text(title).font(.werk(size: size, weight: .medium)).kerning(-0.3)
            + Text(superscript.isEmpty ? "" : " " + superscript)
                .font(.werk(size: 10, weight: .light))
                .baselineOffset(size * 0.5)
                .foregroundColor(ThingsColor.textSecondary))
            .foregroundStyle(ThingsColor.textPrimary)
            .lineLimit(1)
    }
}

/// Rooster van de luidspreker (Tischsuper in de timerpil): een paar horizontale streepjes.
struct SpeakerGrille: View {
    var lines = 5
    var color: Color
    var width: CGFloat = 22

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<lines, id: \.self) { _ in
                Rectangle().fill(color).frame(height: 1.5)
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

// MARK: - Principes

/// Kop met een regel erboven (Principes); twee naast elkaar vormen de koppen van de affiche.
struct RuledHeading: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(ThemeParts.rule).frame(height: 2)
            Text(text)
                .font(.werk(size: size, weight: .semibold))
                .foregroundStyle(ThingsColor.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Luidsprekerrooster van de affiche (Principes): twee kolommen afgeronde streepjes, in het midden iets ingesprongen.
struct PosterGrille: View {
    var rows = 8
    var color: Color
    var columnWidth: CGFloat = 26

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 3) {
                    ForEach(0..<rows, id: \.self) { row in
                        Capsule().fill(color)
                            .frame(height: 3)
                            .padding(.horizontal, row == rows / 2 - 1 || row == rows / 2 ? 3 : 0)
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Kleine schuifknop (Principes): aan = gekleurd spoor met de zwarte knop rechts, uit = grijs spoor met de knop links.
struct MiniToggle: View {
    let isOn: Bool
    let tint: Color
    var height: CGFloat = 17

    var body: some View {
        Capsule()
            .fill(isOn ? tint : ThingsColor.separator)
            .frame(width: height * 1.8, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.black : ThingsColor.textTertiary)
                    .frame(width: height - 3, height: height - 3)
                    .overlay(alignment: .trailing) {
                        if isOn {
                            Circle().fill(Color.white)
                                .frame(width: height * 0.18, height: height * 0.18)
                                .padding(.trailing, height * 0.2)
                        }
                    }
                    .padding(1.5)
            }
    }
}

// MARK: - Sneeuwwitje

/// Witte draaiknop met een streepje dat de richting wijst (Sneeuwwitje, de knoppen van de SK 4).
struct DialKnob: View {
    var angle: Double = 0
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: scheme == .dark ? [Color(hex: 0x3A3733), Color(hex: 0x2A2825)]
                                                         : [Color.white, Color(hex: 0xE6E2DB)],
                                 center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: size * 0.6))
            .overlay(Circle().strokeBorder(scheme == .dark ? Color(hex: 0x3E3A35) : Color(hex: 0xD9D4CB), lineWidth: 1))
            .overlay {
                Capsule()
                    .fill(ThingsColor.textPrimary)
                    .frame(width: 2, height: size * 0.3)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 1, y: 1)
    }
}

/// Schuine glans linksboven, alsof er een glazen deksel op ligt (Sneeuwwitje).
struct LidSheen: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(stops: [.init(color: .white.opacity(scheme == .dark ? 0.06 : 0.55), location: 0),
                               .init(color: .white.opacity(0), location: 0.38)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .allowsHitTesting(false)
    }
}

/// Afstemschaal met een lichthouten schuifje (Sneeuwwitje): het totaal op 0–8 uur, of hoe ver het uur van een timer is.
struct TuningBar: View {
    /// Plaats van het schuifje, 0…1.
    let fraction: Double
    var sections = 4
    var ticksPerSection = 4
    var labels: [String] = []
    var height: CGFloat = 13

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let line = ThingsColor.textTertiary
                let base = size.height * 0.55
                context.fill(Path(CGRect(x: 0, y: base, width: size.width, height: 1)), with: .color(line))
                let count = sections * ticksPerSection
                for index in 0...count {
                    let x = min(size.width - 1, CGFloat(index) / CGFloat(count) * size.width)
                    let major = index % ticksPerSection == 0
                    let top = major ? size.height * 0.1 : size.height * 0.3
                    let bottom = major ? size.height * 0.9 : size.height * 0.75
                    context.fill(Path(CGRect(x: x, y: top, width: 1, height: bottom - top)), with: .color(line))
                }
            }
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ThemeParts.elm)
                        .frame(width: 5, height: height)
                        .offset(x: geo.size.width * min(max(fraction, 0), 1) - 2.5)
                }
            }
            if !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.werk(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(ThingsColor.textTertiary)
                            .frame(maxWidth: .infinity,
                                   alignment: index == 0 ? .leading : (index == labels.count - 1 ? .trailing : .center))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rekenmachine

/// Lcd-cijfers (Rekenmachine): DSEG7 op het grijsgroene scherm, met de uitgeschakelde segmenten zwak zichtbaar.
struct LCDDigits: View {
    let text: String
    var size: CGFloat = 20

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(String(text.map { $0.isNumber ? "8" : $0 }))
                .foregroundStyle(ThemeParts.lcdInk.opacity(0.08))
            Text(text)
                .foregroundStyle(ThemeParts.lcdInk)
        }
        .font(.werkLCD(size: size))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Ronde toets met een teken (Rekenmachine); de gele is de =-toets.
struct CalcKey: View {
    let label: String
    var yellow = false
    var size: CGFloat = 30

    var body: some View {
        Text(label)
            .font(.werk(size: size * 0.48, weight: .medium))
            .foregroundStyle(yellow ? Color(hex: 0x1F1D1B) : ThingsColor.textPrimary)
            .frame(width: size, height: size)
            .background(RoundKey(tint: yellow ? ThingsColor.today : nil))
    }
}

// MARK: - Drukproef

/// Geluidsgolf van dunne staafjes (Drukproef): wat loopt. `phase` schuift het patroon elke seconde op.
struct Waveform: View {
    var count = 14
    var height: CGFloat = 22
    var phase = 0
    var color: Color = ThingsColor.today

    private static let pattern: [CGFloat] = [0.25, 0.58, 0.38, 0.83, 0.5, 1, 0.33, 0.7, 0.92, 0.42, 0.62, 0.25,
                                             0.79, 0.46, 0.96, 0.38, 0.58, 0.83, 0.29, 0.67, 0.5, 1, 0.42, 0.75]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(color)
                    .frame(width: 1.5, height: height * Self.pattern[(index + phase) % Self.pattern.count])
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Getallen als woord voor de koppen van Drukproef ("Twaalf nieuw -").
enum DutchNumber {
    private static let words = ["Geen", "Eén", "Twee", "Drie", "Vier", "Vijf", "Zes", "Zeven", "Acht", "Negen", "Tien",
                                "Elf", "Twaalf", "Dertien", "Veertien", "Vijftien", "Zestien", "Zeventien", "Achttien",
                                "Negentien", "Twintig"]

    /// "Twaalf" voor 12; boven twintig het getal zelf.
    static func word(_ number: Int) -> String {
        number >= 0 && number < words.count ? words[number] : "\(number)"
    }
}

/// Klein label in kapitalen met ruime letterafstand (Karmijn): "MAIL / 12 ONGELEZEN".
struct KarmijnLabel: View {
    let text: String
    var color: Color = ThingsColor.textSecondary
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.werk(size: size))
            .tracking(size * 0.14)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

extension View {
    /// Anton heeft veel ruimte boven en onder de kapitalen; dit trekt de regel strak om de letters, zoals de koppen
    /// van de affiche (`size` is de maat die aan `werkDisplay` is gegeven).
    func displayTight(_ size: CGFloat) -> some View {
        padding(.vertical, -size * ThemeStore.shared.scale * 0.27)
    }
}

/// Vierpuntige ster van de affiche (Karmijn): bij ongelezen mail en aan het begin van de lijn van nu.
struct KarmijnStar: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.5, 0))
        path.addLine(to: point(0.6, 0.4))
        path.addLine(to: point(1, 0.5))
        path.addLine(to: point(0.6, 0.6))
        path.addLine(to: point(0.5, 1))
        path.addLine(to: point(0.4, 0.6))
        path.addLine(to: point(0, 0.5))
        path.addLine(to: point(0.4, 0.4))
        path.closeSubpath()
        return path
    }
}

/// Rode gloed linksboven achter het bord (Karmijn), de enige diepte in dat thema.
struct KarmijnGlow: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        EllipticalGradient(colors: [ThemeParts.karmijn.opacity(scheme == .dark ? 0.55 : 0.12), .clear],
                           center: UnitPoint(x: 0.18, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.75)
            .allowsHitTesting(false)
    }
}

// MARK: - Telemetrie

/// Rechthoek met de rechterbovenhoek schuin afgesneden, zoals de panelen van een besturingsscherm (Telemetrie).
struct ChamferedRect: InsettableShape {
    var cut: CGFloat = 12
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: inset, dy: inset)
        let corner = min(cut, frame.width / 2, frame.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - corner, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + corner))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ChamferedRect {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// Vier hoekjes zoals in een zoeker (Telemetrie): om knoppen, de gekozen mailbox en de lopende kaart.
struct CornerBrackets: Shape {
    var length: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let size = min(length, rect.width / 3, rect.height / 3)
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1), (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * size, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * size))
        }
        return path
    }
}

/// Een rij vierkantjes, gevuld tot `fraction` (Telemetrie), zoals de balk "propulsion load".
struct SegmentBar: View {
    let fraction: Double
    var segments = 20
    var height: CGFloat = 8
    var color: Color = ThingsColor.running

    var body: some View {
        let filled = Int((min(max(fraction, 0), 1) * Double(segments)).rounded(.up))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Color.clear)
                    .overlay(Rectangle().strokeBorder(index < filled ? color : ThingsColor.checkboxStroke, lineWidth: 1))
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Klein label in smalle kapitalen met veel letterafstand (Telemetrie): "STATUS", "TE FACTUREREN".
struct HUDLabel: View {
    let text: String
    var color: Color = ThingsColor.textSecondary
    var size: CGFloat = 9.5

    var body: some View {
        Text(text.uppercased())
            .font(.werkNumbers(size: size, weight: .semibold))
            .tracking(size * 0.16)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Het ruitje voor "ACTIVE" (Telemetrie): wat loopt, ongelezen mail en het begin van de lijn van nu.
struct HUDDiamond: View {
    var size: CGFloat = 7
    var color: Color = ThingsColor.running

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size * 0.72, height: size * 0.72)
            .rotationEffect(.degrees(45))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Viertakt

/// Klein label in kapitalen met ruime letterafstand (Viertakt): "SLIDER-CRANK", "REV / MIN".
struct EngineLabel: View {
    let text: String
    var color: Color = ThingsColor.textSecondary
    var size: CGFloat = 9.5
    var weight: Font.Weight = .medium

    var body: some View {
        Text(text.uppercased())
            .font(.werk(size: size, weight: weight))
            .tracking(size * 0.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Toerenteller (Viertakt): een dunne lijn met een kort, dik rood stuk, zoals onder "1881".
struct RevGauge: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                Rectangle()
                    .fill(ThingsColor.running)
                    .frame(width: max(height * 2, geo.size.width * min(max(fraction, 0), 1)), height: height)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Rechthoekige knop van het bedieningspaneel (Viertakt): zwart als gekozen, rood als aan, anders alleen tekst.
struct EngineChip: View {
    enum Style { case plain, selected, on }

    let text: String
    var style: Style = .plain
    var size: CGFloat = 9.5

    var body: some View {
        Text(text.uppercased())
            .font(.werk(size: size, weight: .bold))
            .tracking(size * 0.1)
            .foregroundStyle(style == .plain ? ThingsColor.textPrimary : (style == .on ? Color.white : ThingsColor.window))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Rectangle().fill(style == .selected ? ThingsColor.textPrimary
                                         : (style == .on ? ThingsColor.running : Color.clear)))
    }
}

/// Genummerd rondje van de ontstekingsvolgorde (Viertakt): rood gevuld als het aan de beurt is.
struct FiringDot: View {
    let text: String
    var isOn = false
    var size: CGFloat = 26

    var body: some View {
        Text(text)
            .font(.werk(size: size * 0.42, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
            .frame(minWidth: size, minHeight: size)
            .background(Circle().fill(isOn ? ThingsColor.running : ThingsColor.cardBackground))
            .overlay(Circle().strokeBorder(isOn ? ThingsColor.running.opacity(0.35) : ThingsColor.separator,
                                           lineWidth: isOn ? 3 : 1).padding(isOn ? -2 : 0))
    }
}

enum ThemeParts {
    /// Lijn boven een kopje (Principes).
    static let rule = Color.dynamic(light: 0x000000, dark: 0x5A5A5A)
    static let lcd = Color(hex: 0xB5B9A8)
    static let lcdInk = Color(hex: 0x1E1F1A)
    static let lcdLabel = Color(hex: 0x3E4137)
    /// Oranje van de kolomkop (Tischsuper).
    static let orange = Color(hex: 0xFE6217)
    static let teak = Color.dynamic(light: 0xAE6630, dark: 0xC27A44)
    /// Kleur per mailbox (Spark): blauw, groen, oranje, daarna weer van voren af.
    static let mailboxColors: [Color] = [Color(hex: 0x2F7CF6), Color(hex: 0x34C759), Color(hex: 0xF5A623), Color(hex: 0xAF52DE)]
    /// Karmijnrood voor kaders en knoppen (Karmijn); rode tekst op zwart is lichter (de rollen Vandaag en Loopt nu).
    static let karmijn = Color(hex: 0x85051F)
    /// Crème op een rood vlak (Karmijn).
    static let creme = Color(hex: 0xF1E8D8)
    /// Wijzerplaat en datumvenster (Wandklok).
    static let face = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2A2A)
    /// Wijzers en knoppen (Wandklok).
    static let graphite = Color.dynamic(light: 0x3C3C3C, dark: 0xE6E6E6)
    /// Gele tekst (Wandklok): in licht een donkerder goud zodat de seconden leesbaar blijven.
    static let handText = Color.dynamic(light: 0xC9961A, dark: 0xF0C030)
    /// Lichthout (Sneeuwwitje): het schuifje en de uiteinden.
    static let elm = Color.dynamic(light: 0xD6B588, dark: 0xC9A574)
    static let elmGrain = LinearGradient(colors: [Color(hex: 0xCDA978), Color(hex: 0xE2C499), Color(hex: 0xD2B080)],
                                         startPoint: .leading, endPoint: .trailing)
    /// Regel tussen de rijen (Principes), dunner van kleur dan de kopregel.
    static let rowRule = Color.dynamic(light: 0xD2D2D2, dark: 0x2E2E2E)

    /// "Klant: Bakkerij Smit": label in inkt, waarde grijs (Tischsuper, de voetregel van het RT 20-blad).
    static func labelValue(_ label: String, _ value: String, size: CGFloat = 11) -> Text {
        Text(label + ": ").font(.werk(size: size)).foregroundColor(ThingsColor.textPrimary)
            + Text(value).font(.werk(size: size)).foregroundColor(ThingsColor.textSecondary)
    }

    /// "12 / 48": vet getal, dun totaal (Tischsuper, de paginateller van het blad).
    static func counter(_ value: Int, _ total: Int, size: CGFloat = 15, ink: Color = ThingsColor.textPrimary,
                        secondary: Color = ThingsColor.textSecondary) -> Text {
        Text("\(value)").font(.werk(size: size, weight: .semibold)).foregroundColor(ink)
            + Text(" / \(total)").font(.werk(size: size, weight: .light)).foregroundColor(secondary)
    }

    /// "0:42:17" met de seconden in goud (Wandklok: de seconden zijn de gele wijzer).
    static func secondsTinted(_ time: String) -> Text {
        guard let split = time.lastIndex(of: ":"), time.filter({ $0 == ":" }).count == 2 else { return Text(time) }
        return Text(String(time[..<split])) + Text(String(time[split...])).foregroundColor(handText)
    }
}

/// Houtfineer (Tischsuper): de kast van de RT 20, notenhout met een rustige nerf in de lengte. Altijd dezelfde nerf
/// (vaste startwaarde), zodat hij niet verspringt.
struct Veneer: View {
    /// Nerf van boven naar beneden (een zijkant) in plaats van van links naar rechts.
    var vertical = false

    private static let tones = [Color(hex: 0x5E3A20), Color(hex: 0x7A4C2B), Color(hex: 0x6A4224), Color(hex: 0x86563A),
                                Color(hex: 0x6E4527), Color(hex: 0x5C381F)]

    var body: some View {
        Canvas { context, size in
            let length = vertical ? size.height : size.width
            let across = vertical ? size.width : size.height
            let start = CGPoint.zero
            let end = vertical ? CGPoint(x: size.width * 0.35, y: size.height) : CGPoint(x: size.width, y: size.height * 0.35)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: Self.tones), startPoint: start, endPoint: end))
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func random() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            var offset = 0.0
            while offset < across + 4 {
                let amplitude = 0.4 + random() * 1.6
                let frequency = 0.004 + random() * 0.012
                let phase = random() * .pi * 2
                var path = Path()
                var t = 0.0
                while t <= length + 8 {
                    let wave = offset + amplitude * sin(t * frequency * .pi * 2 + phase)
                    let point = vertical ? CGPoint(x: wave, y: t) : CGPoint(x: t, y: wave)
                    if t == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    t += 8
                }
                let light = random() < 0.3
                context.stroke(path, with: .color(light ? Color.white.opacity(0.05 + random() * 0.05)
                                                        : Color.black.opacity(0.07 + random() * 0.09)),
                               lineWidth: 0.5 + random() * 0.9)
                offset += 1.6 + random() * 2.4
            }
            // Een zachte glans, alsof er lak op zit.
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color.white.opacity(0.07), .clear, Color.black.opacity(0.08)]),
                                               startPoint: .zero,
                                               endPoint: vertical ? CGPoint(x: size.width, y: 0) : CGPoint(x: 0, y: size.height)))
        }
        .accessibilityHidden(true)
    }
}
