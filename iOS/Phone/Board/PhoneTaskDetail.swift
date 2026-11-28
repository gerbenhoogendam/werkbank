import SwiftData
import SwiftUI

/// Een taak openen op de iPhone, in de stijl Etiket: titel, klant, notities, subtaken en de mailtekst. Wijzigingen
/// worden meteen bewaard. Onderaan afvinken (klaar, naar het archief), archiveren (afvinken én de mail waar de taak
/// uit komt archiveren; alleen bij een taak uit een mail) en KLAAR (klaar met bewerken).
struct PhoneTaskDetailView: View {
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

    private var hasMail: Bool { card.mailThreadID != nil && card.mailAccount != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("TAAK")
                        .font(Ph.poster(32))
                        .foregroundStyle(Ph.ink)
                    TextField("Titel", text: $title, axis: .vertical)
                        .font(Ph.text(17, .semibold))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .phCard(border: Ph.ink)
                    HStack(spacing: 6) {
                        field("Klant") {
                            TextField("Geen klant", text: $label)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                        }
                        field("Logo van domein") {
                            TextField("studio-noord.nl", text: $logoDomain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                    }
                    if let sender = card.senderLine {
                        Text(sender).font(Ph.text(12)).foregroundStyle(Ph.ink2).textSelection(.enabled)
                    }
                    notes
                    subtaskList
                    if let text = card.bodyText, !text.isEmpty { mailText(text) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            buttons
        }
        .background(Ph.paper.ignoresSafeArea())
        .tint(Ph.ink)
        .onAppear {
            title = card.title
            label = card.clientLabel ?? ""
            logoDomain = card.logoDomain ?? ""
        }
        // Ook bewaren als het blad op een andere manier sluit (omlaag vegen).
        .onDisappear { commitHeader() }
    }

    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PhCaps(text: name, size: 9.5, color: Ph.olive)
            content()
                .font(Ph.text(15, .semibold))
                .foregroundStyle(Ph.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .phCard()
    }

    // MARK: Notities en subtaken

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: "Notities", size: 11)
            TextEditor(text: $card.notes)
                .font(Ph.text(15))
                .foregroundStyle(Ph.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 110)
                .phWell(Ph.card)
                .overlay(alignment: .topLeading) {
                    if card.notes.isEmpty {
                        Text("Notities bij deze taak")
                            .font(Ph.text(15))
                            .foregroundStyle(Ph.ink3)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PhCaps(text: "Subtaken", size: 11)
                if !subtasks.isEmpty {
                    PhCaps(text: "\(subtasks.filter(\.isDone).count)/\(subtasks.count)", size: 11, color: Ph.olive)
                }
            }
            VStack(spacing: 0) {
                ForEach(subtasks) { subtask in
                    PhoneSubtaskRow(subtask: subtask)
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ph.ink)
                        .frame(width: 22, height: 22)
                    TextField("Nieuwe subtaak", text: $newSubtask)
                        .font(Ph.text(15))
                        .focused($newSubtaskFocused)
                        .submitLabel(.next)
                        .onSubmit(addSubtask)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
            }
            .phCard()
        }
    }

    private func addSubtask() {
        BoardService.addSubtask(to: card, title: newSubtask, in: context)
        newSubtask = ""
        newSubtaskFocused = true
    }

    private func mailText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsMail.toggle() }
            } label: {
                HStack(spacing: 6) {
                    PhCaps(text: "Mailtekst", size: 11)
                    Image(systemName: showsMail ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ph.ink2)
                }
            }
            .buttonStyle(.plain)
            if showsMail {
                Text(text)
                    .font(Ph.mail(14))
                    .foregroundStyle(Ph.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .phCard()
            }
        }
    }

    // MARK: Knoppen

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { complete(archivingMail: false) } label: { iconFace("checkmark", primary: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("Afvinken")
            if hasMail {
                Button { complete(archivingMail: true) } label: { iconFace("archivebox", primary: false) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Afvinken en mail archiveren")
            }
            Button("KLAAR") {
                commitHeader()
                dismiss()
            }
            .buttonStyle(PhSecondaryStyle(height: 50))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    private func iconFace(_ symbol: String, primary: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Ph.ink)
            .frame(width: 58, height: 47)
            .background(primary ? Ph.lime : Ph.card)
            .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
            .background(Rectangle().fill(Ph.ink).offset(y: 3))
            .padding(.bottom, 3)
    }

    /// Afvinken: de taak naar het archief (Gedaan). Met `archivingMail` gaat ook de mail waar hij uit komt uit de inbox.
    /// Zes seconden om het terug te draaien (de balk boven de tabbalk).
    private func complete(archivingMail: Bool) {
        commitHeader()
        let id = card.id
        let title = card.title
        let before = CardPlace(card)
        let thread: (threadID: String, account: String)? = archivingMail
            ? card.mailThreadID.flatMap { threadID in card.mailAccount.map { (threadID: threadID, account: $0) } } : nil
        BoardService.complete(card, in: context)
        dismiss()
        Task { @MainActor in
            var archived = false
            if let thread { archived = await PhoneGmail.shared.archive([thread]) > 0 }
            PhoneUndo.shared.show(archived ? "Afgerond en gearchiveerd" : "Afgerond", detail: title, icon: "checkmark") {
                if let card = BoardService.card(withID: id, in: context) {
                    withAnimation { before.restore(card) }
                    try? context.save()
                }
                if archived, let thread { await PhoneGmail.shared.unarchive([thread]) }
            }
        }
    }

    private func commitHeader() {
        guard title != card.title || label != (card.clientLabel ?? "") || logoDomain != (card.logoDomain ?? "") else {
            try? context.save()
            return
        }
        BoardService.update(card, title: title, label: label, logoDomain: logoDomain, in: context)
    }
}

/// Eén subtaak: vierkant vinkje, titel aanpassen, weghalen.
private struct PhoneSubtaskRow: View {
    @Bindable var subtask: Subtask
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { BoardService.toggle(subtask, in: context) }
            } label: {
                PhCheck(isOn: subtask.isDone, size: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isDone ? "Subtaak heropenen" : "Subtaak afvinken")
            TextField("Subtaak", text: $subtask.title)
                .font(Ph.text(15))
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? Ph.ink3 : Ph.ink)
            Button {
                BoardService.delete(subtask, in: context)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ph.ink3)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Subtaak weghalen")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }
}
