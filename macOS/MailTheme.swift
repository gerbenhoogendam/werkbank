import SwiftUI

// Het mailpaneel zoals elk thema het tekent: kop, mailboxtabs en mailrijen.

/// Titel in de kop van het mailpaneel (de knoppen rechts blijven van het paneel zelf).
struct MailHeaderTitle: View {
    let title: String
    let unread: Int

    var body: some View {
        switch ThemeStore.shared.look {
        case .tischsuper:
            // De datum groot en dun, zoals het jaartal op de RT 20-pagina.
            HStack(alignment: .bottom, spacing: 10) {
                Text(Date.now.formatted(.dateTime.day()))
                    .font(.werk(size: 52, weight: .ultraLight))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "nl_NL"))))
                        .font(.werk(size: 12))
                        .foregroundStyle(ThingsColor.textPrimary)
                    Text("\(Date.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "nl_NL")))) · \(unread) ongelezen")
                        .font(.werk(size: 11))
                        .foregroundStyle(ThingsColor.textSecondary)
                }
                .padding(.bottom, 4)
            }
        case .drukproef:
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title.uppercased()).font(.werk(size: 11, weight: .medium)).foregroundStyle(ThingsColor.textPrimary)
                Text("ONGELEZEN (N°\(String(format: "%02d", unread)))").font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
            }
        case .rekenmachine:
            HStack(spacing: 10) {
                Text(title.uppercased()).font(.werk(size: 10)).tracking(1).foregroundStyle(ThingsColor.textSecondary)
                Text("\(unread) ongelezen").font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
            }
        case .principes:
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(ThemeParts.rule).frame(height: 2)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title).font(.werk(size: 15, weight: .medium)).foregroundStyle(ThingsColor.textPrimary)
                    Text("\(unread) ongelezen").font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                }
            }
        case .spark:
            HStack(spacing: 9) {
                Image(systemName: "tray")
                    .font(.werk(size: 13, weight: .medium))
                Text(title.uppercased()).font(.werk(size: 12, weight: .medium)).tracking(0.3)
            }
            .foregroundStyle(ThingsColor.textPrimary)
        case .wandklok, .sneeuwwitje, .standaard:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.werk(size: 15, weight: .semibold)).foregroundStyle(ThingsColor.textPrimary)
                Text("\(unread) ongelezen").font(.werk(size: 11)).monospacedDigit().foregroundStyle(ThingsColor.textSecondary)
            }
        }
    }
}

/// Eén mailbox in de tabs bovenin.
struct MailboxTab: View {
    let title: String
    let isOn: Bool
    var color: Color = .clear
    var count: Int?
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            label
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var label: some View {
        switch ThemeStore.shared.look {
        case .wandklok, .sneeuwwitje:
            Text(title)
                .font(.werk(size: 11, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isOn {
                        Capsule().fill(ThingsColor.cardBackground)
                            .shadow(color: ThingsColor.cardShadow, radius: 4, y: 2)
                    }
                }
        case .tischsuper:
            Text(title)
                .font(.werk(size: 11))
                .foregroundStyle(isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isOn ? Color(hex: 0x303030) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Color(hex: 0x303030), lineWidth: 1))
        case .principes:
            Text(title)
                .font(.werk(size: 11, weight: isOn ? .medium : .regular))
                .foregroundStyle(isOn ? Color.white : ThingsColor.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? ThingsColor.accent : .clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : ThingsColor.separator, lineWidth: 1))
        case .rekenmachine:
            Text(title)
                .font(.werk(size: 11))
                .foregroundStyle(ThingsColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if isOn {
                        Capsule().fill(Color.black.opacity(scheme == .dark ? 0.35 : 0.08))
                            .overlay(Capsule().stroke(Color.black.opacity(0.3), lineWidth: 2).blur(radius: 1.5)
                                .offset(y: 1).mask(Capsule()))
                    } else {
                        Capsule().fill(ThingsColor.cardBackground)
                            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.15), radius: 1.5, y: 1)
                    }
                }
        case .drukproef:
            Text(title)
                .font(.werk(size: 16, weight: isOn ? .medium : .regular))
                .tracking(-0.5)
                .foregroundStyle(isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary)
        case .spark:
            // Een rij in de donkerblauwe kop: kleurstreepje, naam en teller.
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 15)
                Text(title).font(.werk(size: 12.5))
                Spacer(minLength: 4)
                if let count, count > 0 { CountBadge(count: count) }
            }
            .foregroundStyle(ThingsColor.textPrimary)
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? Color.white.opacity(0.1) : .clear))
        case .standaard:
            Text(title)
                .font(.werk(size: 11.5, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.white : ThingsColor.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? ThingsColor.accent : Color.clear))
        }
    }
}

enum MailLook {
    /// Rijen als losse kaartjes (gekozen rij als witte kaart) in plaats van rijen met haarlijnen.
    static var cardRows: Bool {
        switch ThemeStore.shared.look {
        case .wandklok, .tischsuper, .sneeuwwitje, .rekenmachine: true
        default: false
        }
    }

    /// Initialen van de afzender in een rondje.
    static var avatars: Bool { cardRows }

    static var unreadDot: Color {
        switch ThemeStore.shared.look {
        case .standaard, .principes: ThingsColor.accent
        case .drukproef, .rekenmachine: ThingsColor.today
        default: ThingsColor.running
        }
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
