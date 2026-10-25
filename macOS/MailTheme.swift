import AppKit
import SwiftUI

// Het mailpaneel zoals elk thema het tekent: kop, mailboxtabs en mailrijen.

/// Titel in de kop van het mailpaneel (de knoppen rechts blijven van het paneel zelf).
struct MailHeaderTitle: View {
    let title: String
    let unread: Int
    /// Aantal mails in de lijst (Tischsuper: "12 / 48").
    var total = 0
    /// Naam van de getoonde mailbox (Drukproef: "in Support.").
    var mailbox = ""

    var body: some View {
        switch ThemeStore.shared.look {
        case .wandklok:
            // Groot en vet zoals het horlogeblad, met een productcode in kapitalen eronder.
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.werk(size: 22, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("\(mailbox.uppercased()) · \(unread) ONGELEZEN")
                    .font(.werk(size: 10))
                    .tracking(0.6)
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textSecondary)
            }
        case .tischsuper:
            // De datum groot en dun, zoals het jaartal op de RT 20-pagina; rechts de teller zoals 01 / 08.
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
                    Text(Date.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "nl_NL"))))
                        .font(.werk(size: 11))
                        .foregroundStyle(ThingsColor.textSecondary)
                }
                .padding(.bottom, 4)
                Spacer(minLength: 6)
                ThemeParts.counter(unread, total)
                    .padding(.bottom, 4)
            }
        case .drukproef:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title.uppercased()).font(.werk(size: 11, weight: .medium)).foregroundStyle(ThingsColor.textPrimary)
                    Text("ONGELEZEN (N°\(String(format: "%02d", unread)))").font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                }
                // Een kop in drie kleuren zoals op de poster.
                (Text(DutchNumber.word(unread)).foregroundColor(ThingsColor.textPrimary)
                    + Text(" nieuw -").foregroundColor(ThingsColor.today)
                    + Text("\nin \(mailbox).").foregroundColor(ThingsColor.textSecondary))
                    .font(.werk(size: 26, weight: .medium))
                    .kerning(-1.4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        case .rekenmachine:
            // Het aantal ongelezen op een klein lcd-schermpje, zoals het geheugen van de rekenmachine.
            HStack(spacing: 8) {
                Text(title.uppercased()).font(.werk(size: 10)).tracking(1).foregroundStyle(ThingsColor.textSecondary)
                LCDPanel(radius: 6) {
                    LCDDigits(text: "\(unread)", size: 12)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                }
                .fixedSize()
                .accessibilityLabel("\(unread) ongelezen")
            }
        case .principes:
            // Twee koppen naast elkaar met elk een regel erboven, zoals de affiche.
            HStack(alignment: .top, spacing: 14) {
                RuledHeading(text: title)
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(ThemeParts.rule).frame(height: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(unread)").font(.werk(size: 15, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(ThingsColor.textPrimary)
                        Text("ongelezen").font(.werk(size: 11)).foregroundStyle(ThingsColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .karmijn:
            // Label erboven, dan groot en rood "INBOX" zoals de kop van de affiche.
            VStack(alignment: .leading, spacing: 3) {
                KarmijnLabel(text: "\(title) / \(unread) ongelezen")
                Text("INBOX")
                    .font(.werkDisplay(size: 40))
                    .foregroundStyle(ThingsColor.today)
                    .displayTight(40)
            }
        case .spark:
            HStack(spacing: 9) {
                Image(systemName: "chevron.down")
                    .font(.werk(size: 8, weight: .bold))
                    .foregroundStyle(ThingsColor.textSecondary)
                Image(systemName: "tray")
                    .font(.werk(size: 13, weight: .medium))
                Text("INBOX").font(.werk(size: 12, weight: .medium)).tracking(0.3)
            }
            .foregroundStyle(ThingsColor.textPrimary)
        case .sneeuwwitje, .standaard:
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
            HStack(spacing: 6) {
                // Sneeuwwitje: een houten streepje bij de gekozen mailbox.
                if isOn && ThemeStore.shared.look == .sneeuwwitje {
                    RoundedRectangle(cornerRadius: 1.5).fill(ThemeParts.elm).frame(width: 3, height: 12)
                }
                Text(title)
                    .font(.werk(size: 11, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary)
            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isOn {
                        Capsule().fill(ThingsColor.cardBackground)
                            .shadow(color: ThingsColor.cardShadow, radius: 4, y: 2)
                    }
                }
        case .tischsuper:
            // Een pianotoets van de platenspeler met het label eronder; de gekozen mailbox is oranje.
            PianoKey(title: title, fill: isOn ? ThemeParts.orange : Color(hex: 0x303030),
                     ink: isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary)
                .frame(maxWidth: .infinity)
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
        case .karmijn:
            // Kapitalen; de gekozen mailbox krijgt een rode lijn eronder.
            KarmijnLabel(text: title, color: isOn ? ThingsColor.textPrimary : ThingsColor.textSecondary, size: 11)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    if isOn { Rectangle().fill(ThemeParts.karmijn).frame(height: 1) }
                }
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

/// Vooraan een rij in de maillijst: het logo van de website achter het domein van de afzender, anders de initialen
/// in de vorm van het thema (freemail-adressen en sites zonder bruikbaar icoon houden de initialen).
struct MailSenderIcon: View {
    let name: String
    let address: String
    var size: CGFloat = 30

    @State private var logo: NSImage?

    var body: some View {
        let look = ThemeStore.shared.look
        // Karmijn: recht, zoals de rest van dat thema; elders rond.
        let shape = RoundedRectangle(cornerRadius: look == .karmijn ? 0 : size / 2, style: .continuous)
        Group {
            if let logo {
                shape.fill(look == .karmijn ? ThemeParts.creme : Color.white)
                    .overlay(Image(nsImage: logo).resizable().interpolation(.high).scaledToFit().padding(size * 0.14))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(ThingsColor.separator, lineWidth: 1))
            } else {
                Text(MailLook.initials(name))
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .frame(width: size, height: size)
                    .background {
                        switch look {
                        case .rekenmachine: RoundKey()
                        case .karmijn: shape.strokeBorder(ThingsColor.separator, lineWidth: 1)
                        default: shape.fill(ThingsColor.tagBackground)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .task(id: address) {
            logo = nil
            guard !address.isEmpty, let data = await SenderLogoService.shared.logo(forAddress: address) else { return }
            logo = NSImage(data: data)
        }
        .accessibilityHidden(true)
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

    static var unreadDot: Color {
        switch ThemeStore.shared.look {
        case .standaard, .principes: ThingsColor.accent
        case .drukproef, .rekenmachine: ThingsColor.today
        default: ThingsColor.running
        }
    }

    /// Een afzender die een machine is (noreply, notificaties): Spark toont dan een belletje in plaats van een persoontje.
    static func isNotification(_ address: String?) -> Bool {
        guard let local = address?.lowercased().split(separator: "@").first else { return false }
        return ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "notify", "alert", "mailer-daemon",
                "bounce", "newsletter"].contains { local.contains($0) }
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
