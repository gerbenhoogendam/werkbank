import SwiftUI

/// Kaart op het board: titel, optioneel klantlabel en -logo, afzenderregel, uitklapbare mailtekst en een timerknop.
struct CardView: View {
    let card: TodoCard
    var isTimerRunning = false
    /// Dubbelklikken op titel of label bewerkt de tekst ter plekke.
    var isEditable = false
    var onStartTimer: () -> Void = {}

    private enum Field: Hashable { case title, minutes, label }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var editing = false
    @State private var titleDraft = ""
    @State private var minutesDraft = ""
    @State private var editingLabel = false
    @State private var labelDraft = ""
    @State private var expanded = false
    @State private var bodyHeight: CGFloat = 0
    @FocusState private var focus: Field?

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
                        .onTapGesture { if hasBody { toggleExpanded() } }
                }
                if expanded, let text = card.bodyText, !text.isEmpty { bodyView(text) }
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 3, x: 0, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expanded)
        .onAppear {
            // Een nieuwe kaart (mail gesleept, plusknop) opent direct in bewerkmodus.
            if isEditable, InlineEditing.pendingEditID == card.id {
                InlineEditing.pendingEditID = nil
                startEditing()
            }
        }
        .onDisappear { finishEditing() }
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
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if isEditable { startEditing() } }
            }
        }
        .onChange(of: focus) { _, new in
            // Focus weg uit alle velden = klaar met bewerken.
            if new == nil && editing { commitEditing() }
            if new == nil && editingLabel { commitLabel() }
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
        if card.logoDomain != nil || card.clientLabel != nil || editingLabel {
            HStack(spacing: 6) {
                if let domain = card.logoDomain {
                    LogoView(domain: domain, fallbackName: card.clientLabel ?? domain, size: 16)
                }
                if editingLabel {
                    TextField("Klant", text: $labelDraft)
                        .textFieldStyle(.plain)
                        .thingsFont(.tag)
                        .frame(minWidth: 60, maxWidth: 160)
                        .focused($focus, equals: .label)
                        .onSubmit(commitLabel)
                        #if os(macOS)
                        .onExitCommand(perform: cancelEditing)
                        #endif
                } else if let label = card.clientLabel {
                    TagPill(name: label)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if isEditable { startEditingLabel() } }
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

    // MARK: Bewerken ter plekke

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

    private func startEditingLabel() {
        labelDraft = card.clientLabel ?? ""
        editingLabel = true
        InlineEditing.cardID = card.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focus = .label
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

    /// Leeg label = label verwijderen. Een gewijzigd label vult ook de koppeltabel domein → klant aan.
    private func commitLabel() {
        guard editingLabel else { return }
        let text = labelDraft
        finishEditing()
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) != (card.clientLabel ?? "") else { return }
        BoardService.update(card, title: card.title, label: text, logoDomain: card.logoDomain ?? "", in: context)
    }

    private func cancelEditing() {
        let wasEmptyNewCard = editing && card.title.isEmpty
        finishEditing()
        if wasEmptyNewCard { BoardService.delete(card, in: context) }
    }

    private func finishEditing() {
        editing = false
        editingLabel = false
        if InlineEditing.cardID == card.id { InlineEditing.cardID = nil }
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

/// Bewerken van titel, klantlabel en logodomein van een kaart.
struct CardEditSheet: View {
    let card: TodoCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var label = ""
    @State private var logoDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kaart bewerken")
                .thingsFont(.listTitle)
                .foregroundStyle(ThingsColor.textPrimary)

            field("Titel", text: $title)
            field("Klantlabel", text: $label)
            VStack(alignment: .leading, spacing: 4) {
                field("Logo van domein", text: $logoDomain, prompt: "bijv. studio-noord.nl")
                Text("Leeg laten voor geen logo. Wijzig je het label van een kaart met logodomein, dan onthoudt Werkbank die koppeling voor volgende mails.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Annuleer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Bewaar") {
                    BoardService.update(card, title: title, label: label, logoDomain: logoDomain, in: context)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 360)
        #endif
        .background(ThingsColor.backgroundContent)
        .onAppear {
            title = card.title
            label = card.clientLabel ?? ""
            logoDomain = card.logoDomain ?? ""
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }
}
