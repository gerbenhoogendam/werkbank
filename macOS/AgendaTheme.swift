import SwiftUI

// De agenda zoals elk thema hem tekent: knoppen, agendafilters, dagkoppen, uurliniaal, afspraken en de lijn van nu.

/// Vorige/volgende in de agendakop.
struct AgendaNavButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch ThemeStore.shared.look {
            case .tischsuper:
                icon(size: 11, weight: .bold, color: .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(hex: 0x111111)))
            case .rekenmachine:
                icon(size: 11, weight: .bold, color: ThingsColor.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(RoundKey())
            case .principes:
                icon(size: 11, weight: .semibold, color: ThingsColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(ThingsColor.separator, lineWidth: 1))
            case .sneeuwwitje:
                // Draaiknop van de SK 4: het streepje wijst de richting.
                DialKnob(angle: symbol == "chevron.left" ? -60 : 60, size: 30)
            case .drukproef:
                Image(systemName: symbol == "chevron.left" ? "arrow.left" : "arrow.right")
                    .font(.werk(size: 15, weight: .regular))
                    .foregroundStyle(ThingsColor.today)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(ThingsColor.checkboxStroke, lineWidth: 1))
            case .spark:
                icon(size: 12, weight: .semibold, color: ThingsColor.accent)
                    .frame(width: 24, height: 24)
            case .karmijn:
                Image(systemName: symbol == "chevron.left" ? "arrow.left" : "arrow.right")
                    .font(.werk(size: 13, weight: .regular))
                    .foregroundStyle(ThingsColor.running)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(ThingsColor.separator, lineWidth: 1))
            case .wandklok:
                icon(size: 10, weight: .bold, color: ThingsColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ThingsColor.cardBackground))
                    .overlay(Circle().strokeBorder(ThingsColor.separator, lineWidth: 1))
            case .standaard:
                icon(size: 11, weight: .semibold, color: ThingsColor.textSecondary)
                    .frame(width: 22, height: 22)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    private func icon(size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.werk(size: size, weight: weight))
            .foregroundStyle(color)
    }
}

/// "Vandaag" in de agendakop.
struct AgendaTodayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch ThemeStore.shared.look {
            case .drukproef:
                Text("Vandaag")
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(ThingsColor.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .overlay(Capsule().strokeBorder(ThingsColor.today, lineWidth: 1))
            case .principes:
                Text("Vandaag")
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(ThingsColor.separator, lineWidth: 1))
            case .rekenmachine:
                Text("VANDAAG")
                    .font(.werk(size: 9.5))
                    .tracking(0.8)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(ThingsColor.tagBackground))
            case .tischsuper:
                Text("Vandaag")
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThingsColor.cardBackground))
            case .spark:
                Text("Vandaag")
                    .font(.werk(size: 11.5, weight: .medium))
                    .foregroundStyle(ThingsColor.accent)
            case .karmijn:
                KarmijnLabel(text: "Vandaag", color: ThingsColor.running)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(Rectangle().strokeBorder(ThingsColor.running, lineWidth: 1))
            case .wandklok:
                Text("Vandaag")
                    .font(.werk(size: 11, weight: .bold))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .padding(.horizontal, 4)
            case .sneeuwwitje:
                DialKnob(angle: 0, size: 30)
                    .accessibilityLabel("Vandaag")
            case .standaard:
                Text("Vandaag")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.accent)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Een agenda aan of uit in de kop.
