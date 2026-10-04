import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Geometrie-voorkeuren

private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ColumnFrameKey: PreferenceKey {
    static var defaultValue: [BoardColumn: CGRect] = [:]
    static func reduce(value: inout [BoardColumn: CGRect], nextValue: () -> [BoardColumn: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct StackFrameKey: PreferenceKey {
    static var defaultValue: [BoardColumn: CGRect] = [:]
    static func reduce(value: inout [BoardColumn: CGRect], nextValue: () -> [BoardColumn: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct BoardFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private enum ColumnItem: Identifiable {
    case card(TodoCard)
    case placeholder

    var id: String {
        switch self {
        case .card(let card): return card.id.uuidString
        case .placeholder:    return "placeholder"
        }
    }
}

// MARK: - Board

/// Kanban-board over de volle breedte. Standaard Inbox, Te doen, Bezig, Wacht op klant, Klaar; de kolommen zijn
/// aan te passen (hernoemen, toevoegen, verwijderen).
struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Environment(DragCoordinator.self) private var drag
    @Environment(AppState.self) private var appState
    @Query(sort: \TodoCard.sortOrder) private var cards: [TodoCard]
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @State private var editing: TodoCard?
    @State private var columnRequest: ColumnRequest?
    /// Kolom waar op dit moment een bestand/mail boven gehouden wordt.
    @State private var dropTargetColumn: BoardColumn?
    @GestureState private var gestureActive = false

    private var runningTodoID: UUID? { running.first?.todoID }
    private var columns: [BoardColumn] { columnRecords.map(\.column) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(columns) { column in
                columnView(column)
            }
            addColumnButton
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ThingsColor.backgroundContent)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BoardFrameKey.self, value: geo.frame(in: .main))
            }
        )
        // Eén sleepgebaar voor het hele board (niet per kaart): het blijft bestaan terwijl kaarten
        // tijdens het slepen worden verwijderd, verplaatst en opnieuw opgebouwd.
        // Slepen start na ca. 5 px beweging; korter telt als klik.
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .main)
                .updating($gestureActive) { _, state, _ in state = true }
                .onChanged { value in
                    if drag.phase == .idle {
                        // Tijdens tekst bewerken hoort een sleep bij de tekstselectie, niet bij de kaart.
                        guard InlineEditing.cardID == nil,
                              let card = card(at: value.startLocation),
                              let frame = drag.cardFrames[card.id] else { return }
                        drag.begin(card: card, frame: frame, pointer: value.startLocation, order: currentOrder())
                    }
                    drag.update(pointer: value.location)
                }
                .onEnded { value in drag.end(pointer: value.location) }
        )
        // Gebaar verdwenen zonder onEnded (focusverlies e.d.): kaart terugzetten, niet blijven hangen.
        .onChange(of: gestureActive) { _, active in
            guard !active else { return }
            // Een gewoon einde zet de fase eerst op .landing; pas als die na een korte wachttijd nog op
            // .dragging staat is het gebaar zonder onEnded verdwenen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                if drag.phase == .dragging { drag.cancel() }
            }
        }
        .onPreferenceChange(CardFrameKey.self) { drag.cardFrames = $0 }
        .onPreferenceChange(ColumnFrameKey.self) { drag.columnFrames = $0 }
        .onPreferenceChange(StackFrameKey.self) { drag.stackFrames = $0 }
        .onPreferenceChange(BoardFrameKey.self) { drag.boardFrame = $0 }
        .onAppear {
            BoardService.ensureColumns(in: context)
            drag.onBoardDrop = { card, column, index in
                BoardService.move(card, to: column, index: index, in: context)
            }
        }
        // Ook na wijzigingen van buiten (iCloud): dubbele kolommen opruimen, zwevende kaarten onderbrengen.
        .onChange(of: columnRecords.count) { BoardService.ensureColumns(in: context) }
        .sheet(item: $editing) { CardEditSheet(card: $0) }
        .columnManagement($columnRequest)
    }

    /// Smalle knop rechts van de laatste kolom.
    private var addColumnButton: some View {
        Button {
            columnRequest = .add
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(width: 34)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                        .strokeBorder(ThingsColor.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Nieuwe kolom")
        .accessibilityLabel("Nieuwe kolom")
    }

    // MARK: Kolom

    private func cards(in column: BoardColumn) -> [TodoCard] {
        // In de view sorteren, zodat de volgorde direct meebeweegt met de model-wijziging na het neerzetten.
        cards.filter { $0.column == column }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func items(for column: BoardColumn) -> [ColumnItem] {
        let columnCards = cards(in: column)
        guard drag.isDragging, let target = drag.target, target.column == column else {
            return columnCards.map { .card($0) }
        }
        var result: [ColumnItem] = []
        var seen = 0
        var inserted = false
        for card in columnCards {
            if card.id == drag.card?.id { continue }   // wordt door DragOverlay getekend
            if seen == target.index && !inserted {
                result.append(.placeholder)
                inserted = true
            }
            result.append(.card(card))
            seen += 1
        }
        if !inserted { result.append(.placeholder) }
        return result
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let columnCards = cards(in: column)
        let isTarget = (drag.region == .board && drag.target?.column == column && drag.isDragging)
            || dropTargetColumn == column

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: column.symbol)
                        .foregroundStyle(column.color)
                    Text(column.title)
                        .foregroundStyle(ThingsColor.textPrimary)
                    Spacer()
                    Text("\(columnCards.count)")
                        .foregroundStyle(ThingsColor.textSecondary)
                        .monospacedDigit()
                }
                .thingsFont(.heading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(column.title), \(columnCards.count) kaarten")

                // Nieuwe kaart direct in deze kolom; de titel staat meteen in bewerkmodus.
                Button {
                    let card = BoardService.addCard(title: "", column: column, in: context)
                    InlineEditing.pendingEditID = card.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThingsColor.accent)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Nieuwe kaart in \(column.title)")
                .accessibilityLabel("Nieuwe kaart in \(column.title)")

                Menu {
                    Button("Naam wijzigen…") { columnRequest = .rename(column.id) }
                    Button("Kolom verwijderen…", role: .destructive) { columnRequest = .delete(column.id) }
                        .disabled(columnRecords.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Kolom hernoemen of verwijderen")
                .accessibilityLabel("Kolomopties voor \(column.title)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle().fill(ThingsColor.separator).frame(height: 1).padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items(for: column)) { item in
                        switch item {
                        case .card(let card):
                            cell(card, in: column)
                        case .placeholder:
                            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                                .strokeBorder(ThingsColor.accent.opacity(0.55),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .background(
                                    RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                                        .fill(ThingsColor.accent.opacity(0.06))
                                )
                                .frame(height: drag.cardSize.height)
                                .padding(.bottom, DragCoordinator.cardSpacing)
                                .transition(.opacity)
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: StackFrameKey.self, value: [column: geo.frame(in: .main)])
                    }
                )
                .animation(ThingsMotion.reorder, value: drag.target)
                .animation(ThingsMotion.reorder, value: items(for: column).map(\.id))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(isTarget ? column.color.opacity(0.10) : ThingsColor.backgroundSidebar)
                .animation(.easeOut(duration: 0.15), value: isTarget)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ColumnFrameKey.self, value: [column: geo.frame(in: .main)])
            }
        )
        // Een mail (.eml, of een mail uit het Gmail-paneel) op een kolom slepen zet de kaart in die kolom.
        .onDrop(of: [.emailMessage, .fileURL, .gmailMessage], isTargeted: Binding(
            get: { dropTargetColumn == column },
            set: { targeted in
                if targeted { dropTargetColumn = column }
                else if dropTargetColumn == column { dropTargetColumn = nil }
            }
        )) { providers in
            if GmailDrop.accepts(providers) {
                return GmailDrop.handle(providers: providers, column: column, context: context, appState: appState)
            }
            return MailImporter.handle(providers: providers, column: column, context: context, appState: appState)
        }
    }

    // MARK: Kaart

    private func cell(_ card: TodoCard, in column: BoardColumn) -> some View {
        BoardCardCell(
            card: card,
            isTimerRunning: runningTodoID == card.id,
            onStartTimer: { TimerService.startTimer(for: card, in: context) },
            onEdit: { editing = card },
            onDelete: { BoardService.delete(card, in: context) }
        )
    }

    /// De kaart onder een punt (in "main"-coördinaten), alleen binnen het zichtbare deel van zijn kolom.
    private func card(at point: CGPoint) -> TodoCard? {
        cards.first { card in
            guard let frame = drag.cardFrames[card.id], frame.contains(point),
                  let column = drag.columnFrames[card.column] else { return false }
            return column.contains(point)
        }
    }

    private func currentOrder() -> [BoardColumn: [UUID]] {
        Dictionary(uniqueKeysWithValues: columns.map { column in
            (column, cards(in: column).map(\.id))
        })
    }
}

