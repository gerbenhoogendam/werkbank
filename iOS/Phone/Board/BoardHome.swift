import SwiftData
import SwiftUI
import WerkbankCore

/// Het board op de iPhone: één kolom tegelijk (keuze bovenaan), snel een taak toevoegen, compacte taakkaarten; of alle
/// kolommen naast elkaar. Afvinken rondt af (archief), vegen verplaatst naar de volgende kolom, start de timer, rondt
/// af of verwijdert. Gedaan toont wat er vandaag is afgerond.
struct BoardHome: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<TodoCard> { $0.columnRaw != "done" }, sort: \TodoCard.sortOrder)
    private var cards: [TodoCard]
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    /// Tijd die op kaarten is geschreven (voor de minuten per kaart).
    @Query(filter: #Predicate<TimeEntry> { $0.todoID != nil }) private var cardEntries: [TimeEntry]
    /// Afgeronde taken (voor het aantal van vandaag op de knop Gedaan).
    @Query(filter: #Predicate<TodoCard> { $0.columnRaw == "done" }) private var doneCards: [TodoCard]

    /// De gekozen kolom, per apparaat.
    @AppStorage("phone.board.column") private var selectedID = BoardColumn.inboxID
    /// Alle kolommen naast elkaar in plaats van één kolom, per apparaat.
    @AppStorage("phone.board.kanban") private var kanban = false
    @State private var showsDone = false
    @State private var newTask: BoardNewTaskStart?
    @State private var draft = ""
    @State private var editing: TodoCard?
    /// De kaart die openstaat na vegen.
    @State private var swipedOpen: String?
    /// Afgevinkt; de kaart gaat even later naar het archief.
    @State private var completing: Set<UUID> = []
    @FocusState private var addFocused: Bool

    private var columns: [BoardColumn] { columnRecords.map(\.column) }

    var body: some View {
        let columns = self.columns
        let grouped = BoardService.grouped(cards, into: columns)
        let selected = columns.first { $0.id == selectedID } ?? columns.first ?? BoardColumn.inbox
        let columnCards = grouped[selected.id] ?? []
        let minutes = minutesByCard()
        let running = Set(cardEntries.filter { $0.status == .running }.compactMap(\.todoID))

        VStack(alignment: .leading, spacing: 12) {
            PhHeader(eyebrow: "\(cards.count) OPEN", title: "Board") {
                headerButtons
            }
            if kanban {
                BoardKanban(columns: columns, grouped: grouped, minutes: minutes, running: running,
                            onOpen: { editing = $0 },
                            onAdd: { newTask = BoardNewTaskStart(column: $0, dictate: false) }) { card in
                    menu(for: card, columns: columns)
                }
            } else {
                columnPicker(columns, grouped: grouped, selected: selected)
                    .padding(.horizontal, 16)
                quickAdd(selected)
                list(columnCards, in: selected, columns: columns, minutes: minutes, running: running)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .phScreen()
        .onAppear { BoardService.ensureColumns(in: context) }
        // Ook na wijzigingen van buiten (iCloud): dubbele kolommen opruimen.
        .onChange(of: columnRecords.count) { BoardService.ensureColumns(in: context) }
        .sheet(item: $editing) { card in
            TaskDetailView(card: card)
                .presentationDetents([.medium, .large])
                .presentationBackground(Ph.paper)
        }
        .sheet(isPresented: $showsDone) {
            BoardDoneView()
        }
        .sheet(item: $newTask) { start in
            BoardNewTaskSheet(start: start, columns: columns)
        }
    }

    // MARK: Kop

    private var doneToday: Int {
        doneCards.filter { card in
            guard let date = card.completedAt else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
    }

    /// Gedaan vandaag (vinkje en aantal) en de keuze tussen één kolom en alle kolommen.
    private var headerButtons: some View {
        HStack(spacing: 6) {
            Button {
                showsDone = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(doneToday)")
                        .font(Ph.poster(20))
                }
                .foregroundStyle(Ph.ink)
                .padding(.horizontal, 11)
                .frame(height: 44)
                .background(Rectangle().fill(Ph.card)
                    .shadow(color: Ph.ink.opacity(0.08), radius: 0, y: 1)
                    .shadow(color: Ph.ink.opacity(0.06), radius: 3, y: 2))
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gedaan vandaag, \(doneToday)")
            HStack(spacing: 3) {
                layoutButton(showsColumns: false, symbol: "list.bullet", label: "Lijst")
                layoutButton(showsColumns: true, symbol: "rectangle.split.3x1", label: "Kolommen")
            }
            .padding(3)
            .phWell()
        }
    }

    private func layoutButton(showsColumns value: Bool, symbol: String, label: String) -> some View {
        let on = kanban == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { kanban = value }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Ph.ink : Ph.ink2)
                .frame(width: 36, height: 32)
                .background {
                    if on {
                        Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                            .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                            .shadow(color: Ph.ink.opacity(0.12), radius: 2, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Kolommen

    /// Korte naam in de keuze ("Wacht op klant" → "Wacht") als er vier of meer kolommen naast elkaar staan.
    private func shortTitle(_ column: BoardColumn, count: Int) -> String {
        guard count >= 4, column.title.count > 9 else { return column.title }
        return column.title.split(separator: " ").first.map(String.init) ?? column.title
    }

    @ViewBuilder
    private func columnPicker(_ columns: [BoardColumn], grouped: [String: [TodoCard]],
                              selected: BoardColumn) -> some View {
        if columns.count <= 4 {
            let items = columns.map { column in
                PhSegmented<String>.Item(value: column.id, title: shortTitle(column, count: columns.count),
                                         count: grouped[column.id]?.count ?? 0)
            }
            PhSegmented(items: items, selection: Binding(get: { selected.id }, set: { selectedID = $0 }), height: 40)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(columns) { column in
                        PhChip(title: "\(column.title) \(grouped[column.id]?.count ?? 0)", isOn: column == selected) {
                            withAnimation(.easeOut(duration: 0.15)) { selectedID = column.id }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func nextColumn(after column: BoardColumn, in columns: [BoardColumn]) -> BoardColumn? {
        guard let index = columns.firstIndex(of: column), index + 1 < columns.count else { return nil }
        return columns[index + 1]
    }

    // MARK: Snel toevoegen

    private func quickAdd(_ column: BoardColumn) -> some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ph.ink2)
                .frame(width: 30)
                .accessibilityHidden(true)
            TextField("Nieuwe taak", text: $draft)
                .font(Ph.text(15))
                .foregroundStyle(Ph.ink)
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit { add(to: column) }
                .frame(minHeight: 40)
            // Leeg: inspreken of uitgebreid invoeren (blad Nieuwe taak); met tekst: toevoegen.
            Button {
                if empty {
                    newTask = BoardNewTaskStart(column: column, dictate: PhoneDictation.isEnabled)
                } else {
                    add(to: column)
                }
            } label: {
                Image(systemName: empty ? "mic.fill" : "plus")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(PhPrimaryStyle(height: 40))
            .frame(width: 40)
            .accessibilityLabel(empty ? "Dicteer een taak" : "Voeg toe aan \(column.title)")
        }
        .padding(4)
        .phWell()
        .padding(.horizontal, 16)
    }

    private func add(to column: BoardColumn) {
        guard BoardService.addQuickEntry(draft, column: column, in: context) != nil else { return }
        draft = ""
        appState.showToast("Toegevoegd aan \(column.title)")
    }

    // MARK: Kaarten

    /// Geschreven en lopende tijd per kaart, in minuten.
    private func minutesByCard() -> [UUID: Int] {
        var seconds: [UUID: TimeInterval] = [:]
        let now = Date()
        for entry in cardEntries {
            guard let id = entry.todoID else { continue }
            seconds[id, default: 0] += entry.status == .finished ? entry.accumulated : entry.elapsed(at: now)
        }
        return seconds.mapValues { Int(($0 / 60).rounded()) }
    }

    private func list(_ columnCards: [TodoCard], in column: BoardColumn, columns: [BoardColumn],
                      minutes: [UUID: Int], running: Set<UUID>) -> some View {
        let next = nextColumn(after: column, in: columns)
        return List {
            if columnCards.isEmpty {
                PhCaps(text: "Leeg", size: 11, color: Ph.ink3)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(columnCards) { card in
                PhSwipeRow(id: card.id.uuidString, openID: $swipedOpen, background: .clear,
                           leading: leadingActions(card, next: next),
                           trailing: [
                               PhSwipeAction(id: "afronden", symbol: "checkmark", label: "Afronden", primary: true) {
                                   complete(card)
                               },
                               PhSwipeAction(id: "verwijder", symbol: "trash", label: "Verwijder") {
                                   withAnimation { BoardService.delete(card, in: context) }
                               },
                           ],
                           fullTrailing: false,
                           onTap: { editing = card }) {
                    BoardTaskRow(card: card, minutes: minutes[card.id] ?? 0, isRunning: running.contains(card.id),
                                 isCompleting: completing.contains(card.id)) {
                        complete(card)
                    } onOpen: {
                        editing = card
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                .contextMenu { menu(for: card, columns: columns) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .contentMargins(.bottom, 16, for: .scrollContent)
    }

    /// Naar rechts vegen: naar de volgende kolom (limoen, ook bij helemaal doorvegen) en de timer starten.
    private func leadingActions(_ card: TodoCard, next: BoardColumn?) -> [PhSwipeAction] {
        var actions: [PhSwipeAction] = []
        if let next {
            actions.append(PhSwipeAction(id: "volgende", symbol: "arrow.right", label: "Naar \(next.title)", primary: true) {
                withAnimation { BoardService.move(card, to: next, index: 0, undoable: true, in: context) }
                appState.showToast("Naar \(next.title)")
            })
        }
        actions.append(PhSwipeAction(id: "timer", symbol: "play.fill", label: "Timer", primary: next == nil) {
            TimerService.startTimer(for: card, in: context)
            appState.showToast("Timer gestart: \(card.title)")
        })
        return actions
    }

    @ViewBuilder private func menu(for card: TodoCard, columns: [BoardColumn]) -> some View {
        Button { editing = card } label: { Label("Openen", systemImage: "square.and.pencil") }
        Button { complete(card) } label: { Label("Afronden", systemImage: "checkmark.square") }
        Button {
            TimerService.startTimer(for: card, in: context)
            appState.showToast("Timer gestart: \(card.title)")
        } label: { Label("Timer starten", systemImage: "play.fill") }
        Menu {
            ForEach(columns.filter { $0.id != card.columnRaw }) { target in
                Button(target.title) {
                    withAnimation { BoardService.move(card, to: target, index: 0, undoable: true, in: context) }
                }
            }
        } label: { Label("Verplaats naar", systemImage: "arrow.right.square") }
        Button(role: .destructive) {
            withAnimation { BoardService.delete(card, in: context) }
        } label: { Label("Verwijder", systemImage: "trash") }
    }

    /// Vinkje zetten, even laten staan, dan naar het archief (zoals op het oude board).
    private func complete(_ card: TodoCard) {
        let id = card.id
        guard !completing.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.15)) { _ = completing.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if let card = BoardService.card(withID: id, in: context) {
                let title = card.title
                withAnimation { BoardService.complete(card, in: context) }
                appState.showToast("\"\(title)\" afgerond")
            }
            completing.remove(id)
        }
    }
}

// MARK: - Taakkaart

/// Een compacte taak: vinkje, titel, klant, minuten, envelop als hij uit een mail komt, "loopt" bij een timer.
struct BoardTaskRow: View {
    let card: TodoCard
    let minutes: Int
    let isRunning: Bool
    let isCompleting: Bool
    let onCheck: () -> Void
    let onOpen: () -> Void

    private var fromMail: Bool { card.mailThreadID != nil || card.senderLine != nil }

    private var edge: Color {
        if isRunning { return Ph.lime }
        if card.isNew { return Ph.olive }
        return Ph.line
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCheck) {
                PhCheck(isOn: isCompleting)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -5)
            .padding(.leading, -6)
            .padding(.trailing, -6)
            .accessibilityLabel("\(card.title) klaar")

            VStack(alignment: .leading, spacing: 5) {
                Text(card.title.isEmpty ? "Nieuwe taak" : card.title)
                    .font(Ph.text(14.5, .medium))
                    .foregroundStyle(isCompleting ? Ph.ink3 : Ph.ink)
                    .strikethrough(isCompleting, color: Ph.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if let label = card.clientLabel, !label.isEmpty {
                        PhBoxTag(text: label)
                            .lineLimit(1)
                    }
                    if minutes > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .medium))
                            Text("\(minutes) MIN")
                                .font(Ph.text(11))
                                .monospacedDigit()
                        }
                    }
                    if fromMail {
                        Image(systemName: "envelope")
                            .font(.system(size: 11, weight: .medium))
                            .accessibilityLabel("Uit mail")
                    }
                    Spacer(minLength: 0)
                    if isRunning {
                        PhCaps(text: "Loopt", size: 10, color: Ph.late)
                    }
                }
                .foregroundStyle(Ph.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
    }
}
