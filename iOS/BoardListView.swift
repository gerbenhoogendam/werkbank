import SwiftData
import SwiftUI

/// Board op iPhone: kies een kolom, werk met de kaarten als lijst. Verplaatsen tussen kolommen via het
/// contextmenu; herschikken via "Wijzig". Inplannen via een blad (slepen naar de agenda past niet op een telefoon).
struct BoardListView: View {
    @Binding var column: BoardColumn

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TodoCard.sortOrder) private var cards: [TodoCard]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @State private var editing: TodoCard?
    @State private var scheduling: TodoCard?

    private var columnCards: [TodoCard] { cards.filter { $0.column == column } }
    private var runningTodoID: UUID? { running.first?.todoID }

    var body: some View {
        VStack(spacing: 0) {
            ThingsListHeader(title: column.title, symbol: column.symbol, color: column.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ThingsMetrics.contentPadding)
                .padding(.top, 4)

            columnPicker

            List {
                ForEach(columnCards) { card in
                    CardView(card: card, isTimerRunning: runningTodoID == card.id) {
                        TimerService.startTimer(for: card, in: context)
                        appState.showToast("Timer gestart: \(card.title)")
                    }
                    .onTapGesture { editing = card }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ThingsColor.backgroundSidebar)
            .overlay {
                if columnCards.isEmpty { ThingsEmptyStateSymbol(symbol: column.symbol) }
            }
        }
        .background(ThingsColor.backgroundContent)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { CardEditSheet(card: $0).presentationDetents([.medium]) }
        .sheet(item: $scheduling) { ScheduleSheet(card: $0) }
    }

    private var columnPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BoardColumn.allCases) { item in
                    let count = cards.filter { $0.column == item }.count
                    Button {
                        withAnimation(ThingsMotion.reorder) { column = item }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol).foregroundStyle(item.color)
                            Text(item.title)
                            Text("\(count)").foregroundStyle(ThingsColor.textSecondary).monospacedDigit()
                        }
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                                .fill(item == column ? ThingsColor.selection : ThingsColor.tagBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item == column ? .isSelected : [])
                }
            }
            .padding(.horizontal, ThingsMetrics.contentPadding)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func menu(for card: TodoCard) -> some View {
        Button { editing = card } label: { Label("Bewerken…", systemImage: "pencil") }
        Button { scheduling = card } label: { Label("Inplannen…", systemImage: "calendar.badge.plus") }
        Menu {
            ForEach(BoardColumn.allCases.filter { $0 != card.column }) { target in
                Button {
                    BoardService.move(card, to: target, index: 0, in: context)
                } label: { Label(target.title, systemImage: target.symbol) }
            }
        } label: { Label("Verplaats naar", systemImage: "arrow.right.circle") }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let card = columnCards[from]
        let index = destination > from ? destination - 1 : destination
        BoardService.move(card, to: column, index: index, in: context)
    }
}
