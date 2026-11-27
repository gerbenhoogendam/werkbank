import SwiftData
import SwiftUI
import WerkbankCore

/// Gedaan: de taken die vandaag zijn afgerond (doorgestreept), met de tijd per taak en het totaal; terugzetten zet een
/// taak weer op het board. Daaronder de eerdere dagen van deze week.
struct BoardDoneView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var done: [TodoCard]
    /// Tijd die op kaarten is geschreven.
    @Query(filter: #Predicate<TimeEntry> { $0.todoID != nil }) private var cardEntries: [TimeEntry]

    init() {
        let key = BoardColumn.doneID
        _done = Query(filter: #Predicate<TodoCard> { $0.columnRaw == key })
    }

    private struct EarlierDay: Identifiable {
        let date: Date
        let count: Int
        let seconds: TimeInterval
        var id: Date { date }
    }

    private var calendar: Calendar { TijdDates.calendar }

    /// Seconden per kaart (afgerond en lopend).
    private func secondsByCard() -> [UUID: TimeInterval] {
        var seconds: [UUID: TimeInterval] = [:]
        let now = Date()
        for entry in cardEntries {
            guard let id = entry.todoID else { continue }
            seconds[id, default: 0] += entry.status == .finished ? entry.accumulated : entry.elapsed(at: now)
        }
        return seconds
    }

    private var today: [TodoCard] {
        done.filter { card in
            guard let date = card.completedAt else { return false }
            return calendar.isDateInToday(date)
        }
        .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Maandag tot gisteren, nieuwste eerst; alleen dagen waarop iets is afgerond.
    private func earlier(seconds: [UUID: TimeInterval]) -> [EarlierDay] {
        let todayStart = calendar.startOfDay(for: .now)
        let monday = TijdDates.monday(of: .now)
        var result: [EarlierDay] = []
        var day = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        while day >= monday {
            let cards = done.filter { card in
                guard let date = card.completedAt else { return false }
                return calendar.isDate(date, inSameDayAs: day)
            }
            if !cards.isEmpty {
                let total = cards.reduce(0.0) { $0 + (seconds[$1.id] ?? 0) }
                result.append(EarlierDay(date: day, count: cards.count, seconds: total))
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return result
    }

    var body: some View {
        let seconds = secondsByCard()
        let list = today
        let total = list.reduce(0.0) { $0 + (seconds[$1.id] ?? 0) }
        let earlierDays = earlier(seconds: seconds)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("BOARD", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(PhSecondaryStyle(height: 40))
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    PhEyebrow(text: "\(DutchDate.weekdayAndDay(.now)) · \(list.count) \(list.count == 1 ? "taak" : "taken")")
                    Text("GEDAAN")
                        .font(Ph.poster(52))
                        .foregroundStyle(Ph.ink)
                        .padding(.bottom, -6)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    PhCaps(text: "Tijd", size: 10.5)
                    Text(Billing.formatHM(total))
                        .font(Ph.poster(52))
                        .foregroundStyle(Ph.ink)
                        .padding(.bottom, -6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todayCard(list, seconds: seconds, total: total)
                    if !earlierDays.isEmpty { earlierCard(earlierDays) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .phScreen()
        .presentationDetents([.large])
        .presentationBackground(Ph.paper)
    }

    // MARK: Vandaag

    private func todayCard(_ list: [TodoCard], seconds: [UUID: TimeInterval], total: TimeInterval) -> some View {
        VStack(spacing: 0) {
            if list.isEmpty {
                PhCaps(text: "Nog niets afgerond vandaag", size: 11, color: Ph.ink3)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(list) { card in
                    row(card, seconds: seconds[card.id] ?? 0)
                }
                HStack {
                    Text("TOTAAL · \(list.count) \(list.count == 1 ? "TAAK" : "TAKEN")")
                        .font(Ph.text(11, .semibold))
                        .tracking(1.8)
                        .foregroundStyle(Ph.paper)
                    Spacer(minLength: 8)
                    Text(Billing.formatHM(total))
                        .font(Ph.poster(30))
                        .foregroundStyle(Ph.lime)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(Ph.ink)
            }
        }
        .phCard()
    }

    private func row(_ card: TodoCard, seconds: TimeInterval) -> some View {
        let fromMail = card.mailThreadID != nil || card.senderLine != nil
        return HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(Ph.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ph.lime)
            }
            .frame(width: 22, height: 22)
            .accessibilityLabel("Klaar")
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title.isEmpty ? "Taak" : card.title)
                    .font(Ph.text(14))
                    .foregroundStyle(Ph.ink3)
                    .strikethrough(true, color: Ph.ink)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    if let label = card.clientLabel, !label.isEmpty {
                        PhBoxTag(text: label)
                            .lineLimit(1)
                    }
                    if let date = card.completedAt {
                        Text("KLAAR \(DutchDate.time(date))")
                            .font(Ph.text(10.5))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    if fromMail {
                        Image(systemName: "envelope")
                            .font(.system(size: 10, weight: .medium))
                            .accessibilityLabel("Uit mail")
                    }
                }
                .foregroundStyle(Ph.ink2)
            }
            Spacer(minLength: 6)
            Text(Billing.formatHM(seconds))
                .font(Ph.poster(24))
                .foregroundStyle(seconds > 0 ? Ph.ink : Ph.ink3)
            Button {
                withAnimation { BoardService.reopen(card, in: context) }
                appState.showToast("Terug op het board")
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ph.ink)
                    .frame(width: 38, height: 38)
                    .phWell()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Herstel \(card.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
    }

    // MARK: Eerder deze week

    private func earlierCard(_ days: [EarlierDay]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: "Eerder deze week", size: 11)
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 12) {
                        Text(DutchDate.weekdayShort(day.date).uppercased())
                            .font(Ph.text(10, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Ph.ink2)
                            .frame(width: 24, alignment: .leading)
                        Text("\(day.count) \(day.count == 1 ? "taak" : "taken")")
                            .font(Ph.text(13))
                            .foregroundStyle(Ph.ink)
                        Spacer(minLength: 8)
                        Text(Billing.formatHM(day.seconds))
                            .font(Ph.poster(20))
                            .foregroundStyle(Ph.ink)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .overlay(alignment: .bottom) {
                        if index < days.count - 1 { Rectangle().fill(Ph.hair).frame(height: 1) }
                    }
                }
            }
            .phCard()
        }
    }
}
