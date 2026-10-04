import SwiftData
import SwiftUI

/// Kaart op het board: titel, optioneel klantlabel en -logo, afzenderregel, uitklapbare mailtekst, subtaken en een
/// timerknop. Klikken op de kaart opent de taak (notities en subtaken); een nieuwe kaart opent direct in bewerkmodus.
struct CardView: View {
    let card: TodoCard
    var isTimerRunning = false
    /// Nieuwe kaarten openen in bewerkmodus; op macOS kun je onderaan een subtaak toevoegen.
    var isEditable = false
    var onStartTimer: () -> Void = {}
    /// Klik op de kaart (niet op een knop of veld).
    var onOpen: () -> Void = {}

    private enum Field: Hashable { case title, minutes, subtask }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var subtasks: [Subtask]
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

    init(card: TodoCard, isTimerRunning: Bool = false, isEditable: Bool = false,
         onStartTimer: @escaping () -> Void = {}, onOpen: @escaping () -> Void = {}) {
        self.card = card
        self.isTimerRunning = isTimerRunning
        self.isEditable = isEditable
        self.onStartTimer = onStartTimer
        self.onOpen = onOpen
        let id = card.id
        _subtasks = Query(filter: #Predicate<Subtask> { $0.cardID == id }, sort: \Subtask.sortOrder)
    }

    private var hasBody: Bool { !(card.bodyText ?? "").isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                titleRow
                if editing { minutesRow }
                labelRow
                if let sender = card.senderLine {
                    Text(sender)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentShape(Rectangle())
                        .onTapGesture { if hasBody { toggleExpanded() } else { open() } }
                }
                if expanded, let text = card.bodyText, !text.isEmpty { bodyView(text) }
                subtaskList
                #if os(macOS)
                if isEditable { addSubtaskRow }
                #endif
            }
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                TimerButton(isRunning: isTimerRunning, action: onStartTimer)
                if hasBody {
                    Button(action: toggleExpanded) {
                        Image(systemName: expanded ? "chevron.up" : "text.alignleft")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ThingsColor.textSecondary)
                            .frame(width: 22, height: 22)
                            .frame(width: ThingsMetrics.minTapTarget * 0.6, height: ThingsMetrics.minTapTarget * 0.6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Verberg de tekst" : "Toon de tekst van de mail")
                    .accessibilityLabel(expanded ? "Verberg de tekst" : "Toon de tekst")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, isEditable ? 4 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 3, x: 0, y: 1)
        )
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

    /// Klik op de kaart opent de taak, behalve tijdens bewerken ter plekke.
    private func open() {
        guard !editing, !addingSubtask else { return }
        onOpen()
    }

    // MARK: Onderdelen

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !editing { completeButton }
            if card.isNew {
                Circle()
                    .fill(ThingsColor.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Nieuw")
            }
            if editing {
                TextField("Titel", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .thingsFont(.todoTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .focused($focus, equals: .title)
                    .onSubmit(commitEditing)
                    #if os(macOS)
                    .onExitCommand(perform: cancelEditing)
                    #endif
            } else {
                Text(card.title.isEmpty ? "Nieuwe taak" : card.title)
                    .thingsFont(.todoTitle)
                    .foregroundStyle(card.title.isEmpty ? ThingsColor.textTertiary : ThingsColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: ThingsMetrics.checkboxSize, height: ThingsMetrics.checkboxSize)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
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
        .thingsFont(.metadata)
    }

    @ViewBuilder private var labelRow: some View {
        if card.logoDomain != nil || card.clientLabel != nil {
            HStack(spacing: 6) {
                if let domain = card.logoDomain {
                    LogoView(domain: domain, fallbackName: card.clientLabel ?? domain, size: 16)
                }
                if let label = card.clientLabel {
                    TagPill(name: label)
                }
            }
        }
    }

    /// De tekst van de mail, klein en binnen de kaart; lange teksten scrollen.
    private func bodyView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 10.5))
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
                            .thingsFont(.notes)
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

    #if os(macOS)
    /// Onderaan de kaart: zodra je erboven zweeft verschijnt "Subtaak toevoegen". De ruimte is altijd gereserveerd,
    /// zodat de kaart niet verspringt.
    @ViewBuilder private var addSubtaskRow: some View {
        if addingSubtask {
            HStack(spacing: 4) {
                Circle()
                    .strokeBorder(ThingsColor.checkboxStroke, lineWidth: 1.2)
                    .frame(width: 12, height: 12)
                    .frame(width: 22, height: 22)
                TextField("Nieuwe subtaak", text: $subtaskDraft)
                    .textFieldStyle(.plain)
                    .thingsFont(.notes)
                    .focused($focus, equals: .subtask)
                    .onSubmit { commitSubtask(keepAdding: true) }
                    .onExitCommand(perform: endAddingSubtask)
            }
        } else {
            Button(action: startAddingSubtask) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Subtaak toevoegen")
                        .thingsFont(.metadata)
                }
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityLabel("Subtaak toevoegen aan \(card.title)")
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
        if wasEmptyNewCard { BoardService.delete(card, in: context) }
    }

    private func finishEditing() {
        editing = false
        if InlineEditing.cardID == card.id && !addingSubtask { InlineEditing.cardID = nil }
    }
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
                .font(.system(size: 10, weight: .bold))
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
