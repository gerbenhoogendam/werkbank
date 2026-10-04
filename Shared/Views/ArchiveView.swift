import SwiftData
import SwiftUI

/// Het archief: afgeronde taken, nieuwste bovenaan. Terugzetten brengt een taak terug op het board.
struct ArchiveView: View {
    @Query private var completed: [TodoCard]

    init() {
        let done = BoardColumn.doneID
        _completed = Query(filter: #Predicate<TodoCard> { $0.columnRaw == done })
    }

    private var sorted: [TodoCard] {
        completed.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(ThingsColor.logbook)
                Text("Archief")
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("\(completed.count)")
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            if completed.isEmpty {
                Text("Nog geen afgeronde taken. Vink een taak op het board af om hem hier terug te vinden.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sorted) { card in
                            ArchiveRow(card: card)
                            Rectangle().fill(ThingsColor.separator).frame(height: 1)
                        }
                    }
                }
            }
        }
        .background(ThingsColor.backgroundContent)
    }
}

private struct ArchiveRow: View {
    let card: TodoCard

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ThingsColor.logbook)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title.isEmpty ? "Taak zonder titel" : card.title)
                    .thingsFont(.todoTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let label = card.clientLabel { TagPill(name: label) }
                    Text(dateText)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                }
            }
            Spacer(minLength: 4)
            Button {
                BoardService.reopen(card, in: context)
                appState.showToast("\"\(card.title)\" teruggezet op het board")
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Terugzetten op het board")
            .accessibilityLabel("Zet \(card.title) terug op het board")

            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(ThingsColor.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Definitief verwijderen")
            .accessibilityLabel("Verwijder \(card.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .confirmationDialog("Taak definitief verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) { BoardService.delete(card, in: context) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("\"\(card.title)\" en de subtaken verdwijnen. Bestede tijd in Tijd schrijven blijft staan.")
        }
    }

    private var dateText: String {
        guard let date = card.completedAt else { return "Afgerond" }
        return "Afgerond " + date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
