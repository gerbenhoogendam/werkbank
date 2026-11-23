import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Een adresveld in het opstelvenster (Aan, Cc, Bcc). Elke ontvanger is een blokje met alleen de naam (of het adres als
/// er geen naam is); daarachter typ je de volgende.
/// - Sluiten tot een blokje: komma, puntkomma, Return of Tab; een spatie alleen na een compleet adres (een naam typ je
///   met spaties). Staat er nog geen compleet adres en is er een suggestie gemarkeerd, dan wordt die het blokje.
///   Plakken met komma's ertussen geeft losse blokjes. Het veld verlaten sluit een compleet adres.
/// - Klik op een blokje: het adres komt erbij, met een kruisje om de ontvanger weg te halen. Dubbelklik zet hem terug
///   naar tekst om te verbeteren. Backspace in een leeg tekstvak wijst het laatste blokje aan en haalt het de tweede
///   keer weg.
/// - Een blokje dat geen geldig adres is, is rood.
/// Aanvullen gaat uit wie je mailde, Contacten en de klantenlijst (de naam van een klant geeft de mensen van die klant):
/// pijltjes kiezen, Return of Tab neemt het gemarkeerde adres over, Esc sluit de lijst.
///
/// Naar buiten blijft het veld één tekst ("Naam <adres>, adres", `RecipientTokens`), zodat versturen, concepten en
/// beantwoorden er niets van merken.
struct AddressField<Field: Hashable>: View {
    @Binding var text: String
    let focus: FocusState<Field?>.Binding
    let field: Field

    @State private var tokens: [RecipientToken] = []
    /// Wat er achter de blokjes getypt wordt.
    @State private var draft = ""
    /// Wat dit veld zelf het laatst in `text` zette. Staat er iets anders, dan kwam het van buiten (een antwoord dat
    /// zijn ontvangers invult, een concept) en wordt het opnieuw in blokjes gezet.
    @State private var written: String?
    /// Het aangeklikte blokje: dat toont zijn adres.
    @State private var openID: UUID?
    @State private var highlighted = 0
    /// Net gekozen of met Esc weggeklikt: de lijst blijft dicht tot je verder typt.
    @State private var settled: String?
    @State private var prepared = false
    /// Backspace in een leeg tekstvak. Via een toetsmonitor: het tekstveld van macOS slikt Backspace zelf, zodat
    /// `onKeyPress(.delete)` hem in de app niet kreeg.
    @State private var keyMonitor: Any?
    /// Wie dit veld is, voor het slepen van een blokje naar een ander veld (Aan, Cc, Bcc).
    @State private var dragKey = UUID()
    @State private var isDropTarget = false

    private var isFocused: Bool { focus.wrappedValue == field }

    private func suggestions(for term: String) -> [AddressCandidate] {
        let token = term.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return [] }
        let present = Set(tokens.filter(\.isValid).map { $0.address.lowercased() })
        let found = AddressSuggestions.search(token, in: AddressBook.shared.candidates(), excluding: present)
        if found.count == 1, found[0].address == token.lowercased() { return [] }
        return found
    }

    private var matches: [AddressCandidate] {
        let token = draft.trimmingCharacters(in: .whitespaces)
        guard isFocused, token != settled else { return [] }
        return suggestions(for: token)
    }

    var body: some View {
        let matches = self.matches
        VStack(alignment: .leading, spacing: 4) {
            RecipientFlow() {
                ForEach(tokens) { token in
                    RecipientChip(token: token, isOpen: openID == token.id,
                                  onToggle: { toggle(token) }, onEdit: { edit(token) }, onRemove: { remove(token) })
                        // Oppakken en naar Aan, Cc of Bcc slepen: daar komt hij bij, hier gaat hij weg.
                        .onDrag {
                            RecipientDrag.begin(text: token.fieldText, source: dragKey) { remove(token) }
                            return NSItemProvider(object: token.fieldText as NSString)
                        }
                }
                TextField("", text: $draft)
                    .focused(focus, equals: field)
                    .frame(height: RecipientChip.height)
                    .onKeyPress(.downArrow) {
                        guard !matches.isEmpty else { return .ignored }
                        highlighted = min(highlighted + 1, matches.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard !matches.isEmpty else { return .ignored }
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        if !matches.isEmpty, !RecipientTokens.isComplete(draft) {
                            pick(matches[min(highlighted, matches.count - 1)])
                            return .handled
                        }
                        // Een compleet adres sluit en Tab gaat door naar het volgende veld.
                        if RecipientTokens.isComplete(draft) { closeDraft() }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if !matches.isEmpty {
                            settled = draft.trimmingCharacters(in: .whitespaces)
                            return .handled
                        }
                        guard openID != nil else { return .ignored }
                        openID = nil
                        return .handled
                    }
                    .onSubmit {
                        if !matches.isEmpty, !RecipientTokens.isComplete(draft) {
                            pick(matches[min(highlighted, matches.count - 1)])
                        } else {
                            closeDraft()
                        }
                    }
            }
            // "Aan:" staat op de grondlijn van de eerste regel blokjes, ook als het veld meer regels telt.
            .alignmentGuide(.firstTextBaseline) { _ in RecipientChip.baseline }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.address) { index, candidate in
                        row(candidate, isOn: index == min(highlighted, matches.count - 1))
                    }
                }
                .padding(4)
                .frame(maxWidth: 460, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ThingsColor.separator))
                .padding(.bottom, 4)
            }
        }
        .onChange(of: text, initial: true) { _, new in
            if new != written { adopt(new) }
        }
        .onChange(of: draft) { _, new in draftChanged(new) }
        .padding(.horizontal, isDropTarget ? 4 : 0)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isDropTarget ? ThingsColor.accent.opacity(0.1) : Color.clear))
        .onDrop(of: [.plainText], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                Task { @MainActor in receive(text) }
            }
            return true
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: isFocused) { _, focused in
            if focused { installKeyMonitor() } else { removeKeyMonitor() }
            if focused {
                guard !prepared else { return }
                prepared = true
                Task { await AddressBook.shared.prepare() }
            } else {
                // Het veld verlaten: een compleet adres wordt een blokje, half getypte tekst blijft staan.
                if RecipientTokens.isComplete(draft) { closeDraft() }
                openID = nil
            }
        }
    }

    private func row(_ candidate: AddressCandidate, isOn: Bool) -> some View {
        Button { pick(candidate) } label: {
            HStack(spacing: 8) {
                if let name = candidate.name {
                    Text(name)
                        .font(.werk(size: 13, weight: .medium))
                        .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                }
                Text(candidate.address)
                    .font(.werk(size: 12.5))
                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : ThingsColor.textSecondary)
                Spacer(minLength: 6)
                if let client = candidate.client {
                    HStack(spacing: 4) {
                        ClientLogo(name: client, size: 12)
                        Text(client)
                    }
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.textSecondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? ThingsColor.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tekst van het veld

    /// Van buiten gezet: alles wat er staat wordt een blokje.
    private func adopt(_ value: String) {
        tokens = RecipientTokens.tokens(from: value)
        draft = ""
        openID = nil
        written = value
    }

    private func write() {
        let value = RecipientTokens.text(tokens, draft: draft)
        written = value
        if text != value { text = value }
    }

    /// Een ontvanger die er al staat komt er niet nog eens bij.
    private func add(_ token: RecipientToken) {
        if token.isValid, tokens.contains(where: { $0.isValid && $0.address.lowercased() == token.address.lowercased() }) {
            return
        }
        tokens.append(token)
    }

    // MARK: Typen

    private func draftChanged(_ new: String) {
        // Verder typen: het aangewezen blokje gaat weer dicht.
        if !new.isEmpty { openID = nil }
        let absorbed = RecipientTokens.absorb(new)
        guard !absorbed.tokens.isEmpty || absorbed.draft != new else {
            if new.trimmingCharacters(in: .whitespaces) != settled { settled = nil }
            highlighted = 0
            write()
            return
        }
        var closed = absorbed.tokens
        // Eén stuk afgesloten met een komma terwijl het nog geen adres is: dan telt de gemarkeerde suggestie.
        if closed.count == 1, absorbed.draft.isEmpty, !closed[0].isValid {
            let found = suggestions(for: closed[0].address)
            if !found.isEmpty { closed = [RecipientToken(found[min(highlighted, found.count - 1)].mailAddress)] }
        }
        closed.forEach(add)
        draft = absorbed.draft
        settled = nil
        highlighted = 0
        write()
    }

    /// Return of Tab: wat er getypt staat wordt een blokje (ongeldig als het geen adres is).
    private func closeDraft() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        add(RecipientTokens.token(draft))
        draft = ""
        settled = nil
        highlighted = 0
        write()
    }

    private func pick(_ candidate: AddressCandidate) {
        add(RecipientToken(candidate.mailAddress))
        draft = ""
        settled = ""
        highlighted = 0
        write()
    }

    /// Backspace in een leeg tekstvak: eerst het laatste blokje aanwijzen (het adres komt erbij), daarna weghalen.
    private func deleteBackward() -> KeyPress.Result {
        guard draft.isEmpty, !tokens.isEmpty else { return .ignored }
        if let openID, let token = tokens.first(where: { $0.id == openID }) {
            remove(token)
        } else {
            openID = tokens.last?.id
        }
        return .handled
    }

    // MARK: Slepen

    /// Er is tekst op het veld gelaten: een blokje uit een ander veld (dat haalt hem daar weg) of adressen van elders.
    private func receive(_ text: String) {
        let dragged = RecipientDrag.take(text: text)
        if let dragged {
            // Op het eigen veld teruggezet: niets veranderen.
            guard dragged.source != dragKey else { return }
            dragged.remove()
        }
        RecipientTokens.tokens(from: text).forEach(add)
        openID = nil
        write()
    }

    // MARK: Backspace

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handleKey(event) } ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Backspace zonder andere toets, terwijl dit veld de cursor heeft en er niets getypt staat.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isFocused, event.keyCode == 51,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        return deleteBackward() == .handled
    }

    // MARK: Blokjes

    private func toggle(_ token: RecipientToken) {
        withAnimation(ThingsMotion.reveal) { openID = openID == token.id ? nil : token.id }
        // Het tekstvak krijgt de cursor, zodat Backspace het aangewezen blokje weghaalt.
        focus.wrappedValue = field
    }

    private func remove(_ token: RecipientToken) {
        tokens.removeAll { $0.id == token.id }
        if openID == token.id { openID = nil }
        write()
    }

    /// Dubbelklik: terug naar tekst om het adres te verbeteren. Wat er nog getypt stond blijft niet hangen: dat wordt
    /// eerst zelf een blokje.
    private func edit(_ token: RecipientToken) {
        if !draft.trimmingCharacters(in: .whitespaces).isEmpty { add(RecipientTokens.token(draft)) }
        tokens.removeAll { $0.id == token.id }
        openID = nil
        draft = token.fieldText
        settled = token.fieldText
        focus.wrappedValue = field
        write()
    }
}

