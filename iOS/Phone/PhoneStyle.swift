import CoreText
import SwiftUI

// De iPhone-app in de stijl Etiket (licht): gebroken wit papier, witte kaarten met een haarlijn, inkt, één limoen.
// Diepte is subtiel: kaarten liggen iets boven het papier (zachte slagschaduw), putjes en sporen liggen erin (schaduw
// aan de binnenkant), de gekozen knop in een spoor ligt er weer bovenop. Ontwerp: canvas "Werkbank iOS".

enum Ph {
    static let paper = Color(hex: 0xF6F6F1)
    static let card = Color.white
    static let line = Color(hex: 0xDADAD2)
    static let hair = Color(hex: 0xECECE6)
    static let ink = Color(hex: 0x0B0B0B)
    static let ink2 = Color(hex: 0x55554F)
    static let ink3 = Color(hex: 0x7A7A72)
    static let lime = Color(hex: 0xD4FF1E)
    static let olive = Color(hex: 0x4F5E00)
    static let well = Color(hex: 0xECECE5)
    static let band = Color(hex: 0xF0F0E9)
    static let chosen = Color(hex: 0xF3F6E4)
    /// Datum van een mail met ster die blijft liggen: na meer dan 4 dagen, na meer dan 6 dagen.
    static let late = Color(hex: 0xFF6A00)
    static let urgent = Color(hex: 0xFF0055)
    static let danger = Color(hex: 0xC8003F)
    static let claude = Color(hex: 0xD97757)

    /// Koppen en grote cijfers (Bebas Neue, meegeleverd).
    static func poster(_ size: CGFloat) -> Font { .custom("BebasNeue-Regular", size: size) }

    /// Bebas Neue zit in de app (Shared/Fonts) maar staat niet in Info.plist: één keer aanmelden bij het opstarten,
    /// anders valt elke kop terug op de systeemletter.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "BebasNeue-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// De letter van mailtekst.
    static func mail(_ size: CGFloat) -> Font { .custom("Helvetica", size: size) }
}

// MARK: - Tekst

/// "—— 12 ONGELEZEN": streepje en kleine kapitalen in olijf.
struct PhEyebrow: View {
    let text: String
    var color: Color = Ph.olive

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 24, height: 1).accessibilityHidden(true)
            Text(text.uppercased())
                .font(Ph.text(11, .semibold))
                .tracking(2)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

/// Kleine kapitalen met letterafstand (knoppen, veldnamen).
struct PhCaps: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = Ph.ink2

    var body: some View {
        Text(text.uppercased())
            .font(Ph.text(size, .semibold))
            .tracking(size * 0.15)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// De kop van een scherm: bijschrift en grote titel, rechts eventueel knoppen.
struct PhHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    var size: CGFloat = 52
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow { PhEyebrow(text: eyebrow) }
                Text(title.uppercased())
                    .font(Ph.poster(size))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -size * 0.12)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
    }
}

extension PhHeader where Trailing == EmptyView {
    init(eyebrow: String?, title: String, size: CGFloat = 52) {
        self.init(eyebrow: eyebrow, title: title, size: size) { EmptyView() }
    }
}

// MARK: - Vlakken

extension View {
    /// Een witte kaart met haarlijn die iets boven het papier ligt.
    func phCard(border: Color = Ph.line) -> some View {
        background(
            Rectangle().fill(Ph.card)
                .shadow(color: Ph.ink.opacity(0.04), radius: 0, y: 1)
                .shadow(color: Ph.ink.opacity(0.05), radius: 5, y: 3)
        )
        .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
    }

    /// Een kaart die naar voren komt: inktrand en een harde schaduw eronder (de geopende mail).
    func phRaisedCard() -> some View {
        background(
            Rectangle().fill(Ph.card)
                .background(Rectangle().fill(Ph.ink).offset(y: 3))
                .shadow(color: Ph.ink.opacity(0.08), radius: 10, y: 8)
        )
        .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
    }