// MARK: - Kaartcel met sleepgebaar

private struct BoardCardCell: View {
    let card: TodoCard
    let isTimerRunning: Bool
    let onStartTimer: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(DragCoordinator.self) private var drag
    @Environment(AppState.self) private var appState
    @State private var popScale: CGFloat = 1
    @State private var highlight = false

    var body: some View {
        CardView(card: card, isTimerRunning: isTimerRunning, isEditable: true) {
            onStartTimer()
            appState.showToast("Timer gestart: \(card.title)")
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CardFrameKey.self, value: [card.id: geo.frame(in: .main)])
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.accent.opacity(highlight ? 0.22 : 0))
                .allowsHitTesting(false)
        )
        .scaleEffect(popScale)
        .padding(.bottom, DragCoordinator.cardSpacing)
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        .contextMenu {
            Button("Bewerken…", action: onEdit)
            Button("Verwijderen", role: .destructive, action: onDelete)
        }
        .onChange(of: drag.popID) { _, new in
            if new == card.id { runPop() }
        }
        .onAppear {
            if drag.popID == card.id { runPop() }
            // Nieuwe kaart (snelle invoer of mail): korte highlight na het inschuiven.
            if Date().timeIntervalSince(card.createdAt) < 1.5 {
                highlight = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeOut(duration: 1.0)) { highlight = false }
                }
            }
        }
    }

    /// Kleine "pop" na het neerzetten: schaal 1,03 → 0,97 → 1.
    private func runPop() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.08)) { popScale = 1.03 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.08)) { popScale = 0.97 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { popScale = 1 }
            if drag.popID == card.id { drag.popID = nil }
        }
    }
}

// MARK: - Zwevende kaart

/// De gesleepte kaart, boven alle panelen getekend.
struct DragOverlay: View {
    @Environment(DragCoordinator.self) private var drag

    private var landingAnimation: Animation? {
        guard drag.phase == .landing else { return nil }
        // Naar de agenda: kleiner wordend erin; naar het board: licht doorverend naar de placeholder.
        return drag.region == .agenda ? .easeIn(duration: 0.2) : .spring(response: 0.22, dampingFraction: 0.72)
    }

    var body: some View {
        if drag.isDragging, let card = drag.card {
            CardView(card: card)
                .frame(width: drag.cardSize.width)
                .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
                .scaleEffect(drag.overlayScale)
                .animation(.easeOut(duration: 0.15), value: drag.overlayScale)
                .rotationEffect(.degrees(drag.tilt))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: drag.tilt)
                .opacity(drag.overlayOpacity)
                .animation(.easeIn(duration: 0.2), value: drag.overlayOpacity)
                .offset(x: drag.overlayOrigin.x, y: drag.overlayOrigin.y)
                // Tijdens het slepen volgt de kaart de cursor exact; alleen bij het landen animeren.
                .animation(landingAnimation, value: drag.overlayOrigin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
