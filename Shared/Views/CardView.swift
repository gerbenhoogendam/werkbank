import SwiftUI

/// Kaart op het board: titel, optioneel klantlabel en -logo, afzenderregel en een timerknop.
struct CardView: View {
    let card: TodoCard
    var isTimerRunning = false
    /// Dubbelklikken op titel of label bewerkt de tekst ter plekke.
    var isEditable = false
    var onStartTimer: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingLabel = false
    @State private var labelDraft = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var labelFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if card.isNew {
                        Circle()
                            .fill(ThingsColor.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Nieuw")
                    }
                    if editingTitle {
                        TextField("Titel", text: $titleDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .thingsFont(.todoTitle)
                            .foregroundStyle(ThingsColor.textPrimary)
                            .focused($titleFocused)
                            .onSubmit(commitTitle)
                            #if os(macOS)
                            .onExitCommand(perform: cancelEditing)
                            #endif
                            .onChange(of: titleFocused) { _, focused in
                                if !focused && editingTitle { commitTitle() }
                            }
                    } else {
                        Text(card.title)
                            .thingsFont(.todoTitle)
                            .foregroundStyle(ThingsColor.textPrimary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { if isEditable { startEditingTitle() } }
                    }
                }

                if card.logoDomain != nil || card.clientLabel != nil {
                    HStack(spacing: 6) {
                        if let domain = card.logoDomain {
                            LogoView(domain: domain, fallbackName: card.clientLabel ?? domain, size: 16)
                        }
                        if editingLabel {
                            TextField("Klant", text: $labelDraft)
                                .textFieldStyle(.plain)
                                .thingsFont(.tag)
                                .frame(minWidth: 60, maxWidth: 160)
                                .focused($labelFocused)
                                .onSubmit(commitLabel)
                                #if os(macOS)
                                .onExitCommand(perform: cancelEditing)
                                #endif
                                .onChange(of: labelFocused) { _, focused in
                                    if !focused && editingLabel { commitLabel() }
                                }
                        } else if let label = card.clientLabel {
                            TagPill(name: label)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { if isEditable { startEditingLabel() } }
                        }
                    }
                }

                if let sender = card.senderLine {
                    Text(sender)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            TimerButton(isRunning: isTimerRunning, action: onStartTimer)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 3, x: 0, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
        .onDisappear { finishEditing() }
    }

    // MARK: Bewerken ter plekke

    private func startEditingTitle() {
        titleDraft = card.title
        editingTitle = true
        InlineEditing.cardID = card.id
        Task { @MainActor in titleFocused = true }
    }

    private func startEditingLabel() {
        labelDraft = card.clientLabel ?? ""
        editingLabel = true
        InlineEditing.cardID = card.id
        Task { @MainActor in labelFocused = true }
    }

    private func commitTitle() {
        guard editingTitle else { return }
        let text = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finishEditing()
        guard !text.isEmpty, text != card.title else { return }
        card.title = text
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

    private func cancelEditing() { finishEditing() }

    private func finishEditing() {
        editingTitle = false
        editingLabel = false
        if InlineEditing.cardID == card.id { InlineEditing.cardID = nil }
    }
}

/// Houdt bij welke kaart ter plekke bewerkt wordt, zodat het board tijdens tekstselectie geen kaart gaat slepen.
@MainActor
enum InlineEditing {
    static var cardID: UUID?
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