struct AgendaCalendarChip: View {
    let title: String
    let color: Color
    let hidden: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch ThemeStore.shared.look {
        case .standaard:
            HStack(spacing: 4) {
                Image(systemName: hidden ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(color)
                label(hidden ? ThingsColor.textTertiary : ThingsColor.textSecondary)
            }
        case .wandklok, .sneeuwwitje:
            HStack(spacing: 5) {
                Circle()
                    .fill(hidden ? Color.clear : color)
                    .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                label(hidden ? ThingsColor.textTertiary : ThingsColor.textSecondary)
            }
        case .tischsuper:
            // Een pianotoets met het label eronder: aan in de kleur van de agenda, uit leeg met een rand.
            PianoKey(title: title, fill: hidden ? Color.clear : color, edge: hidden ? ThingsColor.separator : Color.clear,
                     ink: hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary, height: 14)
                .frame(width: 58)
        case .principes:
            // Een schuifknop in de kleur van de agenda, zoals op de affiche.
            HStack(spacing: 7) {
                MiniToggle(isOn: !hidden, tint: color)
                label(hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary, weight: .medium)
            }
        case .rekenmachine:
            HStack(spacing: 6) {
                RoundKey(tint: hidden ? nil : color).frame(width: 12, height: 12)
                label(ThingsColor.textSecondary)
            }
        case .drukproef:
            // Een dunne omlijnde capsule, zoals Bottom Metrics op de poster.
            HStack(spacing: 6) {
                Circle()
                    .fill(hidden ? Color.clear : color)
                    .overlay(Circle().strokeBorder(hidden ? ThingsColor.textSecondary : color, lineWidth: 1))
                    .frame(width: 6, height: 6)
                Text(title.uppercased())
                    .font(.werk(size: 10, weight: .medium))
                    .foregroundStyle(hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .overlay(Capsule().strokeBorder(hidden ? ThingsColor.separator : ThingsColor.checkboxStroke, lineWidth: 1))
        case .spark:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 13).opacity(hidden ? 0.4 : 1)
                label(hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary, size: 11.5)
            }
        case .karmijn:
            HStack(spacing: 6) {
                Rectangle()
                    .fill(hidden ? Color.clear : color)
                    .overlay(Rectangle().strokeBorder(hidden ? ThingsColor.textSecondary : color, lineWidth: 1))
                    .frame(width: 8, height: 8)
                KarmijnLabel(text: title, color: hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary)
            }
        }
    }

