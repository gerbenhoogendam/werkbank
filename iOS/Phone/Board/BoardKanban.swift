import SwiftData
import SwiftUI
import WerkbankCore

/// Het board als kolommen naast elkaar (horizontaal scrollen): per kolom een putje met compacte kaarten, de kop met
/// het aantal en de tijd. Lang indrukken opent het menu van de kaart (ook verplaatsen naar een andere kolom).
struct BoardKanban<MenuContent: View>: View {
    let columns: [BoardColumn]
    let grouped: [String: [TodoCard]]
    /// Geschreven en lopende minuten per kaart.
    let minutes: [UUID: Int]
    let running: Set<UUID>
    let onOpen: (TodoCard) -> Void
    /// "+" in de kop van een kolom: nieuwe taak in die kolom.
    let onAdd: (BoardColumn) -> Void
    @ViewBuilder let menu: (TodoCard) -> MenuContent

    static var columnWidth: CGFloat { 240 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(columns) { column in
                    columnView(column, cards: grouped[column.id] ?? [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private func columnView(_ column: BoardColumn, cards: [TodoCard]) -> some View {
        VStack(spacing: 6) {
            header(column, cards: cards)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if cards.isEmpty {
                        PhCaps(text: "Leeg", size: 10.5, color: Ph.ink3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    ForEach(cards) { card in
                        BoardKanbanCard(card: card, minutes: minutes[card.id] ?? 0,
                                        isRunning: running.contains(card.id))
                            .onTapGesture { onOpen(card) }
                            .contextMenu { menu(card) }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .phWell()
    }

    private func header(_ column: BoardColumn, cards: [TodoCard]) -> some View {
        let total = cards.reduce(0) { $0 + (minutes[$1.id] ?? 0) }
        return HStack(spacing: 8) {
            Text(column.title.uppercased())
                .font(Ph.text(11.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(Ph.ink)
                .lineLimit(1)
            Text("\(cards.count)")
                .font(Ph.poster(16))
                .foregroundStyle(Ph.paper)
                .padding(.horizontal, 5)
                .frame(minWidth: 22, minHeight: 20)
                .background(Ph.ink)
            Spacer(minLength: 4)
            if total > 0 {
                Text(Billing.formatHM(TimeInterval(total * 60)))
                    .font(Ph.text(10.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink2)
            }
            Button {
                onAdd(column)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ph.ink)
                    .frame(width: 28, height: 28)
                    .background(Rectangle().fill(Ph.card).shadow(color: Ph.ink.opacity(0.1), radius: 1, y: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Taak toevoegen aan \(column.title)")
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }
}

// MARK: - Compacte kaart

/// Een kaart in een kolom: titel (twee regels), klant, minuten en een envelop als hij uit een mail komt.
struct BoardKanbanCard: View {
    let card: TodoCard
    let minutes: Int
    let isRunning: Bool

    private var fromMail: Bool { card.mailThreadID != nil || card.senderLine != nil }

    private var edge: Color {
        if isRunning { return Ph.late }
        if card.isNew { return Ph.olive }
        return Ph.line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                if isRunning {
                    Rectangle()
                        .fill(Ph.late)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                        .accessibilityLabel("Tijd loopt")
                }
                Text(card.title.isEmpty ? "Nieuwe taak" : card.title)
                    .font(Ph.text(13.5, .medium))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                if let label = card.clientLabel, !label.isEmpty {
                    PhBoxTag(text: label)
                        .lineLimit(1)
                }
                if minutes > 0 {
                    Text("\(minutes) MIN")
                        .font(Ph.text(10.5))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                if fromMail {
                    Image(systemName: "envelope")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityLabel("Uit mail")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ph.ink2)
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
        .contentShape(Rectangle())
    }
}
