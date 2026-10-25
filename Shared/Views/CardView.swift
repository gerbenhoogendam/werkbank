import SwiftData
import SwiftUI

/// Kaart op het board: titel, optioneel klantlabel en -logo, afzenderregel, uitklapbare mailtekst, subtaken en
/// onderaan een rij met afronden, timer en mail lezen. Klikken op de kaart opent de taak (notities en subtaken); een nieuwe kaart opent direct in bewerkmodus.
struct CardView: View {
    let card: TodoCard
    var isTimerRunning = false
    /// De lopende tijdregel van deze kaart (voor "loopt" met de tijd, zoals het thema dat toont).
    var runningEntry: TimeEntry?
    /// Nieuwe kaarten openen in bewerkmodus; op macOS kun je onderaan een subtaak toevoegen.
    var isEditable = false
    var onStartTimer: () -> Void = {}
    /// Klik op de kaart (niet op een knop of veld).
    var onOpen: () -> Void = {}

    private enum Field: Hashable { case title, minutes, subtask }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Subtaken komen van één gedeelde query hoger in de boom (niet één query per kaart).
    @Environment(\.subtasksByCard) private var subtasksByCard
    private var subtasks: [Subtask] { subtasksByCard[card.id] ?? [] }
    @State private var editing = false
    @State private var titleDraft = ""
    @State private var minutesDraft = ""
    @State private var expanded = false
    @State private var bodyHeight: CGFloat = 0
    @State private var isHovering = false
    /// Het vinkje is gezet; de taak gaat even later naar het archief.
    @State private var completing = false
    @State private var addingSubtask = false
    @State private var subtaskDraft = ""
    /// Tussen twee subtaken door verliest het veld heel even de focus; dat telt dan niet als "klaar".
    @State private var ignoreFocusLoss = false
    @FocusState private var focus: Field?

    init(card: TodoCard, isTimerRunning: Bool = false, runningEntry: TimeEntry? = nil, isEditable: Bool = false,
         onStartTimer: @escaping () -> Void = {}, onOpen: @escaping () -> Void = {}) {
        self.card = card
        self.isTimerRunning = isTimerRunning
        self.runningEntry = runningEntry
        self.isEditable = isEditable
        self.onStartTimer = onStartTimer
        self.onOpen = onOpen
    }