    private func label(_ color: Color, size: CGFloat = 11.5, weight: Font.Weight = .regular) -> some View {
        Text(title)
            .font(.werk(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Weekdag en dagnummer boven een dagkolom (alleen in een thema; Standaard tekent zijn eigen kop).
struct AgendaDayHeader: View {
    let weekday: String
    let number: String
    let isToday: Bool

    var body: some View {
        switch ThemeStore.shared.look {
        case .tischsuper:
            VStack(spacing: 3) {
                Text("\(weekday) \(number)")
                    .font(.werk(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color(hex: 0xE0E0E0) : ThingsColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isToday ? Color(hex: 0x1C1C1C) : ThingsColor.cardBackground))
                Text(isToday ? "VANDAAG" : " ")
                    .font(.werk(size: 9))
                    .tracking(0.6)
                    .foregroundStyle(ThingsColor.accent)
            }
            .padding(.horizontal, 1)
        case .principes:
            VStack(spacing: 6) {
                Rectangle().fill(ThemeParts.rule).frame(height: 2)
                HStack(spacing: 8) {
                    Text(weekday).font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                    numberView(size: 13, weight: .medium, fill: isToday ? ThingsColor.today : .clear,
                               ink: isToday ? Color.black : ThingsColor.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 3)
        case .rekenmachine:
            HStack(spacing: 8) {
                Text(weekday.uppercased()).font(.werk(size: 10)).tracking(0.8).foregroundStyle(ThingsColor.textSecondary)
                Text(number)
                    .font(.werk(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color(hex: 0x1F1D1B) : ThingsColor.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(RoundKey(tint: isToday ? ThingsColor.today : nil))
            }
            .frame(maxWidth: .infinity)
        case .drukproef:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(weekday.uppercased()).font(.werk(size: 10, weight: .medium)).foregroundStyle(ThingsColor.textPrimary)
                Text(number)
                    .font(.werkNumbers(size: 18))
                    .tracking(-0.5)
                    .foregroundStyle(isToday ? ThingsColor.today : ThingsColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .overlay(alignment: .leading) { Rectangle().fill(ThingsColor.separator).frame(width: 1) }
        case .spark:
            HStack(spacing: 6) {
                Text(weekday).font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                numberView(size: 13, weight: .semibold, fill: isToday ? ThingsColor.today : .clear,
                           ink: isToday ? Color.white : ThingsColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
        case .karmijn:
            // Het dagnummer in schreef; vandaag cursief, rood en onderstreept.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                KarmijnLabel(text: weekday)
                Text(number)
                    .font(.werkSerif(size: 22, italic: isToday, bold: isToday))
                    .foregroundStyle(isToday ? ThingsColor.running : ThingsColor.textPrimary)
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) {
                        if isToday { Rectangle().fill(ThingsColor.running).frame(height: 2) }
                    }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        case .sneeuwwitje:
            // De dagen langs een afstemschaal; op vandaag staat het houten schuifje.
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(weekday).font(.werk(size: 11)).foregroundStyle(isToday ? ThingsColor.textPrimary : ThingsColor.textSecondary)
                    Text(number)
                        .font(.werk(size: 15, weight: isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
                }
                TuningScaleCell(isToday: isToday)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
        case .wandklok:
            // Vandaag is het datumvenster van de klok: een wit vakje met een rood vlaggetje.
            HStack(spacing: 7) {
                Text(weekday).font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                if isToday {
                    DateWindow(number: number)
                } else {
                    numberView(size: 15, weight: .light, fill: .clear, ink: ThingsColor.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        case .standaard:
            HStack(spacing: 6) {
                Text(weekday).font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                numberView(size: 15, weight: isToday ? .regular : .light,
                           fill: isToday ? ThingsColor.today : .clear,
                           ink: isToday ? Color(hex: 0x1C1C1C) : ThingsColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func numberView(size: CGFloat, weight: Font.Weight, fill: Color, ink: Color) -> some View {
        Text(number)
            .font(.werk(size: size, weight: weight))
            .monospacedDigit()
            .foregroundStyle(ink)
            .frame(minWidth: 26, minHeight: 26)
            .background(Circle().fill(fill))
    }
}

/// Minuutstreepjes langs de urenkolom (Wandklok: wijzerplaat, Tischsuper: radioschaal).
struct HourRuler: View {
    let hours: Int
    let hourHeight: CGFloat

    var body: some View {
        let look = ThemeStore.shared.look
        Canvas { context, size in
            let color = look == .tischsuper ? ThingsColor.textSecondary : ThingsColor.checkboxStroke
            if look == .tischsuper {
                context.fill(Path(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height)), with: .color(color))
            }
            if look == .wandklok {
                // De minutenring: per uur een dik streepje in inkt, elke vijf minuten een dun.
                for index in 0...(hours * 12) {
                    let y = CGFloat(index) * hourHeight / 12
                    let hour = index % 12 == 0
                    context.fill(Path(CGRect(x: size.width - (hour ? 9 : 4), y: y - (hour ? 1 : 0.5),
                                             width: hour ? 9 : 4, height: hour ? 2 : 1)),
                                 with: .color(hour ? ThingsColor.textPrimary : color))
                }
                return
            }
            for index in 0...(hours * 4) {
                let y = CGFloat(index) * hourHeight / 4
                let width: CGFloat = index % 4 == 0 ? 8 : (look == .tischsuper && index % 2 == 0 ? 6 : 4)
                context.fill(Path(CGRect(x: size.width - width, y: y, width: width, height: 1)), with: .color(color))
            }
        }
        .frame(width: 10, height: CGFloat(hours) * hourHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Het vlak achter de dagkolommen (Tischsuper en Rekenmachine verzonken, Sneeuwwitje glas).
struct TimelineWell: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch ThemeStore.shared.look {
        case .tischsuper:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.tagBackground)
        case .rekenmachine:
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(ThingsColor.backgroundSidebar)
                .overlay(shape.stroke(Color.black.opacity(scheme == .dark ? 0.5 : 0.15), lineWidth: 3)
                    .blur(radius: 2).offset(y: 1.5).mask(shape))
        case .sneeuwwitje:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThingsColor.columnBackground.opacity(0.75))
                .overlay(LidSheen().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.85), lineWidth: 1))
        default:
            Color.clear
        }
    }
}

enum AgendaLook {
    /// Kleur en dikte van de lijn van nu.
    static var nowLine: (color: Color, thickness: CGFloat) {
        switch ThemeStore.shared.look {
        case .wandklok: (ThingsColor.running, 1)
        case .principes, .rekenmachine: (ThingsColor.today, 2)
        case .tischsuper: (Color(hex: 0xD93A2B), 2)
        case .sneeuwwitje: (ThingsColor.accent, 2)
        case .drukproef: (ThingsColor.today, 1)
        case .spark: (ThingsColor.deadline, 2)
        case .karmijn: (ThingsColor.running, 2)
        case .standaard: (ThingsColor.deadline, 1.5)
        }
    }

    /// Afronding van een afspraak.
    static var eventRadius: CGFloat {
        switch ThemeStore.shared.look {
        case .principes: 14
        case .rekenmachine, .sneeuwwitje: 10
        case .wandklok: 8
        case .tischsuper, .drukproef, .spark: 6
        case .standaard: 4
        case .karmijn: 0
        }
    }

    /// Afspraken als vol vlak (tekstkleur volgt het contrast) in plaats van een tint.
    static var solidEvents: Bool {
        switch ThemeStore.shared.look {
        case .principes, .rekenmachine, .drukproef, .karmijn: true
        default: false
        }
    }
}

/// Het begin van de lijn van nu, in de vorm van het thema.
struct NowMarker: View {
    let color: Color

    /// Hoogte van het merkteken (de lijn staat in het midden).
    static var size: CGFloat {
        switch ThemeStore.shared.look {
        case .karmijn: 11
        case .wandklok: 10
        case .sneeuwwitje: 12
        case .principes, .rekenmachine: 14
        default: 7
        }
    }

    var body: some View {
        switch ThemeStore.shared.look {
        case .karmijn:
            KarmijnStar().fill(color).frame(width: 11, height: 11)
        case .wandklok:
            // De gele middenas van de klok.
            Circle().fill(color).frame(width: 10, height: 10).shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        case .principes:
            // De zwarte knop met het witte stipje, met een gele rand.
            Circle().fill(Color.black)
                .overlay(alignment: .trailing) { Circle().fill(Color.white).frame(width: 3, height: 3).padding(.trailing, 3) }
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(color, lineWidth: 2).padding(-2))
        case .rekenmachine:
            RoundKey(tint: color).frame(width: 14, height: 14)
        case .sneeuwwitje:
            // Het houten schuifje van de afstemschaal.
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ThemeParts.elm)
                .frame(width: 18, height: 12)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        case .tischsuper:
            EmptyView()
        default:
            Circle().fill(color).frame(width: 7, height: 7)
        }
    }
}

/// Datumvenster van de wandklok (Wandklok): een wit vakje met een rood vlaggetje erboven.
struct DateWindow: View {
    let number: String

    var body: some View {
        VStack(spacing: 0) {
            NotchedFlag().fill(ThingsColor.deadline).frame(height: 6)
            Text(number)
                .font(.werk(size: 15))
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textPrimary)
                .padding(.top, 1)
                .padding(.bottom, 3)
        }
        .frame(width: 28)
        .background(ThemeParts.face)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ThingsColor.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
    }
}

/// Het vlaggetje van het datumvenster: een band met een inkeping onderaan.
private struct NotchedFlag: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Eén vak van de afstemschaal boven de dagen (Sneeuwwitje): de lijn, een lange streep in het midden, korte ernaast.
struct TuningScaleCell: View {
    let isToday: Bool

    var body: some View {
        Canvas { context, size in
            let color = ThingsColor.textTertiary
            let base = size.height / 2
            context.fill(Path(CGRect(x: 0, y: base, width: size.width, height: 1)), with: .color(color))
            for (index, fraction) in [0.0, 0.25, 0.5, 0.75].enumerated() {
                let major = index == 2
                let height: CGFloat = major ? size.height * 0.75 : size.height * 0.35
                let x = CGFloat(fraction) * size.width
                context.fill(Path(CGRect(x: x, y: base - height / 2 + 0.5, width: 1, height: height)), with: .color(color))
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ThemeParts.elm)
                    .frame(width: 26, height: 14)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Een platte pianotoets met het label eronder (Tischsuper), zoals ein/aus · Phono · UKW op de platenspeler.
struct PianoKey: View {
    let title: String
    let fill: Color
    var edge: Color = .clear
    var ink: Color = ThingsColor.textPrimary
    var height: CGFloat = 18

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(edge, lineWidth: 1))
                .frame(height: height)
            Text(title.uppercased())
                .font(.werk(size: 9))
                .tracking(0.5)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }
}

/// De rode naald van de afstemschaal (Tischsuper): de lijn van nu dwars over de urenschaal en alle dagen.
struct AgendaNeedle: View {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let minutes = timeline.date.timeIntervalSince(Calendar.current.startOfDay(for: timeline.date)) / 60
            let y = CGFloat(minutes / 60 - Double(startHour)) * hourHeight
            if y >= 0, y <= CGFloat(endHour - startHour) * hourHeight {
                Rectangle()
                    .fill(AgendaLook.nowLine.color)
                    .frame(height: AgendaLook.nowLine.thickness)
                    .padding(.leading, 22)
                    .offset(y: y - NowMarker.size / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