    /// Een putje: ligt in het papier (velden, sporen van keuzeknoppen, de band met sterren).
    func phWell(_ color: Color = Ph.well) -> some View {
        background(Rectangle().fill(color.shadow(.inner(color: Ph.ink.opacity(0.12), radius: 1.5, y: 1))))
    }

    /// De achtergrond van elk scherm.
    func phScreen() -> some View {
        background(Ph.paper.ignoresSafeArea())
    }
}

// MARK: - Knoppen

/// Limoen met inktrand en een harde schaduw eronder; ingedrukt zakt hij erin.
struct PhPrimaryStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Ph.text(13, .semibold))
            .tracking(1.8)
            .foregroundStyle(Ph.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                    .background(Rectangle().fill(Ph.ink).offset(y: pressed ? 0 : 3))
            )
            .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
            .offset(y: pressed ? 2 : 0)
            .contentShape(Rectangle())
    }
}

/// Wit met een inktrand.
struct PhSecondaryStyle: ButtonStyle {
    var height: CGFloat = 48
    var tint: Color = Ph.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ph.text(11.5, .semibold))
            .tracking(1.4)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Rectangle().fill(configuration.isPressed ? Ph.band : Ph.card)
                .shadow(color: Ph.ink.opacity(0.08), radius: 0, y: 1))
            .overlay(Rectangle().strokeBorder(tint, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Inkt met licht erop (Archiveer, Stop).
struct PhInkStyle: ButtonStyle {
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ph.text(11.5, .semibold))
            .tracking(1.4)
            .foregroundStyle(Ph.paper)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Rectangle().fill(Ph.ink)
                .shadow(color: Ph.ink.opacity(configuration.isPressed ? 0 : 0.25), radius: 2, y: 2))
            .contentShape(Rectangle())
    }
}

/// Een vierkant knopje met een icoon (zoeken, mappen, voorkeuren).
struct PhIconButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Ph.ink)
            .frame(width: size, height: size)
            .background(Rectangle().fill(configuration.isPressed ? Ph.band : Ph.card)
                .shadow(color: Ph.ink.opacity(0.08), radius: 0, y: 1)
                .shadow(color: Ph.ink.opacity(0.06), radius: 3, y: 2))
            .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

// MARK: - Keuzes