    private var hasBody: Bool { !(card.bodyText ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleRow
            if editing { minutesRow }
            if let sender = senderName {
                Text(sender)
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture { if hasBody { toggleExpanded() } else { open() } }
            }
            if expanded, let text = card.bodyText, !text.isEmpty { bodyView(text) }
            subtaskList
            #if os(macOS)
            if isEditable && addingSubtask { subtaskField }
            #endif
            actionRow
            if isTimerRunning, let runningEntry, ThemeStore.shared.look != .standaard {
                RunningStrip(entry: runningEntry)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, ThemeStore.shared.look == .drukproef ? 2 : 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            if isTimerRunning, ThemeStore.shared.look == .wandklok { SecondHandLine() }
        }
        // Principes: een lopende kaart is een geel vlak met zwarte tekst.
        .lightScheme(isTimerRunning && ThemeStore.shared.look == .principes)
        // Klein en onopvallend rechtsboven: de mail bij deze taak.
        .overlay(alignment: .topTrailing) {
            if hasBody {
                mailButton.padding(.top, 5).padding(.trailing, 5)
            }
        }
        .background(CardSurface(isRunning: isTimerRunning))
        .contentShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        .onTapGesture { open() }
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expanded)
        .onAppear {
            // Een nieuwe kaart (mail gesleept, plusknop) opent direct in bewerkmodus.
            if isEditable, InlineEditing.pendingEditID == card.id {
                InlineEditing.pendingEditID = nil
                startEditing()
            }
        }
        .onDisappear {
            finishEditing()
            endAddingSubtask()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open de taak") { open() }
    }

    /// Alleen de naam van de afzender ("Naam · adres" → "Naam"); een kaal mailadres tonen we niet.
    private var senderName: String? {
        guard let line = card.senderLine, !line.isEmpty else { return nil }
        if let name = line.components(separatedBy: " · ").first, line.contains(" · ") { return name }
        return line.contains("@") ? nil : line
    }

    /// Klik op de kaart opent de taak, behalve tijdens bewerken ter plekke.
    private func open() {
        guard !editing, !addingSubtask else { return }
        onOpen()
    }

    // MARK: Onderdelen

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if card.isNew {
                Circle()
                    .fill(ThingsColor.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Nieuw")
            }
            if let domain = card.logoDomain {
                LogoView(domain: domain, fallbackName: card.clientLabel ?? domain, size: 15)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            if editing {
                TextField("Titel", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .cardFont(.title)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .focused($focus, equals: .title)
                    .onSubmit(commitEditing)
                    #if os(macOS)
                    .onExitCommand(perform: cancelEditing)
                    #endif
            } else {
                Text(card.title.isEmpty ? "Nieuwe taak" : card.title)
                    .cardFont(.title)
                    .foregroundStyle(card.title.isEmpty ? ThingsColor.textTertiary : ThingsColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.trailing, hasBody ? 14 : 0)   // ruimte voor het mailicoontje rechtsboven
        .onChange(of: focus) { _, new in
            // Focus weg uit alle velden = klaar met bewerken.
            if new == nil && editing { commitEditing() }
            if new == nil && addingSubtask && !ignoreFocusLoss { commitSubtask(keepAdding: false) }
        }
    }

    /// Rond vakje links van de titel: aanklikken rondt de taak af en zet hem in het archief.
    private var completeButton: some View {
        Button(action: complete) {
            ZStack {
                RoundedRectangle(cornerRadius: ThingsMetrics.checkboxRadius, style: .continuous)
                    .fill(completing ? ThingsColor.accent : Color.clear)
                RoundedRectangle(cornerRadius: ThingsMetrics.checkboxRadius, style: .continuous)
                    .strokeBorder(completing ? Color.clear : ThingsColor.checkboxStroke, lineWidth: 1.5)
                if completing {
                    Image(systemName: "checkmark")
                        .font(.werk(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: ThingsMetrics.checkboxSize, height: ThingsMetrics.checkboxSize)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Taak afronden")
        .accessibilityLabel("Taak afronden: \(card.title)")
    }

    private func complete() {
        guard !completing else { return }
        withAnimation(.easeOut(duration: 0.15)) { completing = true }
        let title = card.title
        Task { @MainActor in
            // Het vinkje is even te zien voordat de kaart van het board verdwijnt.
            try? await Task.sleep(for: .milliseconds(350))
            BoardService.complete(card, in: context)
            appState.showToast("\"\(title)\" afgerond; te vinden in het archief")
        }
    }

    /// Tijd die al aan deze taak besteed is voordat de kaart er was (bijv. een gesprek over de mail).
    private var minutesRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .foregroundStyle(ThingsColor.textSecondary)
            Text("Reeds besteed")
                .foregroundStyle(ThingsColor.textSecondary)
            TextField("", text: $minutesDraft, prompt: Text("0"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 34)
                .focused($focus, equals: .minutes)
                .onSubmit(commitEditing)
                #if os(macOS)
                .onExitCommand(perform: cancelEditing)
                #endif
                .onChange(of: minutesDraft) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(3))
                    if digits != new { minutesDraft = digits }
                }
            Text("min").foregroundStyle(ThingsColor.textSecondary)
        }
        .cardFont(.meta)
    }

    /// De tekst van de mail, klein en binnen de kaart; lange teksten scrollen.
    private func bodyView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.werk(size: 10.5))
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { bodyHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, new in bodyHeight = new }
                    }
                )
        }
        .frame(height: min(max(bodyHeight, 20), 150) + 12)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThingsColor.tagBackground))
        .transition(.opacity)
    }

    private func toggleExpanded() { expanded.toggle() }

    // MARK: Subtaken

    @ViewBuilder private var subtaskList: some View {
        if !subtasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subtasks) { subtask in
                    HStack(alignment: .center, spacing: 4) {
                        SubtaskCheckbox(isDone: subtask.isDone) { BoardService.toggle(subtask, in: context) }
                        Text(subtask.title)
                            .cardFont(.subtask)
                            .strikethrough(subtask.isDone)
                            .foregroundStyle(subtask.isDone ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// Onderste rij: afronden, timer en (bij een mail) de mailtekst lezen. Op de Mac verschijnt rechts
    /// "Subtaak" zodra je boven de kaart zweeft.
    /// Onderaan: subtaak toevoegen links (bij aanwijzen), timer en afvinken rechts.
    private var actionRow: some View {
        HStack(spacing: 2) {
            #if os(macOS)
            if isEditable && !addingSubtask { addSubtaskButton }
            #endif
            Spacer(minLength: 4)
            TimerButton(isRunning: isTimerRunning, action: onStartTimer)
            if !editing { completeButton }
        }
    }

    private var mailButton: some View {
        Button(action: toggleExpanded) {
            Image(systemName: expanded ? "envelope.open" : "envelope")
                .font(.werk(size: 9))
                .foregroundStyle(expanded ? ThingsColor.accent : ThingsColor.textTertiary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Verberg de mailtekst" : "Lees de mail")
        .accessibilityLabel(expanded ? "Verberg de mailtekst" : "Lees de mail")
    }

    #if os(macOS)
    private var addSubtaskButton: some View {
        Button(action: startAddingSubtask) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.werk(size: 9, weight: .semibold))
                Text("Subtaak")
                    .cardFont(.meta)
            }
            .foregroundStyle(ThingsColor.textSecondary)
            .padding(.horizontal, 4)
            .frame(height: ThingsMetrics.minTapTarget * 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .help("Subtaak toevoegen")
        .accessibilityLabel("Subtaak toevoegen aan \(card.title)")
    }

    private var subtaskField: some View {
        HStack(spacing: 4) {
            Circle()
                .strokeBorder(ThingsColor.checkboxStroke, lineWidth: 1.2)
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
            TextField("Nieuwe subtaak", text: $subtaskDraft)
                .textFieldStyle(.plain)
                .cardFont(.subtask)
                .focused($focus, equals: .subtask)
                .onSubmit { commitSubtask(keepAdding: true) }
                .onExitCommand(perform: endAddingSubtask)
        }
    }
    #endif

    private func startAddingSubtask() {
        subtaskDraft = ""
        addingSubtask = true
        InlineEditing.cardID = card.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focus = .subtask
        }
    }

    /// Bewaart de subtaak. Return gaat direct door met de volgende; een leeg veld (of focus kwijt) sluit het toevoegen.
    private func commitSubtask(keepAdding: Bool) {
        guard addingSubtask else { return }
        let text = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        subtaskDraft = ""
        guard !text.isEmpty else {
            endAddingSubtask()
            return
        }
        BoardService.addSubtask(to: card, title: text, in: context)
        if keepAdding {
            ignoreFocusLoss = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                focus = .subtask
                ignoreFocusLoss = false
            }
        } else {
            endAddingSubtask()
        }
    }

    private func endAddingSubtask() {
        addingSubtask = false
        subtaskDraft = ""
        if InlineEditing.cardID == card.id && !editing { InlineEditing.cardID = nil }
    }

    // MARK: Bewerken ter plekke (nieuwe kaart)

    private func startEditing() {
        titleDraft = card.title
        minutesDraft = ""
        editing = true
        InlineEditing.cardID = card.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focus = .title
        }
    }

    /// Bewaart titel en eventueel al bestede tijd. Een nieuwe kaart die leeg blijft, wordt weer verwijderd.
    private func commitEditing() {
        guard editing else { return }
        let text = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(minutesDraft) ?? 0
        finishEditing()

        if text.isEmpty && card.title.isEmpty {
            BoardService.delete(card, in: context)
            return
        }
        if !text.isEmpty && text != card.title { card.title = text }
        if minutes > 0 {
            TimerService.logPriorTime(for: card, minutes: minutes, in: context)
            appState.showToast("\(minutes) min gelogd op \"\(card.title)\"")
        }
        try? context.save()
    }

    private func cancelEditing() {
        let wasEmptyNewCard = editing && card.title.isEmpty
        finishEditing()
        if wasEmptyNewCard { BoardService.delete(card, undoable: false, in: context) }
    }

    private func finishEditing() {
        editing = false
        if InlineEditing.cardID == card.id && !addingSubtask { InlineEditing.cardID = nil }
    }
}

