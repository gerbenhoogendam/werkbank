import SwiftData
import SwiftUI
import WerkbankCore

/// Tijd op de iPhone: wat er loopt (groot, live), daaronder vandaag of de week (per dag en per klant).
struct TijdHome: View {
    private enum Scope: Hashable { case vandaag, week }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Regels van deze en vorige week (op `createdAt`; ingedeeld op het begin, zie `TijdDates.date(of:)`).
    @Query private var entries: [TimeEntry]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" || $0.statusRaw == "paused" })
    private var active: [TimeEntry]

    @State private var scope: Scope = .vandaag
    @State private var editing: TimeEntry?
    /// De timer over het hele scherm.
    @State private var focused: TimeEntry?
    /// Stop gekozen op het volle scherm: na het sluiten de stopsheet openen (twee bladen tegelijk kan niet).
    @State private var stopAfterFocus: TimeEntry?
    /// "+ TIJD": kiezen tussen inspreken en typen.
    @State private var adding = false
    /// Inspreken gekozen: na het sluiten van het keuzeblad de tijdinvoer openen.
    @State private var voiceAfterAdd = false

    init() {
        let since = TijdDates.monday(of: .now).addingTimeInterval(-7 * 86_400)
        _entries = Query(filter: #Predicate<TimeEntry> { $0.createdAt >= since }, sort: \TimeEntry.createdAt)
    }

    /// Lopende timers eerst (laatst gestart bovenaan), daarna gepauzeerde.
    private var activeSorted: [TimeEntry] {
        let running = active.filter { $0.status == .running }
            .sorted { ($0.lastStart ?? .distantPast) > ($1.lastStart ?? .distantPast) }
        let paused = active.filter { $0.status == .paused }
            .sorted { ($0.pausedAt ?? .distantPast) > ($1.pausedAt ?? .distantPast) }
        return running + paused
    }

    var body: some View {
        let activeEntries = activeSorted
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                PhHeader(eyebrow: "VANDAAG \(Billing.formatHM(todayTotal(at: timeline.date)))", title: "Tijd")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if activeEntries.isEmpty {
                        idleCard
                    } else {
                        ForEach(Array(activeEntries.enumerated()), id: \.element.id) { index, entry in
                            TijdTimerCard(entry: entry, large: index == 0) { focused = entry }
                        }
                    }
                    PhSegmented(items: [PhSegmented<Scope>.Item(value: .vandaag, title: "Vandaag"),
                                        PhSegmented<Scope>.Item(value: .week, title: "Week")],
                                selection: $scope)
                    switch scope {
                    case .vandaag: todayList
                    case .week: TijdWeekView(entries: weekEntries)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("+ TIJD") { adding = true }
                .buttonStyle(PhPrimaryStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Ph.paper)
        }
        .phScreen()
        .sheet(item: $editing) { entry in
            TijdEntryEditor(entry: entry) {
                editing = nil
                TimerService.discard(entry, in: context)
                appState.showToast("Tijdregel verwijderd")
            }
        }
        .sheet(isPresented: $adding, onDismiss: {
            guard voiceAfterAdd else { return }
            voiceAfterAdd = false
            appState.timeEntry = .voice
        }) {
            TijdAddSheet {
                voiceAfterAdd = true
                adding = false
            }
        }
        .fullScreenCover(item: $focused, onDismiss: {
            guard let entry = stopAfterFocus else { return }
            stopAfterFocus = nil
            if entry.status != .finished { appState.requestStop(entry, in: context) }
        }) { entry in
            TijdFocusView(entry: entry, todayTotal: { todayTotal(at: $0) }) {
                stopAfterFocus = entry
                focused = nil
            }
        }
    }

    // MARK: Niets loopt

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhCaps(text: "Geen timer", size: 10, color: Ph.ink3)
            Text("0:00:00")
                .font(Ph.poster(56))
                .foregroundStyle(Ph.ink3)
                .padding(.bottom, -6)
            Button("START") { appState.timeEntry = .choose }
                .buttonStyle(PhPrimaryStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .phRaisedCard()
    }

    // MARK: Vandaag

    private var todayEntries: [TimeEntry] {
        entries.filter { $0.status == .finished && TijdDates.calendar.isDateInToday(TijdDates.date(of: $0)) }
            .sorted { TijdDates.date(of: $0) < TijdDates.date(of: $1) }
    }

    private func todayTotal(at now: Date) -> TimeInterval {
        var total = todayEntries.reduce(0.0) { $0 + $1.accumulated }
        for entry in active where TijdDates.calendar.isDate(TijdDates.date(of: entry), inSameDayAs: now) {
            total += entry.elapsed(at: now)
        }
        return total
    }

    @ViewBuilder private var todayList: some View {
        let list = todayEntries
        VStack(spacing: 0) {
            if list.isEmpty {
                PhCaps(text: "Nog niets vandaag", size: 11, color: Ph.ink3)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(list) { entry in
                    Button {
                        editing = entry
                    } label: {
                        TijdEntryRow(entry: entry, isLast: entry.id == list.last?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .phCard()
    }

    // MARK: Week

    private var weekEntries: [TimeEntry] {
        let monday = TijdDates.monday(of: .now)
        let next = monday.addingTimeInterval(7 * 86_400 + 3_600)
        return entries.filter {
            let date = TijdDates.date(of: $0)
            return date >= monday && date < TijdDates.calendar.startOfDay(for: next)
        }
    }
}

// MARK: - Datums

enum TijdDates {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "nl_NL")
        cal.timeZone = .current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// De dag van een regel: het eerste begin, anders het aanmaakmoment (zoals de week in Tijd schrijven).
    static func date(of entry: TimeEntry) -> Date { entry.firstStart ?? entry.createdAt }

    /// "09:30–10:15"
    static func range(of entry: TimeEntry) -> String {
        let start = entry.firstStart ?? entry.createdAt
        let end = entry.finishedAt ?? start.addingTimeInterval(entry.accumulated)
        return DutchDate.range(start, end)
    }
}

// MARK: - Lopende timer

/// Een lopende of gepauzeerde timer: de tijd groot en live, klant en omschrijving, pauze/hervat en stop.
struct TijdTimerCard: View {
    let entry: TimeEntry
    var large = true
    /// Tik op de kaart (niet op een knop): de timer over het hele scherm.
    var onOpen: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        let running = entry.status == .running
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if running {
                    Rectangle().fill(Ph.late).frame(width: 7, height: 7)
                }
                PhCaps(text: running ? "Loopt" : "Pauze", size: 10, color: running ? Ph.ink : Ph.ink3)
                Spacer(minLength: 8)
                if let start = entry.firstStart {
                    PhCaps(text: "Sinds \(DutchDate.time(start))", size: 10, color: Ph.ink2)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(Billing.formatHMS(entry.elapsed(at: timeline.date)))
                    .font(Ph.poster(large ? 56 : 36))
                    .monospacedDigit()
                    .foregroundStyle(running ? Ph.ink : Ph.ink2)
                    .padding(.bottom, large ? -6 : -3)
            }
            VStack(alignment: .leading, spacing: 3) {
                PhCaps(text: entry.client, size: 10.5, color: Ph.olive)
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(Ph.text(15, .semibold))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(2)
                }
                if !entry.workDescription.isEmpty {
                    Text(entry.workDescription)
                        .font(Ph.text(13))
                        .foregroundStyle(Ph.ink2)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                Button(running ? "PAUZE" : "HERVAT") {
                    if running {
                        TimerService.pause(entry, in: context)
                    } else {
                        TimerService.start(entry, in: context)
                    }
                }
                .buttonStyle(PhSecondaryStyle())
                Button("STOP") { appState.requestStop(entry, in: context) }
                    .buttonStyle(PhInkStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .phRaisedCard()
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityAction(named: Text("Volledig scherm")) { onOpen?() }
    }
}

// MARK: - Regel

/// Eén afgeronde regel: tijd, klant, omschrijving en de duur groot.
struct TijdEntryRow: View {
    let entry: TimeEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(TijdDates.range(of: entry))
                        .font(Ph.text(11))
                        .monospacedDigit()
                        .foregroundStyle(Ph.ink2)
                    PhCaps(text: entry.client, size: 10, color: Ph.olive)
                }
                Text(entry.title.isEmpty ? entry.workDescription : entry.title)
                    .font(Ph.text(14, .semibold))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1)
                if !entry.title.isEmpty && !entry.workDescription.isEmpty {
                    Text(entry.workDescription)
                        .font(Ph.text(12))
                        .foregroundStyle(Ph.ink2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Billing.formatHM(entry.accumulated))
                    .font(Ph.poster(28))
                    .foregroundStyle(entry.isWritten ? Ph.ink3 : Ph.ink)
                if entry.isWritten {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ph.olive)
                        .accessibilityLabel("Geschreven")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Ph.hair).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Week

/// De week: een staaf per werkdag (vandaag limoen) en de totalen per klant.
struct TijdWeekView: View {
    let entries: [TimeEntry]

    private struct Day: Identifiable {
        let date: Date
        let seconds: TimeInterval
        var id: Date { date }
    }

    private func seconds(_ entry: TimeEntry, now: Date) -> TimeInterval {
        entry.status == .finished ? entry.accumulated : entry.elapsed(at: now)
    }

    var body: some View {
        let now = Date()
        let monday = TijdDates.monday(of: now)
        let allDays: [Day] = (0..<7).map { offset in
            let date = TijdDates.calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let total = entries.filter { TijdDates.calendar.isDate(TijdDates.date(of: $0), inSameDayAs: date) }
                .reduce(0.0) { $0 + seconds($1, now: now) }
            return Day(date: date, seconds: total)
        }
        // Weekend alleen als er tijd op staat.
        let days = allDays.enumerated().filter { $0.offset < 5 || $0.element.seconds > 0 }.map(\.element)
        let total = allDays.reduce(0.0) { $0 + $1.seconds }
        var perClient: [String: TimeInterval] = [:]
        for entry in entries { perClient[entry.client, default: 0] += seconds(entry, now: now) }
        let clients = perClient.filter { $0.value > 0 }.sorted { $0.value > $1.value }

        return VStack(alignment: .leading, spacing: 14) {
            bars(days, total: total)
            clientTotals(clients)
        }
    }

    private func bars(_ days: [Day], total: TimeInterval) -> some View {
        let maxValue = max(days.map(\.seconds).max() ?? 0, 3_600)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                PhCaps(text: "Week \(DutchDate.isoWeek(.now))", size: 11, color: Ph.olive)
                Spacer()
                Text(Billing.formatHM(total))
                    .font(Ph.poster(34))
                    .foregroundStyle(Ph.ink)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    let today = TijdDates.calendar.isDateInToday(day.date)
                    VStack(spacing: 4) {
                        Text(day.seconds > 0 ? Billing.formatHM(day.seconds) : "")
                            .font(Ph.text(10, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Ph.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Rectangle()
                            .fill(today ? Ph.lime : Ph.ink)
                            .frame(height: max(2, 120 * CGFloat(day.seconds / maxValue)))
                            .overlay {
                                if today { Rectangle().strokeBorder(Ph.ink, lineWidth: 1) }
                            }
                        Text(DutchDate.weekdayShort(day.date).uppercased())
                            .font(Ph.text(9.5, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(today ? Ph.ink : Ph.ink2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 160, alignment: .bottom)
        }
        .padding(14)
        .phCard()
    }

    private func clientTotals(_ clients: [(key: String, value: TimeInterval)]) -> some View {
        let maxValue = max(clients.first?.value ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            PhCaps(text: "Per klant", size: 11, color: Ph.olive)
            VStack(spacing: 0) {
                if clients.isEmpty {
                    PhCaps(text: "Nog niets deze week", size: 11, color: Ph.ink3)
                        .frame(maxWidth: .infinity, minHeight: 52)
                } else {
                    ForEach(Array(clients.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            PhCaps(text: item.key, size: 10.5, color: Ph.ink)
                                .frame(width: 104, alignment: .leading)
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Ph.ink)
                                    .frame(width: max(2, geo.size.width * CGFloat(item.value / maxValue)), height: 10)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 14)
                            Text(Billing.formatHM(item.value))
                                .font(Ph.poster(22))
                                .foregroundStyle(Ph.ink)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if index < clients.count - 1 { Rectangle().fill(Ph.hair).frame(height: 1) }
                        }
                    }
                }
            }
            .phCard()
        }
    }
}
