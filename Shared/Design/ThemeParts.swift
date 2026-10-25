import SwiftUI

// Kleine onderdelen die per thema anders getekend worden (zie de schetsen in de canvas "Werkbank thema's").

/// Kop van een onderdeel (kolom, Tijd schrijven, Mail, Agenda) met een aantal of toelichting erachter.
struct ThemedHeading: View {
    let title: String
    var count: Int?
    /// Toelichting in plaats van een aantal ("Nog te factureren").
    var detail: String?
    var baseSize: CGFloat = 13

    private var look: ThemeLook { ThemeStore.shared.look }

    var body: some View {
        switch look {
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
            HStack(spacing: 8) {
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.werk(size: baseSize + 2, weight: .medium))
                    .foregroundStyle(ThingsColor.textPrimary)
                if let count {
                    Text("\(count)")
                        .font(.werk(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
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
}