/// Tekstgroottes op de kaart. Op de Mac zijn ze kleiner, zodat de tekst ook in smalle kolommen leesbaar blijft.
private enum CardText {
    case title, subtask, meta

    #if os(macOS)
    var macSize: CGFloat {
        switch self {
        case .title:   return 12.5
        case .subtask: return 11.5
        case .meta:    return 10.5
        }
    }
    #else
    var style: ThingsTextStyle {
        switch self {
        case .title:   return .todoTitle
        case .subtask: return .notes
        case .meta:    return .metadata
        }
    }
    #endif
}

private struct CardFont: ViewModifier {
    let kind: CardText

    func body(content: Content) -> some View {
        #if os(macOS)
        if kind == .title {
            // De titel volgt het thema: Drukproef groot en strak, Spark vet, de Braun-thema's medium.
            switch ThemeStore.shared.look {
            case .drukproef: content.font(.werk(size: 14.5, weight: .medium)).tracking(-0.35)
            case .spark: content.font(.werk(size: kind.macSize, weight: .semibold))
            case .wandklok, .principes, .sneeuwwitje, .karmijn: content.font(.werk(size: kind.macSize, weight: .medium))
            default: content.font(.werk(size: kind.macSize))
            }
        } else {
            content.font(.werk(size: kind.macSize))
        }
        #else
        content.thingsFont(kind.style)
        #endif
    }
}