/// Een spoor met knoppen; de gekozen ligt er limoen bovenop. Met `isOn` en `onLongPress` kunnen er meer tegelijk aan
/// staan: tikken kiest, lang drukken voegt toe of haalt weg.
struct PhSegmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var count: Int? = nil
    }

    let items: [Item]
    @Binding var selection: Value
    var height: CGFloat = 38
    var isOn: ((Value) -> Bool)? = nil
    var onLongPress: ((Value) -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.value) { item in
                let on = isOn?(item.value) ?? (item.value == selection)
                if let onLongPress {
                    cell(item, on: on)
                        .onTapGesture { choose(item.value) }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.15)) { onLongPress(item.value) }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityAction(named: on ? "Uit de combinatie" : "Toevoegen aan combinatie") {
                            onLongPress(item.value)
                        }
                } else {
                    Button { choose(item.value) } label: { cell(item, on: on) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(3)
        .phWell()
    }

    private func choose(_ value: Value) {
        withAnimation(.easeOut(duration: 0.15)) { selection = value }
    }

    private func cell(_ item: Item, on: Bool) -> some View {
        HStack(spacing: 5) {
            Text(item.title.uppercased())
                .font(Ph.text(11.5, .semibold))
                .tracking(1.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let count = item.count, count > 0 {
                Text("\(count)")
                    .font(Ph.text(10.5, .semibold))
                    .foregroundStyle(on ? Ph.ink : Ph.olive)
            }
        }
        .foregroundStyle(on ? Ph.ink : Ph.ink2)
        .frame(maxWidth: .infinity, minHeight: height)
        .background {
            if on {
                Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                    .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                    .shadow(color: Ph.ink.opacity(0.12), radius: 2, y: 2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Een vierkant vinkje: limoen met inkt als het aan staat, anders een putje met inktrand.
struct PhCheck: View {
    let isOn: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            if isOn {
                Rectangle().fill(Ph.lime).shadow(color: Ph.ink.opacity(0.25), radius: 0, y: 1)
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(Ph.ink)
            } else {
                Rectangle().fill(Ph.card.shadow(.inner(color: Ph.ink.opacity(0.12), radius: 1, y: 1)))
                Rectangle().strokeBorder(Ph.ink, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Een schakelaar in de stijl: rechthoekig, limoen als hij aan staat.
struct PhToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill((configuration.isOn ? Ph.lime : Ph.line)
                        .shadow(.inner(color: Ph.ink.opacity(0.25), radius: 1.5, y: 1)))
                    Rectangle().fill(configuration.isOn ? Ph.ink : Ph.card)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .padding(3)
                }
                .frame(width: 46, height: 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Aan" : "Uit")
    }
}

/// Een chip: inkt als hij aan staat (ingedrukt), anders wit met een haarlijn.
struct PhChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Ph.text(11, .semibold))
                .tracking(1.2)
                .foregroundStyle(isOn ? Ph.ink : Ph.ink3)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background {
                    if isOn {
                        Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                            .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                    } else {
                        Rectangle().fill(Ph.well.shadow(.inner(color: Ph.ink.opacity(0.12), radius: 1.5, y: 1.5)))
                    }
                }
                .overlay(Rectangle().strokeBorder(isOn ? Ph.ink : Ph.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Kleine onderdelen

/// Het logo van de afzender in een wit rondje (zoals op de Mac), anders de initialen in een rondje dat in het
/// papier ligt. Freemail en sites zonder bruikbaar icoon houden de initialen.
struct PhAvatar: View {
    let name: String
    var size: CGFloat = 34
    var isMe = false
    /// Het mailadres (mag met naam ervoor); leeg = alleen initialen.
    var address: String = ""

    @AppStorage(SettingsKey.mailLogos) private var showLogos = true
    @State private var logo: UIImage?

    private var key: String { "sender:" + address.lowercased() }

    var body: some View {
        Group {
            if showLogos, !isMe, !address.isEmpty, let image = logo ?? DecodedLogos.image(for: key) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Ph.card))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Ph.line, lineWidth: 1))
                    .accessibilityHidden(true)
            } else {
                initialsView
            }
        }
        .task(id: address) {
            guard showLogos, !isMe, !address.isEmpty, DecodedLogos.image(for: key) == nil else { return }
            guard let data = await SenderLogoService.shared.logo(forAddress: address) else { return }
            logo = DecodedLogos.image(from: data, for: key)
        }
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "|" }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var initialsView: some View {
        Text(initials)
            .font(Ph.text(size * 0.32, .semibold))
            .foregroundStyle(isMe ? Ph.lime : Ph.ink)
            .frame(width: size, height: size)
            .background(Circle().fill((isMe ? Ph.ink : Ph.well)
                .shadow(.inner(color: Ph.ink.opacity(0.12), radius: 1, y: 1))))
            .accessibilityHidden(true)
    }
}

/// De ster van Werkbank: limoen, verzonken (schaduw aan de binnenkant).
struct PhStar: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size))
            .foregroundStyle(Ph.lime.shadow(.inner(color: Ph.ink2, radius: 0.6, x: 0.35, y: 0.9)))
    }
}

/// De vonk van Claude.
struct PhSpark: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Ph.claude)
    }
}

/// Een label met de mailbox ("SUPP").
struct PhBoxTag: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Ph.text(10, .semibold))
            .tracking(1.2)
            .foregroundStyle(Ph.ink2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Ph.band)
    }
}

/// Een veld met een naam ervoor, als regel in een witte kaart.
struct PhFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            PhCaps(text: label, size: 11)
                .fixedSize()
                .frame(minWidth: 96, alignment: .leading)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }
}

/// Knoppen naast elkaar die doorlopen op de volgende regel, links uitgelijnd met vaste tussenruimte.
struct PhFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(width: proposed ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