// MARK: - Slepen tussen velden

/// Het blokje dat nu versleept wordt, zodat het veld waar het terechtkomt het uit het oude veld kan halen. Geldt een
/// minuut: een sleep die ergens anders eindigde, haalt later niets weg.
@MainActor
enum RecipientDrag {
    struct Item {
        let text: String
        let source: UUID
        let remove: () -> Void
        let started: Date
    }

    private static var current: Item?

    static func begin(text: String, source: UUID, remove: @escaping () -> Void) {
        current = Item(text: text, source: source, remove: remove, started: Date())
    }

    /// Het versleepte blokje als `text` daarvan komt; daarna is het op.
    static func take(text: String) -> Item? {
        defer { current = nil }
        guard let item = current, item.text == text, Date().timeIntervalSince(item.started) < 60 else { return nil }
        return item
    }
}

// MARK: - Blokje

/// Eén ontvanger: de naam (of het adres); aangeklikt met het adres erbij en een kruisje.
private struct RecipientChip: View {
    static let height: CGFloat = 22
    /// Waar de grondlijn van de naam ligt, van boven gemeten (voor het label van het veld ernaast).
    static let baseline: CGFloat = 15.5

    let token: RecipientToken
    let isOpen: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var foreground: Color {
        if isOpen { return token.isValid ? ThingsColor.onAccent : Color.white }
        return token.isValid ? ThingsColor.textPrimary : ThingsColor.error
    }