/// De achtergrond van een kaart, zoals het thema hem tekent.
private struct CardSurface: View {
    let isRunning: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
        switch ThemeStore.shared.look {
        case .drukproef:
            // Geen kaart, alleen een haarlijn erboven.
            VStack(spacing: 0) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                Spacer(minLength: 0)
            }
        case .principes:
            shape.fill(isRunning ? ThingsColor.today : ThingsColor.cardBackground)
        case .tischsuper:
            shape.fill(ThingsColor.cardBackground)
        case .wandklok:
            shape.fill(ThingsColor.cardBackground)
                .shadow(color: ThingsColor.cardShadow, radius: 1, y: 1)
                .shadow(color: ThingsColor.cardShadow, radius: 12, y: 6)
        case .sneeuwwitje:
            shape.fill(ThingsColor.cardBackground)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: ThingsColor.cardShadow, radius: 12, y: 6)
        case .spark:
            shape.fill(ThingsColor.cardBackground)
                .overlay(shape.strokeBorder(ThingsColor.separator, lineWidth: 1))
                .shadow(color: ThingsColor.cardShadow, radius: 1, y: 1)
        case .rekenmachine:
            // Bol: licht verloop van boven en een schaduw eronder.
            shape.fill(ThingsColor.cardBackground)
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.05 : 0.45), .clear],
                                                   startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.05 : 0.7), lineWidth: 0.5))
                .shadow(color: ThingsColor.cardShadow, radius: 3, y: 2)
        case .karmijn:
            // Recht, met een donkerrode haarlijn; een lopende kaart is alleen een rood kader.
            Rectangle()
                .fill(isRunning ? Color.clear : ThingsColor.cardBackground)
                .overlay(Rectangle().strokeBorder(isRunning ? ThemeParts.karmijn : ThingsColor.separator, lineWidth: 1))
        case .standaard:
            shape.fill(ThingsColor.cardBackground)
                .shadow(color: ThingsColor.cardShadow, radius: 3, x: 0, y: 1)
        }
    }
}

