import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

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

extension UTType {
    /// Zie `UTExportedTypeDeclarations` in project.yml.
    static let werkbankColumn = UTType(exportedAs: "nl.itgwerkbank.column")
}

/// Wat bij het slepen van een kolom meegaat (alleen binnen de app).
struct ColumnReference: Codable, Transferable {
    var key: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .werkbankColumn)
    }
}

/// Board op iPhone en iPad: de kolommen onder elkaar in één lijst, elke kolom met een kop die je in- en uitklapt.
/// Houd een kaart ingedrukt om hem op te pakken en naar een andere kolom (of een andere plek in dezelfde kolom) te
/// slepen; loslaten op een kolomkop zet hem bovenaan die kolom. Een kaart toevoegen gaat met de plus in de kolomkop;
/// kolommen hernoem, voeg toe en verwijder je via het menu ernaast; door aan de kolomkop te slepen verplaats je een
/// kolom.
struct BoardListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<TodoCard> { $0.columnRaw != "done" }, sort: \TodoCard.sortOrder) private var cards: [TodoCard]
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    /// Ingeklapte kolommen (sleutels, met komma's), per apparaat.
    @AppStorage("board.collapsedColumns") private var collapsedRaw = ""
    @State private var editing: TodoCard?
    /// Kolom waarin een nieuwe kaart komt (plus in de kolomkop).
    @State private var addingTo: BoardColumn?
    @State private var columnRequest: ColumnRequest?
    /// Kolom waar op dit moment een kaart boven gehouden wordt.
    @State private var targetedColumn: String?
    /// Kolom waar op dit moment een andere kolom boven gehouden wordt.
    @State private var columnDropTarget: String?

    private var columns: [BoardColumn] { columnRecords.map(\.column) }
    private var runningTodoIDs: Set<UUID> { Set(running.compactMap(\.todoID)) }
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        boardContent.providingSubtasks()
    }

    private var boardContent: some View {
        List {
            ForEach(columns) { column in
                section(column)
            }
            addColumnTile
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
                // Een kolom hier loslaten zet hem helemaal onderaan.
                .dropDestination(for: ColumnReference.self) { items, _ in
                    guard let reference = items.first else { return false }
                    withAnimation(ThingsMotion.reorder) {
                        BoardService.moveColumn(key: reference.key, toIndex: columns.count, in: context)
                    }
                    return true
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .contentMargins(.bottom, 72, for: .scrollContent)   // ruimte voor de Magic Plus
        .background(ThingsColor.backgroundContent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { BoardService.ensureColumns(in: context) }
        // Ook na wijzigingen van buiten (iCloud): dubbele kolommen opruimen, zwevende kaarten onderbrengen.
        .onChange(of: columnRecords.count) { BoardService.ensureColumns(in: context) }
        .sheet(item: $editing) { TaskDetailView(card: $0).presentationDetents([.medium, .large]) }
        .sheet(item: $addingTo) { QuickAddSheet(column: $0) }
        .columnManagement($columnRequest)
    }

    // MARK: Kolom

    private func cards(in column: BoardColumn) -> [TodoCard] {
        cards.filter { BoardService.belongs($0, to: column, in: columns) }.sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder private func section(_ column: BoardColumn) -> some View {
        let columnCards = cards(in: column)
        let isCollapsed = collapsed.contains(column.id)
        Section {
            if !isCollapsed {
                ForEach(columnCards) { card in
                    cardRow(card, in: column)
                }
                if columnCards.isEmpty { emptyRow(column) }
            }
        } header: {
            header(column, count: columnCards.count, isCollapsed: isCollapsed)
        }
    }

    private func cardRow(_ card: TodoCard, in column: BoardColumn) -> some View {
        CardView(card: card, isTimerRunning: runningTodoIDs.contains(card.id),
                 onStartTimer: {
                     TimerService.startTimer(for: card, in: context)
                     appState.showToast("Timer gestart: \(card.title)")
                 },
                 onOpen: { editing = card })
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
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

    /// Lege kolom: een smalle plek om een kaart neer te zetten.
    private func emptyRow(_ column: BoardColumn) -> some View {
        RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
            .strokeBorder(ThingsColor.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 36)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 12))
            .dropDestination(for: CardReference.self) { items, _ in
                drop(items, into: column, before: nil)
            }
            .accessibilityHidden(true)
    }

    /// Kop van een kolom: loslaten van een kaart zet hem bovenaan, van een kolom ervoor of erna (boven- of onderhelft).
    private func header(_ column: BoardColumn, count: Int, isCollapsed: Bool) -> some View {
        let isTargeted = targetedColumn == column.id
        return VStack(spacing: 0) {
            columnHeader(column, count: count, isCollapsed: isCollapsed)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                        .fill(isTargeted ? column.color.opacity(0.14) : Color.clear)
                )
                .animation(.easeOut(duration: 0.15), value: isTargeted)
                .dropDestination(for: CardReference.self) { items, _ in
                    drop(items, into: column, before: cards(in: column).first)
                } isTargeted: { targeted in
                    if targeted { targetedColumn = column.id }
                    else if targetedColumn == column.id { targetedColumn = nil }
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .strokeBorder(ThingsColor.accent, lineWidth: 2)
                .opacity(columnDropTarget == column.id ? 1 : 0)
                .allowsHitTesting(false)
        )
        // Aan de kop vasthouden pakt de hele kolom op.
        .draggable(ColumnReference(key: column.id))
        .dropDestination(for: ColumnReference.self) { items, location in
            dropColumn(items, on: column, after: location.y > ThingsMetrics.minTapTarget / 2)
        } isTargeted: { targeted in
            if targeted { columnDropTarget = column.id }
            else if columnDropTarget == column.id { columnDropTarget = nil }
        }
        .padding(.horizontal, 4)
        .background(ThingsColor.backgroundContent)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.title)
    }

    private func columnHeader(_ column: BoardColumn, count: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 6) {
            // Op het icoon tikken opent de keuze van icoon en kleur.
            Button {
                columnRequest = .icon(column.id)
            } label: {
                ColumnIcon(symbol: column.symbol, color: column.color)
                    .frame(width: 30, height: ThingsMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Icoon en kleur van \(column.title) kiezen")
            // Op de naam tikken klapt de kolom in of uit.
            Button {
                toggleCollapsed(column)
            } label: {
                HStack(spacing: 6) {
                    Text(column.title)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    Text("\(count)")
                        .foregroundStyle(ThingsColor.textSecondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.werk(size: 11, weight: .semibold))
                        .foregroundStyle(ThingsColor.textTertiary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Spacer(minLength: 0)
                }
                .frame(height: ThingsMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(column.title), \(count) kaarten, \(isCollapsed ? "ingeklapt" : "uitgeklapt")")
            Button {
                addingTo = column
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 36, height: ThingsMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nieuwe kaart in \(column.title)")
            Menu {
                Button { columnRequest = .rename(column.id) } label: { Label("Naam wijzigen…", systemImage: "pencil") }
                Button { columnRequest = .icon(column.id) } label: { Label("Icoon en kleur…", systemImage: "face.smiling") }
                Button { shiftColumn(column, by: -1) } label: { Label("Omhoog", systemImage: "arrow.up") }
                    .disabled(columns.first == column)
                Button { shiftColumn(column, by: 1) } label: { Label("Omlaag", systemImage: "arrow.down") }
                    .disabled(columns.last == column)
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
        .padding(.leading, 6)
        .frame(height: ThingsMetrics.minTapTarget)
    }

    private func toggleCollapsed(_ column: BoardColumn) {
        var ids = collapsed
        if ids.contains(column.id) { ids.remove(column.id) } else { ids.insert(column.id) }
        withAnimation(ThingsMotion.reorder) { collapsedRaw = ids.sorted().joined(separator: ",") }
    }

    private var addColumnTile: some View {
        Button {
            columnRequest = .add
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.werk(size: 15, weight: .semibold))
                Text("Nieuwe kolom")
                    .thingsFont(.metadata)
            }
            .foregroundStyle(ThingsColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
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

    private func shiftColumn(_ column: BoardColumn, by offset: Int) {
        guard let index = columns.firstIndex(of: column) else { return }
        withAnimation(ThingsMotion.reorder) {
            BoardService.moveColumn(key: column.id, toIndex: index + offset, in: context)
        }
    }

    private func dropColumn(_ items: [ColumnReference], on target: BoardColumn, after: Bool) -> Bool {
        guard let reference = items.first else { return false }
        if reference.key == target.id { return true }
        let others = columns.filter { $0.id != reference.key }
        guard let position = others.firstIndex(of: target) else { return false }
        withAnimation(ThingsMotion.reorder) {
            BoardService.moveColumn(key: reference.key, toIndex: after ? position + 1 : position, in: context)
        }
        return true
    }

    // MARK: Contextmenu

    @ViewBuilder private func menu(for card: TodoCard) -> some View {
        Button { editing = card } label: { Label("Openen…", systemImage: "square.and.pencil") }
        Button {
            BoardService.complete(card, in: context)
            appState.showToast("\"\(card.title)\" afgerond; te vinden in het archief")
        } label: { Label("Afronden", systemImage: "checkmark.circle") }
        // Naast slepen: de weg zonder slepen (VoiceOver, Schakelbediening).
        Menu {
            ForEach(columns.filter { $0 != card.column }) { target in
                Button {
                    BoardService.move(card, to: target, index: 0, in: context)
                } label: {
                    // Een emoji kan niet als menu-icoon: dan staat hij voor de naam.
                    if IconName.isEmoji(target.symbol) {
                        Label("\(target.symbol) \(target.title)", systemImage: "arrow.right")
                    } else {
                        Label(target.title, systemImage: target.symbol)
                    }
                }
            }
        } label: { Label("Verplaats naar", systemImage: "arrow.right.circle") }
    }
}
