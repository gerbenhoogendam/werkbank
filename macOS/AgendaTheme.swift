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
                icon(size: 11, weight: .semibold, color: ThingsColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ThingsColor.cardBackground))
                    .overlay(Circle().strokeBorder(ThingsColor.separator, lineWidth: 1))
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
            case .wandklok, .standaard:
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
            case .wandklok, .sneeuwwitje:
                Text("Vandaag")
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .padding(.horizontal, 4)
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
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8).opacity(hidden ? 0.4 : 1)
                label(hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hidden ? Color.clear : ThingsColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(hidden ? ThingsColor.separator : Color.clear, lineWidth: 1))
        case .principes:
            let ink = EventStyle.textColors(on: color, opacity: 1, dark: scheme == .dark).primary
            label(hidden ? ThingsColor.textSecondary : ink, weight: .medium)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(hidden ? Color.clear : color))
                .overlay(Capsule().strokeBorder(hidden ? ThingsColor.separator : color, lineWidth: 1))
        case .rekenmachine:
            HStack(spacing: 6) {
                RoundKey(tint: hidden ? nil : color).frame(width: 12, height: 12)
                label(ThingsColor.textSecondary)
            }
        case .drukproef:
            HStack(spacing: 5) {
                Circle()
                    .fill(hidden ? Color.clear : color)
                    .overlay(Circle().strokeBorder(hidden ? ThingsColor.textSecondary : color, lineWidth: 1))
                    .frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(.werk(size: 11))
                    .foregroundStyle(hidden ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                    .lineLimit(1)
            }
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
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isToday ? Color(hex: 0x1C1C1C) : ThingsColor.cardBackground))
                Text(isToday ? "VANDAAG" : " ")
                    .font(.werk(size: 9))
                    .tracking(0.6)
                    .foregroundStyle(ThingsColor.accent)
            }
            .padding(.horizontal, 3)
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
            HStack(spacing: 6) {
                Text(weekday).font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                numberView(size: 15, weight: isToday ? .semibold : .light,
                           fill: isToday ? ThingsColor.accent : .clear,
                           ink: isToday ? ThingsColor.cardBackground : ThingsColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
        case .wandklok, .standaard:
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
        case .wandklok, .principes, .rekenmachine: (ThingsColor.today, 2)
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
        case .principes: 12
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