/// "Loopt" met de tijd onderaan een kaart waarvan de timer loopt, in de vorm van het thema.
private struct RunningStrip: View {
    let entry: TimeEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let time = Self.format(entry.elapsed(at: context.date))
            switch ThemeStore.shared.look {
            case .drukproef:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(time)
                        .font(.werkNumbers(size: 28))
                        .tracking(-0.8)
                        .foregroundStyle(ThingsColor.today)
                    Text("— LOOPT")
                        .font(.werk(size: 10, weight: .medium))
                        .foregroundStyle(ThingsColor.textPrimary)
                }
            case .rekenmachine:
                LCDPanel(radius: 8) {
                    HStack {
                        Text("LOOPT").font(.werk(size: 9)).tracking(0.8).foregroundStyle(ThemeParts.lcdLabel)
                        Spacer()
                        Text(time).font(.werk(size: 11.5)).monospacedDigit()
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                }
            case .tischsuper:
                HStack(spacing: 8) {
                    Circle().fill(ThingsColor.running).frame(width: 7, height: 7)
                    Text("Loopt").font(.werk(size: 10.5)).foregroundStyle(ThingsColor.textSecondary)
                    Spacer()
                    Text(time).font(.werk(size: 11.5)).monospacedDigit().foregroundStyle(ThingsColor.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThingsColor.tagBackground))
            case .sneeuwwitje:
                HStack {
                    Text("Loopt").font(.werk(size: 10.5))
                    Spacer()
                    Text(time).font(.werk(size: 11.5, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(Color(hex: 0x222220))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.running))
            case .spark:
                HStack(spacing: 6) {
                    Circle().fill(ThingsColor.running).frame(width: 7, height: 7)
                    Text(time).font(.werk(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(ThingsColor.accent)
                }
            case .principes:
                HStack {
                    Text(time).font(.werk(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(ThingsColor.textPrimary)
                    Spacer()
                    ToggleKnob(height: 22)
                }
            case .karmijn:
                HStack(alignment: .firstTextBaseline) {
                    KarmijnLabel(text: "Loopt", color: ThingsColor.running, size: 9.5)
                    Spacer()
                    Text(time).font(.werkNumbers(size: 24)).foregroundStyle(ThingsColor.textPrimary)
                }
                .padding(.top, 7)
                .overlay(alignment: .top) { Rectangle().fill(ThemeParts.karmijn).frame(height: 1) }
            case .wandklok, .standaard:
                HStack {
                    Text("Loopt").font(.werk(size: 10.5)).foregroundStyle(ThingsColor.textSecondary)
                    Spacer()
                    Text(time).font(.werk(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(ThingsColor.textPrimary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Wandklok: een gele lijn onderaan de kaart die elke minuut volloopt, als een secondewijzer.
private struct SecondHandLine: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let second = Double(Calendar.current.component(.second, from: context.date))
            GeometryReader { geo in
                Rectangle()
                    .fill(ThingsColor.running)
                    .frame(width: geo.size.width * max(0.02, second / 60), height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

private extension View {
    func cardFont(_ kind: CardText) -> some View { modifier(CardFont(kind: kind)) }
}

/// Houdt bij welke kaart ter plekke bewerkt wordt (het board sleept dan geen kaart tijdens tekstselectie) en
/// welke kaart direct in bewerkmodus moet openen (net aangemaakt).
@MainActor
enum InlineEditing {
    static var cardID: UUID?
    static var pendingEditID: UUID?
}

/// Startknop voor de timer van een kaart.
struct TimerButton: View {
    var isRunning: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "waveform" : "play.fill")
                .font(.werk(size: 10, weight: .bold))
                .foregroundStyle(isRunning ? Color.white : ThingsColor.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isRunning ? ThingsColor.running : ThingsColor.accent.opacity(0.12)))
                .frame(width: ThingsMetrics.minTapTarget * 0.6, height: ThingsMetrics.minTapTarget * 0.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .help(isRunning ? "Timer loopt" : "Start timer")
        .accessibilityLabel(isRunning ? "Timer loopt" : "Start timer")
    }
}

// MARK: - Subtaken per kaart

private struct SubtasksByCardKey: EnvironmentKey {
    static var defaultValue: [UUID: [Subtask]] { [:] }
}

extension EnvironmentValues {
    /// Alle subtaken, gegroepeerd per kaart (gezet door het hoofdvenster en de boardlijst op iOS).
    var subtasksByCard: [UUID: [Subtask]] {
        get { self[SubtasksByCardKey.self] }
        set { self[SubtasksByCardKey.self] = newValue }
    }
}

/// Houdt de subtaken per kaart bij uit één query en geeft ze door aan alle kaarten eronder.
struct SubtaskProvider: ViewModifier {
    @Query(sort: \Subtask.sortOrder) private var all: [Subtask]
    @State private var grouped: [UUID: [Subtask]] = [:]

    func body(content: Content) -> some View {
        content
            .environment(\.subtasksByCard, grouped)
            // Alleen bij toevoegen of verwijderen; afvinken werkt via het object zelf.
            .onChange(of: all, initial: true) { _, new in grouped = Dictionary(grouping: new, by: \.cardID) }
    }
}

extension View {
    func providingSubtasks() -> some View { modifier(SubtaskProvider()) }
}