    private var fill: Color {
        if isOpen { return token.isValid ? ThingsColor.accent : ThingsColor.error }
        return token.isValid ? ThingsColor.textPrimary.opacity(0.08) : ThingsColor.error.opacity(0.12)
    }

    var body: some View {
        HStack(spacing: 6) {
            if !token.isValid {
                Image(systemName: "exclamationmark.circle")
                    .font(.werk(size: 10.5, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(token.label)
                .font(.werk(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if isOpen {
                if token.isValid, token.name != nil {
                    Text(token.address)
                        .font(.werk(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.werk(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Verwijderen")
                .accessibilityLabel("Verwijder \(token.label)")
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .frame(height: Self.height)
        .background(Capsule(style: .continuous).fill(fill))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(token.isValid || isOpen ? Color.clear : ThingsColor.error.opacity(0.5)))
        .contentShape(Capsule(style: .continuous))
        // De klik werkt meteen (niet wachten of er een tweede komt); bij een dubbelklik wint het bewerken.
        .onTapGesture(perform: onToggle)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onEdit() })
        .help(token.isValid ? token.address : "Geen geldig e-mailadres")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Indeling

/// Blokjes naast elkaar, op een nieuwe regel als het niet meer past. Het laatste onderdeel (het tekstvak) krijgt de rest
/// van de regel, of een eigen regel als er minder dan `minimumEditorWidth` over is.
private struct RecipientFlow: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5
    var minimumEditorWidth: CGFloat = 110

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if index == subviews.count - 1 {
                // Het tekstvak: de rest van de regel.
                if x > 0, width - x < minimumEditorWidth {
                    y += rowHeight + lineSpacing
                    x = 0
                    rowHeight = 0
                }
                size.width = max(width - x, 0)
            } else {
                // Een blokje dat breder is dan het veld wordt afgekapt.
                size.width = min(size.width, width)
                if x > 0, x + size.width > width {
                    y += rowHeight + lineSpacing
                    x = 0
                    rowHeight = 0
                }
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width.isFinite else {
            // Geen breedte opgegeven: alles op één regel.
            let sizes = subviews.dropLast().map { $0.sizeThatFits(.unspecified) }
            let natural = sizes.reduce(0) { $0 + $1.width + spacing } + minimumEditorWidth
            let height = max(sizes.map(\.height).max() ?? 0, subviews.last?.sizeThatFits(.unspecified).height ?? 0)
            return CGSize(width: natural, height: height)
        }
        return CGSize(width: width, height: arrange(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }
}
