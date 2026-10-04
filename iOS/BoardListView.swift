import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Zie `UTExportedTypeDeclarations` in project.yml.
    static let werkbankCard = UTType(exportedAs: "nl.itgwerkbank.card")
}

/// Wat bij het slepen van een kaart meegaat (alleen binnen de app).
struct CardReference: Codable, Transferable {
    var id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .werkbankCard)
    }
}

/// Board op iPhone en iPad: alle kolommen naast elkaar, horizontaal te scrollen. Houd een kaart ingedrukt om hem op
/// te pakken en naar een andere kolom (of een andere plek in dezelfde kolom) te slepen. Kolommen hernoem, voeg toe
/// en verwijder je via het menu in de kolomkop. Inplannen gaat via een blad (slepen naar de agenda past niet op een telefoon).
struct BoardListView: View {
    /// Sleutel van de kolom die het meest in beeld is; de Magic Plus voegt daar een kaart toe.
    @Binding var columnID: String?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TodoCard.sortOrder) private var cards: [TodoCard]
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @State private var editing: TodoCard?
    @State private var scheduling: TodoCard?
    @State private var columnRequest: ColumnRequest?
    /// Kolom waar op dit moment een kaart boven gehouden wordt.
    @State private var targetedColumn: String?

    private var columns: [BoardColumn] { columnRecords.map(\.column) }
    private var runningTodoID: UUID? { running.first?.todoID }

    var body: some View {
        GeometryReader { geo in
            let width = columnWidth(in: geo.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column in
                        columnView(column)
                            .frame(width: width)
                            .id(column.id)
                    }
                    addColumnTile
                        .frame(width: min(width, 150))
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: geo.size.height)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $columnID)
        }
        .background(ThingsColor.backgroundContent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { BoardService.ensureColumns(in: context) }
        // Ook na wijzigingen van buiten (iCloud): dubbele kolommen opruimen, zwevende kaarten onderbrengen.
        .onChange(of: columnRecords.count) { BoardService.ensureColumns(in: context) }
        .sheet(item: $editing) { CardEditSheet(card: $0).presentationDetents([.medium]) }
        .sheet(item: $scheduling) { ScheduleSheet(card: $0) }
        .columnManagement($columnRequest)
    }

    /// Op een telefoon is een kolom ruim 80% van het scherm, zodat de volgende zichtbaar is en je ernaartoe kunt slepen.
    private func columnWidth(in available: CGFloat) -> CGFloat {
        available < 700 ? max(available * 0.84, 240) : 340
    }

    // MARK: Kolom

    private func cards(in column: BoardColumn) -> [TodoCard] {
        cards.filter { $0.column == column }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let columnCards = cards(in: column)
        let isTargeted = targetedColumn == column.id

        return VStack(spacing: 0) {
            columnHeader(column, count: columnCards.count)

            List {
                ForEach(columnCards) { card in
                    CardView(card: card, isTimerRunning: runningTodoID == card.id) {
                        TimerService.startTimer(for: card, in: context)
                        appState.showToast("Timer gestart: \(card.title)")
                    }
                    .onTapGesture { editing = card }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .swipeActions(edge: .leading) {
                        Button {
                            TimerService.startTimer(for: card, in: context)
                            appState.showToast("Timer gestart: \(card.title)")
                        } label: { Label("Timer", systemImage: "play.fill") }
                        .tint(ThingsColor.running)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            BoardService.delete(card, in: context)
                        } label: { Label("Verwijder", systemImage: "trash") }
                    }
                    .contextMenu { menu(for: card) }
                    // Ingedrukt houden pakt de kaart op; loslaten op een andere kaart zet hem ervoor.
                    .draggable(CardReference(id: card.id))
                    .dropDestination(for: CardReference.self) { items, _ in
                        drop(items, into: column, before: card)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 72, for: .scrollContent)   // ruimte voor de Magic Plus
            .overlay {
                if columnCards.isEmpty { ThingsEmptyStateSymbol(symbol: column.symbol) }
            }
            // Loslaten onder de kaarten of in een lege kolom zet de kaart onderaan.
            .dropDestination(for: CardReference.self) { items, _ in
                drop(items, into: column, before: nil)
            } isTargeted: { targeted in
                if targeted { targetedColumn = column.id }
                else if targetedColumn == column.id { targetedColumn = nil }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(isTargeted ? column.color.opacity(0.12) : ThingsColor.backgroundSidebar)
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.title)
    }

    private func columnHeader(_ column: BoardColumn, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: column.symbol)
                .foregroundStyle(column.color)
            Text(column.title)
                .foregroundStyle(ThingsColor.textPrimary)
                .lineLimit(1)
            Text("\(count)")
                .foregroundStyle(ThingsColor.textSecondary)
                .monospacedDigit()
            Spacer()
            Menu {
                Button { columnRequest = .rename(column.id) } label: { Label("Naam wijzigen…", systemImage: "pencil") }
                Button(role: .destructive) { columnRequest = .delete(column.id) } label: {
                    Label("Kolom verwijderen…", systemImage: "trash")
                }
                .disabled(columnRecords.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: ThingsMetrics.minTapTarget, height: ThingsMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Kolomopties voor \(column.title)")
        }
        .thingsFont(.heading)
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(height: ThingsMetrics.minTapTarget)
    }

    private var addColumnTile: some View {
        Button {
            columnRequest = .add
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("Nieuwe kolom")
                    .thingsFont(.metadata)
            }
            .foregroundStyle(ThingsColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                    .strokeBorder(ThingsColor.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nieuwe kolom")
    }

    // MARK: Slepen

    /// Zet de gesleepte kaart in `column`, vóór `target` (of onderaan als er geen doelkaart is).
    private func drop(_ items: [CardReference], into column: BoardColumn, before target: TodoCard?) -> Bool {
        guard let reference = items.first, let card = cards.first(where: { $0.id == reference.id }) else { return false }
        if target?.id == card.id { return true }   // op zichzelf neergezet: niets te doen
        let others = cards(in: column).filter { $0.id != card.id }
        let index = target.flatMap { target in others.firstIndex { $0.id == target.id } } ?? others.count
        withAnimation(ThingsMotion.reorder) {
            BoardService.move(card, to: column, index: index, in: context)
        }
        return true
    }

    // MARK: Contextmenu

    @ViewBuilder private func menu(for card: TodoCard) -> some View {
        Button { editing = card } label: { Label("Bewerken…", systemImage: "pencil") }
        Button { scheduling = card } label: { Label("Inplannen…", systemImage: "calendar.badge.plus") }
        // Naast slepen: de weg zonder slepen (VoiceOver, Schakelbediening).
        Menu {
            ForEach(columns.filter { $0 != card.column }) { target in
                Button {
                    BoardService.move(card, to: target, index: 0, in: context)
                } label: { Label(target.title, systemImage: target.symbol) }
            }
        } label: { Label("Verplaats naar", systemImage: "arrow.right.circle") }
    }
}
