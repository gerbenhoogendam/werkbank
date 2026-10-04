import SwiftData
import SwiftUI

/// Kleine ronde afvinkknop voor een subtaak (op de kaart en in het detailvenster).
struct SubtaskCheckbox: View {
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Color.clear : ThingsColor.checkboxStroke, lineWidth: 1.2)
                if isDone {
                    Circle().fill(ThingsColor.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 12, height: 12)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Subtaak afgerond, tik om te heropenen" : "Subtaak afronden")
    }
}

/// De geopende taak: titel, klant, notities en subtaken. Wijzigingen worden direct bewaard.
struct TaskDetailView: View {
    @Bindable var card: TodoCard

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var subtasks: [Subtask]

    @State private var title = ""
    @State private var label = ""
    @State private var logoDomain = ""
    @State private var newSubtask = ""
    @State private var showsMail = false
    @FocusState private var newSubtaskFocused: Bool

    init(card: TodoCard) {
        self.card = card
        let id = card.id
        _subtasks = Query(filter: #Predicate<Subtask> { $0.cardID == id }, sort: \Subtask.sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    notesSection
                    subtasksSection
                    if let text = card.bodyText, !text.isEmpty { mailSection(text) }
                }
                .padding(20)
            }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            HStack {
                Spacer()
                Button("Klaar") {
                    commitHeader()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .background(ThingsColor.backgroundContent)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560)
        #endif
        .onAppear {
            title = card.title
            label = card.clientLabel ?? ""
            logoDomain = card.logoDomain ?? ""
        }
        // Ook bewaren als het venster op een andere manier sluit (iOS: omlaag vegen).
        .onDisappear { commitHeader() }
    }

    // MARK: Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Titel", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ThingsColor.textPrimary)
            HStack(spacing: 10) {
                labeledField("Klant", text: $label, prompt: "Klantnaam")
                labeledField("Logo van domein", text: $logoDomain, prompt: "bijv. studio-noord.nl")
            }
            if let sender = card.senderLine {
                Text(sender)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func labeledField(_ name: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Notities

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notities").thingsFont(.heading).foregroundStyle(ThingsColor.textPrimary)
            TextEditor(text: $card.notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 110)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                        .fill(ThingsColor.backgroundSidebar)
                )
                .overlay(alignment: .topLeading) {
                    if card.notes.isEmpty {
                        Text("Notities bij deze taak")
                            .font(.system(size: 13))
                            .foregroundStyle(ThingsColor.textTertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: Subtaken

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Subtaken").thingsFont(.heading).foregroundStyle(ThingsColor.textPrimary)
                if !subtasks.isEmpty {
                    Text("\(subtasks.filter(\.isDone).count)/\(subtasks.count)")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .monospacedDigit()
                }
            }
            ForEach(subtasks) { subtask in
                SubtaskEditRow(subtask: subtask)
            }
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThingsColor.accent)
                    .frame(width: 22, height: 22)
                TextField("Nieuwe subtaak", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .thingsFont(.notes)
                    .focused($newSubtaskFocused)
                    .onSubmit(addSubtask)
            }
        }
    }

    private func addSubtask() {
        BoardService.addSubtask(to: card, title: newSubtask, in: context)
        newSubtask = ""
        newSubtaskFocused = true   // direct de volgende
    }

    // MARK: Mail

    private func mailSection(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $showsMail) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(ThingsColor.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text("Mailtekst").thingsFont(.heading).foregroundStyle(ThingsColor.textPrimary)
        }
    }

    // MARK: Bewaren

    /// Titel, klant en logo gaan via `BoardService.update`, zodat de koppeltabel domein → klant ook wordt bijgewerkt.
    private func commitHeader() {
        guard title != card.title || label != (card.clientLabel ?? "") || logoDomain != (card.logoDomain ?? "") else {
            try? context.save()
            return
        }
        BoardService.update(card, title: title, label: label, logoDomain: logoDomain, in: context)
    }
}

/// Eén subtaak in het detailvenster: afvinken, titel aanpassen, verwijderen.
private struct SubtaskEditRow: View {
    @Bindable var subtask: Subtask
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 6) {
            SubtaskCheckbox(isDone: subtask.isDone) { BoardService.toggle(subtask, in: context) }
            TextField("Subtaak", text: $subtask.title)
                .textFieldStyle(.plain)
                .thingsFont(.notes)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? ThingsColor.textSecondary : ThingsColor.textPrimary)
            Button {
                BoardService.delete(subtask, in: context)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Subtaak verwijderen")
            .accessibilityLabel("Verwijder subtaak \(subtask.title)")
        }
    }
}
