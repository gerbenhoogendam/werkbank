import AppKit
import SwiftData
import SwiftUI
import WerkbankCore

/// De bladen van de mailmodus: taak (T), tijd schrijven (S), inplannen (P), opvolgen (F) en het Claude-concept (C).
/// Elk blad eindigt in archiveren en opent de volgende mail.
enum MailModeSheet: Equatable {
    case task, time, plan, follow, concept
    /// Nieuwsbrieven en meldingen in één keer archiveren.
    case bulk
    /// Uitgebreid zoeken (⌘F).
    case search

    var needsMail: Bool { self != .bulk && self != .search }
}

struct MailModeSheetHost: View {
    let sheet: MailModeSheet
    let item: GmailMailItem?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture { MailModeStore.shared.closeSheet() }
            Group {
                if sheet == .bulk {
                    MailBulkSheet()
                } else if sheet == .search {
                    MailSearchSheet()
                } else if let item {
                    switch sheet {
                    case .task: MailTaskSheet(item: item)
                    case .time: MailTimeSheet(item: item)
                    case .plan: MailPlanSheet(item: item)
                    case .follow: MailFollowSheet(item: item)
                    case .concept, .bulk, .search: MailConceptSheet(item: item)
                    }
                }
            }
            .padding(.top, 60)
        }
    }
}

// MARK: - Onderdelen

/// Het kader van een blad: titel, inhoud en knoppen onderaan.
private struct SheetFrame<Content: View, Buttons: View>: View {
    let title: String
    let systemImage: String
    /// Grijs naast de titel ("Alle mail").
    var detail: String? = nil
    var width: CGFloat = 520
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.werk(size: 15, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                Text(title)
                    .font(.werk(size: 18, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.werk(size: 13))
                        .foregroundStyle(ThingsColor.textSecondary)
                }
            }
            content
            HStack(spacing: 10) {
                buttons
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: max(4, MailModeMetrics.radius + 4), style: .continuous)
            .fill(ThingsColor.backgroundContent)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12))
        .overlay(RoundedRectangle(cornerRadius: max(4, MailModeMetrics.radius + 4), style: .continuous)
            .strokeBorder(ThingsColor.separator))
    }
}

/// De knoppen onder een blad: de handeling als donker vlak, Annuleren als tekst, andere keuzes met een rand.
struct SheetButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(6, MailModeMetrics.radius + 2), style: .continuous)
        return configuration.label
            .font(.werk(size: 13.5, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? ThingsColor.backgroundContent : ThingsColor.textPrimary)
            .padding(.horizontal, kind == .plain ? 10 : 16)
            .frame(height: 34)
            .background(shape.fill(kind == .primary ? ThingsColor.textPrimary
                                   : (kind == .secondary ? ThingsColor.cardBackground : Color.clear)))
            .overlay(shape.strokeBorder(kind == .secondary ? ThingsColor.separator : Color.clear))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(shape)
    }
}

/// Een lijst in een blad: rijen onder elkaar met een lijntje ertussen, in een vlak met een rand.
private struct SheetList<Item, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(6, MailModeMetrics.radius + 2), style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(ThingsColor.separator).frame(height: 1) }
                row(item)
            }
        }
        .background(shape.fill(ThingsColor.backgroundContent))
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThingsColor.separator))
    }
}

/// Een veld met het label erboven, in de kleur van de rol Veldlabel.
private struct SheetField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.werk(size: 12, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
            content
        }
    }
}

private extension View {
    /// Een tekstveld in de vorm van de mailmodus.
    func sheetInput(height: CGFloat? = 32) -> some View {
        textFieldStyle(.plain)
            .font(.werk(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, height == nil ? 8 : 0)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).fill(ThingsColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous).strokeBorder(ThingsColor.separator))
    }
}

private func plainSubject(_ subject: String) -> String {
    var text = subject.trimmingCharacters(in: .whitespaces)
    while let range = text.range(of: #"^(re|antw|fw|fwd|doorst)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
        text.removeSubrange(range)
    }
    return text
}

// MARK: - Taak (T)

private struct MailTaskSheet: View {
    let item: GmailMailItem
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var columns: [BoardColumn] = []
    @State private var title = ""
    @State private var columnKey = BoardColumn.inboxID
    private let store = MailModeStore.shared

    var body: some View {
        SheetFrame(title: "Taak maken", systemImage: "checkmark.circle") {
            SheetField(label: "Titel") {
                TextField("", text: $title).sheetInput()
            }
            SheetField(label: "Kolom") {
                WrapStack(spacing: 6) {
                    ForEach(columns) { column in
                        Button(column.title) { columnKey = column.id }
                            .buttonStyle(MailFilterChipStyle(isOn: columnKey == column.id))
                    }
                }
            }
            if let client = store.clientName(for: item) {
                SheetField(label: "Klant") {
                    HStack(spacing: 6) {
                        ClientLogo(name: client, size: 16)
                        Text(client).font(.werk(size: 13)).foregroundStyle(ThingsColor.textPrimary)
                    }
                }
            }
        } buttons: {
            Spacer(minLength: 0)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button("Alleen taak") { make(archive: false) }
                .buttonStyle(SheetButtonStyle())
            Button("Taak maken en archiveren") { make(archive: true) }
                .buttonStyle(SheetButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            title = plainSubject(item.subject)
            columns = BoardService.columns(in: context)
        }
    }

    private func make(archive: Bool) {
        let column = columns.first { $0.id == columnKey } ?? .inbox
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.closeSheet()
        if archive {
            store.takeOut(threadID: item.threadID)
            FollowUpStore.shared.clearReturned(threadID: item.threadID)
        }
        Task {
            await GmailSession.shared.createTask(from: item.summary, title: name.isEmpty ? item.subject : name, minutes: 0,
                                                 column: column, archive: archive, context: context, appState: appState)
            store.refreshTasks()
        }
    }
}

// MARK: - Tijd schrijven (S)

private struct MailTimeSheet: View {
    let item: GmailMailItem
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var client = ""
    @State private var caseTitle = ""
    @State private var performed = ""
    @State private var hours = 0.25
    @State private var error: String?
    private let store = MailModeStore.shared
    private static let choices: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2]

    var body: some View {
        SheetFrame(title: "Tijd schrijven", systemImage: "clock") {
            SheetField(label: "Klant") {
                ClientField(text: $client)
            }
            SheetField(label: "Case") {
                TextField("", text: $caseTitle).sheetInput()
            }
            SheetField(label: "Uitgevoerd") {
                TextEditor(text: $performed)
                    .font(.werk(size: 13))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .frame(height: 70)
                    .sheetInput(height: nil)
            }
            SheetField(label: "Te factureren") {
                HStack(spacing: 6) {
                    ForEach(Self.choices, id: \.self) { value in
                        Button(Billing.formatHours(value)) { hours = value }
                            .buttonStyle(MailFilterChipStyle(isOn: hours == value))
                    }
                }
            }
            if let error {
                Text(error).font(.werk(size: 12)).foregroundStyle(ThingsColor.deadline)
            }
        } buttons: {
            Spacer(minLength: 0)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button("Schrijven en archiveren", action: write)
                .buttonStyle(SheetButtonStyle(kind: .primary))
        }
        .onAppear {
            client = store.clientName(for: item) ?? ""
            caseTitle = plainSubject(item.subject)
        }
    }

    private func write() {
        let name = client.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Vul een klant in."; return }
        guard TimerService.validDescription(performed) else { error = "Vul in wat er is uitgevoerd."; return }
        TimerService.logSupport(client: name, caseTitle: caseTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                performed: performed.trimmingCharacters(in: .whitespacesAndNewlines),
                                minutes: Int((hours * 60).rounded()), in: context)
        store.closeSheet()
        store.archive(item, announcing: "\(Billing.formatHours(hours)) u geschreven op \(name) · gearchiveerd", appState: appState)
    }
}

// MARK: - Inplannen (P)

private struct MailPlanSheet: View {
    let item: GmailMailItem
    @Environment(AppState.self) private var appState
    @State private var options: [PlanOption] = []
    @State private var chosen = 0
    @State private var start = Date()
    @State private var minutes = 60
    @State private var title = ""
    @State private var calendarID: String?
    @State private var invite = true
    @State private var error: String?
    private let store = MailModeStore.shared
    private let calendar = CalendarService.shared

    struct PlanOption: Equatable {
        let start: Date
        let end: Date
        let fromMail: Bool
    }

    var body: some View {
        SheetFrame(title: "Inplannen", systemImage: "calendar", width: 860) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    SheetField(label: "Titel") {
                        TextField("", text: $title).sheetInput()
                    }
                    SheetField(label: "Moment") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                                Button { pick(index) } label: {
                                    HStack {
                                        Text(Self.label(option.start, option.end))
                                        Spacer(minLength: 6)
                                        Text(option.fromMail ? "Uit de mail" : "Vrij")
                                            .font(.werk(size: 10.5, weight: .semibold))
                                            .foregroundStyle(chosen == index ? Color.white.opacity(0.85)
                                                             : (option.fromMail ? ThingsColor.accent : ThingsColor.textSecondary))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(MailFilterChipStyle(isOn: chosen == index))
                            }
                            HStack(spacing: 8) {
                                DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .onChange(of: start) { _, new in
                                        if !options.indices.contains(chosen) || options[chosen].start != new { chosen = -1 }
                                    }
                                Picker("", selection: $minutes) {
                                    if ![30, 60, 90, 120].contains(minutes) {
                                        Text("\(minutes) min").tag(minutes)
                                    }
                                    Text("30 min").tag(30)
                                    Text("1 uur").tag(60)
                                    Text("1,5 uur").tag(90)
                                    Text("2 uur").tag(120)
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                            if let conflict {
                                Text("Overlapt met \(conflict.title) (\(DutchDate.time(conflict.start))–\(DutchDate.time(conflict.end)))")
                                    .font(.werk(size: 12))
                                    .foregroundStyle(ThingsColor.deadline)
                            }
                        }
                    }
                    if !calendar.writableCalendars.isEmpty {
                        SheetField(label: "Agenda") {
                            WrapStack(spacing: 6) {
                                ForEach(calendar.writableCalendars) { entry in
                                    Button { calendarID = entry.id } label: {
                                        HStack(spacing: 5) {
                                            Circle().fill(entry.color).frame(width: 7, height: 7)
                                            Text(entry.title)
                                        }
                                    }
                                    .buttonStyle(MailFilterChipStyle(isOn: calendarID == entry.id))
                                }
                            }
                        }
                    }
                    if let guest {
                        Toggle("Uitnodiging in een antwoord aan \(guest.name ?? guest.address)", isOn: $invite)
                            .toggleStyle(.checkbox)
                            .font(.werk(size: 12.5))
                    }
                    if let error {
                        Text(error).font(.werk(size: 12)).foregroundStyle(ThingsColor.deadline)
                    }
                }
                .frame(width: 320)
                WeekPreview(start: start, end: end, title: title)
                    .frame(maxWidth: .infinity)
            }
        } buttons: {
            Button("Vrije momenten in antwoord", action: freeInReply)
                .buttonStyle(SheetButtonStyle())
            Spacer(minLength: 8)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button(invite && guest != nil ? "Inplannen en antwoorden" : "Inplannen en archiveren", action: plan)
                .buttonStyle(SheetButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        .task { await load() }
    }

    private var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

    /// Met wie de afspraak is: de afzender, of bij je eigen mail de eerste ontvanger.
    private var guest: MailAddress? {
        let own = GmailSession.shared.ownAddresses
        if let address = item.fromAddress, !own.contains(address.lowercased()) {
            return MailAddress(name: item.fromName, address: address)
        }
        return item.recipients.first { !own.contains($0) }.map { MailAddress(address: $0) }
    }

    private var greeting: String {
        let first = (guest?.name ?? "").split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Hallo" : "Hoi \(first)"
    }

    private var conflict: AgendaEvent? { overlap(start, end) }

    private func overlap(_ from: Date, _ to: Date) -> AgendaEvent? {
        calendar.events(from: from.addingTimeInterval(-86_400), to: to.addingTimeInterval(86_400),
                        hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
            .first { !$0.isAllDay && $0.start < to && $0.end > from }
    }

    /// "dinsdag 3 november van 14:00 tot 15:00", voor in de mail.
    private static func sentence(_ start: Date, _ end: Date) -> String {
        "\(longDay.string(from: start)) van \(DutchDate.time(start)) tot \(DutchDate.time(end))"
    }

    private static let longDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static func label(_ start: Date, _ end: Date) -> String {
        "\(DutchDate.weekdayAndDay(start)) · \(DutchDate.time(start))–\(DutchDate.time(end))"
    }

    private func pick(_ index: Int) {
        guard options.indices.contains(index) else { return }
        let option = options[index]
        start = option.start
        minutes = max(15, Int(option.end.timeIntervalSince(option.start) / 60))
        chosen = index
    }

    private func load() async {
        let client = store.clientName(for: item)
        title = "\(plainSubject(item.subject))" + (client.map { " · \($0)" } ?? "")
        calendarID = calendar.defaultTargetCalendarID(hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
        let proposals = await store.proposals(for: item)
        let earliest = Date().addingTimeInterval(3600)
        let busy = calendar.events(from: .now, to: .now.addingTimeInterval(60 * 86_400), hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
            .map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }
        // Een dag zonder tijd uit de mail: het eerste vrije uur op die dag.
        let fromMail: [PlanOption] = proposals.prefix(2).compactMap { proposal in
            if proposal.hasTime { return PlanOption(start: proposal.start, end: proposal.end, fromMail: true) }
            let dayStart = Calendar.current.startOfDay(for: proposal.start)
            return FreeSlots.find(busy: busy, from: max(dayStart, earliest), days: 1, startHour: AppSettings.startHour,
                                  endHour: AppSettings.endHour, limit: 1)
                .first.map { PlanOption(start: $0.start, end: $0.end, fromMail: true) }
        }
        let free = FreeSlots.find(busy: busy, from: earliest, startHour: AppSettings.startHour,
                                  endHour: AppSettings.endHour, limit: fromMail.isEmpty ? 3 : 2)
        options = fromMail + free.filter { slot in !fromMail.contains { $0.start == slot.start } }
            .map { PlanOption(start: $0.start, end: $0.end, fromMail: false) }
        if options.isEmpty {
            // Het volgende hele uur.
            let hour = Calendar.current.dateInterval(of: .hour, for: .now)?.end ?? .now
            start = hour
            chosen = -1
        } else {
            pick(0)
        }
    }

    private func plan() {
        guard let calendarID else { error = "Kies een agenda."; return }
        do {
            try calendar.createEvent(title: title, start: start, end: end, calendarID: calendarID)
        } catch {
            self.error = "Inplannen mislukt: \(error.localizedDescription)"
            return
        }
        store.closeSheet()
        let when = Self.label(start, end)
        if invite, let guest {
            // De uitnodiging gaat mee in een antwoord dat je eerst ziet; versturen archiveert het gesprek.
            let me = GmailSession.shared.account(for: item.id) ?? ""
            let ics = CalendarInvite.ics(uid: "\(UUID().uuidString.lowercased())@werkbank", start: start, end: end, title: title,
                                         organizer: MailAddress(name: UserDefaults.standard.string(forKey: "mail.senderName"), address: me),
                                         attendees: [guest])
            let attachment = MailAttachment(name: "uitnodiging.ics", mediaType: "text/calendar; method=REQUEST",
                                            data: Data(ics.utf8))
            store.replyTrigger.reply(text: "\(greeting),\n\nDan zien we elkaar \(Self.sentence(start, end)). De uitnodiging zit erbij.\n",
                                     attachments: [attachment])
            appState.announce("Ingepland: \(when)")
        } else {
            store.archive(item, announcing: "Ingepland: \(when) · gearchiveerd", appState: appState)
        }
    }

    private func freeInReply() {
        let free = options.filter { overlap($0.start, $0.end) == nil }
        guard !free.isEmpty else { error = "Geen vrije momenten gevonden."; return }
        let lines = free.map { "- " + Self.sentence($0.start, $0.end) }.joined(separator: "\n")
        store.closeSheet()
        store.replyTrigger.reply(text: "\(greeting),\n\nDeze momenten kan ik:\n\(lines)\n\nZeg maar welke het beste uitkomt.\n")
    }
}

/// De werkweek rond het gekozen moment: afspraken grijs, het nieuwe moment in de accentkleur.
private struct WeekPreview: View {
    let start: Date
    let end: Date
    let title: String
    private let calendar = CalendarService.shared

    var body: some View {
        let cal = Calendar.current
        let first = AppSettings.startHour
        let last = max(first + 1, AppSettings.endHour)
        let hourHeight: CGFloat = 26
        let days = weekDays(cal)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Color.clear.frame(height: 22)
                ForEach(first..<last, id: \.self) { hour in
                    Text("\(hour):00")
                        .font(.werk(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textTertiary)
                        .frame(height: hourHeight, alignment: .top)
                }
            }
            .frame(width: 34)
            ForEach(days, id: \.self) { day in
                let isTarget = cal.isDate(day, inSameDayAs: start)
                VStack(spacing: 0) {
                    Text(DutchDate.weekdayAndDay(day))
                        .font(.werk(size: 10.5, weight: isTarget ? .semibold : .regular))
                        .foregroundStyle(isTarget ? ThingsColor.accent : ThingsColor.textSecondary)
                        .frame(height: 22)
                    ZStack(alignment: .top) {
                        Rectangle().fill(isTarget ? ThingsColor.selection.opacity(0.35) : ThingsColor.cardBackground)
                        ForEach(events(on: day, cal)) { event in
                            block(title: event.title, from: event.start, to: event.end, on: day, first: first, hourHeight: hourHeight,
                                  fill: ThingsColor.tagBackground, ink: ThingsColor.textPrimary, cal: cal)
                        }
                        if isTarget {
                            block(title: title, from: start, to: end, on: day, first: first, hourHeight: hourHeight,
                                  fill: ThingsColor.accent, ink: Color.white, cal: cal)
                        }
                    }
                    .frame(height: CGFloat(last - first) * hourHeight)
                    .clipped()
                }
                .overlay(alignment: .leading) { Rectangle().fill(ThingsColor.separator).frame(width: 1) }
            }
        }
        .accessibilityHidden(true)
    }

    private func weekDays(_ cal: Calendar) -> [Date] {
        var monday = cal
        monday.firstWeekday = 2
        let startOfWeek = monday.dateInterval(of: .weekOfYear, for: start)?.start ?? cal.startOfDay(for: start)
        return (0..<5).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private func events(on day: Date, _ cal: Calendar) -> [AgendaEvent] {
        let dayStart = cal.startOfDay(for: day)
        return calendar.events(from: dayStart, to: dayStart.addingTimeInterval(86_400), hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
    }

    private func block(title: String, from: Date, to: Date, on day: Date, first: Int, hourHeight: CGFloat,
                       fill: Color, ink: Color, cal: Calendar) -> some View {
        let dayStart = cal.date(bySettingHour: first, minute: 0, second: 0, of: day) ?? day
        let top = CGFloat(from.timeIntervalSince(dayStart) / 3600) * hourHeight
        let height = max(12, CGFloat(to.timeIntervalSince(from) / 3600) * hourHeight - 2)
        return Text(title)
            .font(.werk(size: 9.5, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(fill))
            .padding(.horizontal, 2)
            .offset(y: top)
    }
}

// MARK: - Opvolgen (F)

private struct MailFollowSheet: View {
    let item: GmailMailItem
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var afterDays: Int? = 3
    @State private var customDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var useCustom = false
    @State private var card = true
    @State private var snooze: Date?
    private let store = MailModeStore.shared

    var body: some View {
        SheetFrame(title: "Opvolgen", systemImage: "arrow.uturn.backward.circle") {
            SheetField(label: "Terug als er geen antwoord komt binnen") {
                HStack(spacing: 6) {
                    ForEach([2, 3, 7], id: \.self) { days in
                        Button(days == 7 ? "1 week" : "\(days) dagen") {
                            afterDays = days
                            useCustom = false
                            snooze = nil
                        }
                        .buttonStyle(MailFilterChipStyle(isOn: snooze == nil && !useCustom && afterDays == days))
                    }
                    Button("Datum") {
                        useCustom = true
                        snooze = nil
                    }
                    .buttonStyle(MailFilterChipStyle(isOn: snooze == nil && useCustom))
                    if useCustom && snooze == nil {
                        DatePicker("", selection: $customDate, in: Date()..., displayedComponents: [.date])
                            .labelsHidden()
                    }
                }
            }
            Toggle("Kaart in Wacht op klant", isOn: $card)
                .toggleStyle(.checkbox)
                .font(.werk(size: 12.5))
                .disabled(snooze != nil)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            SheetField(label: "Of later terug in de inbox") {
                HStack(spacing: 6) {
                    ForEach(snoozeChoices) { choice in
                        Button(choice.label) { snooze = snooze == choice.date ? nil : choice.date }
                            .buttonStyle(MailFilterChipStyle(isOn: snooze == choice.date))
                    }
                }
            }
        } buttons: {
            Spacer(minLength: 0)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button(snooze == nil ? "Archiveren en opvolgen" : "Archiveren tot \(Self.when(snooze ?? .now))", action: confirm)
                .buttonStyle(SheetButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private struct SnoozeChoice: Identifiable {
        let label: String
        let date: Date
        var id: String { label }
    }

    /// Vanmiddag (als het nog voor vier uur is), morgen en maandag om half negen.
    private var snoozeChoices: [SnoozeChoice] {
        let cal = Calendar.current
        var result: [SnoozeChoice] = []
        if let afternoon = cal.date(bySettingHour: 16, minute: 0, second: 0, of: .now), afternoon > .now {
            result.append(SnoozeChoice(label: "Vanmiddag 16:00", date: afternoon))
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now),
           let morning = cal.date(bySettingHour: 8, minute: 30, second: 0, of: tomorrow) {
            result.append(SnoozeChoice(label: "Morgen 08:30", date: morning))
        }
        if let monday = cal.nextDate(after: .now, matching: DateComponents(hour: 8, minute: 30, weekday: 2),
                                     matchingPolicy: .nextTime),
           !cal.isDateInTomorrow(monday) {
            result.append(SnoozeChoice(label: "Maandag 08:30", date: monday))
        }
        return result
    }

    private static func when(_ date: Date) -> String {
        "\(DutchDate.weekdayAndDay(date)) \(DutchDate.time(date))"
    }

    private func confirm() {
        let account = GmailSession.shared.account(for: item.id)
        store.closeSheet()
        if let snooze {
            FollowUpStore.shared.add(threadID: item.threadID, account: account, subject: item.subject, kind: .snooze, due: snooze)
            store.archive(item, announcing: "Gearchiveerd · terug op \(Self.when(snooze))", appState: appState)
            return
        }
        let due = useCustom
            ? (Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: customDate) ?? customDate)
            : Date().addingTimeInterval(Double(afterDays ?? 3) * 86_400)
        FollowUpStore.shared.add(threadID: item.threadID, account: account, subject: item.subject, kind: .noReply, due: due)
        let waiting = BoardService.columns(in: context).first { $0.id == "waiting" }
        if card, let waiting {
            store.takeOut(threadID: item.threadID)
            Task {
                await GmailSession.shared.createTask(from: item.summary, title: plainSubject(item.subject), minutes: 0,
                                                     column: waiting, context: context, appState: appState)
                store.refreshTasks()
            }
        } else {
            store.archive(item, announcing: "Gearchiveerd · terug als er geen antwoord is op \(DutchDate.weekdayAndDay(due))",
                          appState: appState)
        }
    }
}

// MARK: - Claude-concept (C)

private struct MailConceptSheet: View {
    let item: GmailMailItem
    @Environment(\.modelContext) private var context
    @State private var concept = MailConcept()
    @State private var edited: String?
    private let store = MailModeStore.shared

    var body: some View {
        SheetFrame(title: "Concept in jouw stijl", systemImage: "sparkles", width: 720) {
            HStack(alignment: .top, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(get: { edited ?? concept.text },
                                             set: { if edited != nil || $0 != concept.text { edited = $0 } }))
                        .font(.werk(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .frame(height: 300)
                        .sheetInput(height: nil)
                    if concept.isRunning && concept.text.isEmpty {
                        ProgressView().controlSize(.small).padding(14)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gebruikt")
                        .font(.werk(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fieldLabel)
                    Text("Het gesprek")
                        .font(.werk(size: 12))
                        .foregroundStyle(ThingsColor.textPrimary)
                    ForEach(concept.context) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.kind.uppercased())
                                .font(.werk(size: 9.5, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(ThingsColor.textSecondary)
                            Text(entry.text)
                                .font(.werk(size: 12))
                                .foregroundStyle(ThingsColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: MailModeMetrics.radius, style: .continuous)
                            .fill(ThingsColor.backgroundSidebar))
                    }
                }
                .frame(width: 210)
            }
            if let error = concept.error {
                Text(error).font(.werk(size: 12)).foregroundStyle(ThingsColor.deadline)
            }
        } buttons: {
            Button("Korter") { restart(.shorter) }
                .buttonStyle(MailFilterChipStyle(isOn: concept.length == .shorter))
                .disabled(concept.isRunning)
            Button("Uitgebreider") { restart(.longer) }
                .buttonStyle(MailFilterChipStyle(isOn: concept.length == .longer))
                .disabled(concept.isRunning)
            Spacer(minLength: 8)
            Button("Annuleren") {
                concept.cancel()
                store.closeSheet()
            }
            .buttonStyle(SheetButtonStyle(kind: .plain))
            Button("In antwoord zetten") {
                let text = edited ?? concept.text
                concept.cancel()
                store.closeSheet()
                store.replyTrigger.reply(text: text)
            }
            .buttonStyle(SheetButtonStyle(kind: .primary))
            .disabled((edited ?? concept.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { restart(.normal) }
        .onDisappear { concept.cancel() }
    }

    private func restart(_ length: MailConcept.Length) {
        edited = nil
        concept.start(item: item, client: store.clientName(for: item), length: length, modelContext: context)
    }
}

// MARK: - Nieuwsbrieven en meldingen in één keer

private struct MailBulkSheet: View {
    @Environment(AppState.self) private var appState
    /// Afzenders die deze keer niet meegaan.
    @State private var skipped: Set<String> = []
    private let store = MailModeStore.shared

    private struct SenderGroup: Identifiable {
        let items: [GmailMailItem]
        var first: GmailMailItem { items[0] }
        var id: String { first.fromAddress?.lowercased() ?? first.senderDisplay }
    }

    var body: some View {
        let groups = MailBulk.groups(store.bundle).map(SenderGroup.init)
        let chosen = groups.filter { !skipped.contains($0.id) }.flatMap(\.items)
        SheetFrame(title: "Nieuwsbrieven en meldingen", systemImage: "tray.full", detail: store.title(of: store.scope),
                   width: 640) {
            ScrollView {
                SheetList(items: groups) { group in row(group) }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: groups.count < 6)
            if !store.bulkRules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nooit in één keer", systemImage: "lock")
                        .font(.werk(size: 12.5, weight: .semibold))
                        .foregroundStyle(ThingsColor.textSecondary)
                    ForEach(store.bulkRules) { rule in
                        HStack(spacing: 12) {
                            Initials(text: rule.title)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.title)
                                    .font(.werk(size: 13.5, weight: .semibold))
                                    .foregroundStyle(ThingsColor.textPrimary)
                                Text(rule.field == .sender ? "Afzender" : (rule.field == .domain ? "Domein" : "Soort"))
                                    .font(.werk(size: 12))
                                    .foregroundStyle(ThingsColor.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("Weer meenemen") { store.removeBulkRule(rule) }
                                .buttonStyle(SheetButtonStyle())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: max(6, MailModeMetrics.radius + 2), style: .continuous)
                            .fill(ThingsColor.backgroundSidebar))
                    }
                }
            }
        } buttons: {
            Spacer(minLength: 0)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button(chosen.count == 1 ? "Archiveer 1 mail" : "Archiveer \(chosen.count) mails") {
                store.closeSheet()
                store.archiveBulk(chosen, appState: appState)
            }
            .buttonStyle(SheetButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(chosen.isEmpty)
        }
    }

    private func toggle(_ id: String) {
        if skipped.contains(id) { skipped.remove(id) } else { skipped.insert(id) }
    }

    private func row(_ group: SenderGroup) -> some View {
        let isOn = !skipped.contains(group.id)
        let kind = store.kind(of: group.first)
        return HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle(group.id) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Initials(text: group.first.senderDisplay)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.first.senderDisplay)
                        .font(.werk(size: 13.5, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                    Text(kind.title)
                        .font(.werk(size: 10.5, weight: .medium))
                        .foregroundStyle(ThingsColor.tagText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ThingsColor.tagBackground))
                }
                Text(group.items.prefix(2).map(\.subject).joined(separator: " · "))
                    .font(.werk(size: 12))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(group.items.count == 1 ? "1 mail" : "\(group.items.count) mails")
                .font(.werk(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textSecondary)
            Menu { menu(group, kind: kind) } label: {
                Image(systemName: "ellipsis")
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Meer")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .opacity(isOn ? 1 : 0.55)
        .background(isOn ? Color.clear : ThingsColor.backgroundSidebar)
        .contentShape(Rectangle())
        .onTapGesture { toggle(group.id) }
        .contextMenu { menu(group, kind: kind) }
    }

    @ViewBuilder private func menu(_ group: SenderGroup, kind: MailKind) -> some View {
        Button(skipped.contains(group.id) ? "Deze keer wel" : "Deze keer niet") { toggle(group.id) }
        Divider()
        if let address = group.first.fromAddress?.lowercased() {
            Button("\(address) nooit in één keer") { store.addBulkRule(.sender(address)) }
            if let host = ClientNaming.domain(ofAddress: address) {
                let domain = ClientNaming.registrableDomain(of: host)
                Button("Alles van \(domain) nooit in één keer") { store.addBulkRule(.domain(domain)) }
            }
        }
        Button(kind == .newsletter ? "Nieuwsbrieven nooit in één keer" : "Meldingen nooit in één keer") {
            store.addBulkRule(.kind(kind))
        }
    }
}

/// Beginletters in een grijs vlak (een afzender of mailbox in een blad).
private struct Initials: View {
    let text: String

    private var letters: String {
        let words = text.split { !$0.isLetter && !$0.isNumber }.prefix(2)
        let result = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        Text(letters)
            .font(.werk(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: max(6, MailModeMetrics.radius + 2), style: .continuous)
                .fill(ThingsColor.textTertiary))
            .accessibilityHidden(true)
    }
}

// MARK: - Uitgebreid zoeken (⌘F)

private struct MailSearchSheet: View {
    @State private var form = MailModeStore.shared.searchForm
    @State private var mailboxes = Set(MailModeStore.shared.searchAccountChoice)
    @FocusState private var focused: Bool
    private let store = MailModeStore.shared
    private let gmail = GmailSession.shared

    var body: some View {
        SheetFrame(title: "Zoeken", systemImage: "magnifyingglass", detail: detail, width: 680) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    SheetField(label: "Met de woorden") {
                        TextField("", text: $form.words).sheetInput().focused($focused).onSubmit(search)
                    }
                    SheetField(label: "Zonder de woorden") {
                        TextField("", text: $form.exclude).sheetInput().onSubmit(search)
                    }
                    SheetField(label: "Van (naam of adres)") {
                        TextField("", text: $form.from).sheetInput().onSubmit(search)
                    }
                    SheetField(label: "Aan of cc (naam of adres)") {
                        TextField("", text: $form.to).sheetInput().onSubmit(search)
                    }
                    SheetField(label: "Onderwerp") {
                        TextField("", text: $form.subject).sheetInput().onSubmit(search)
                    }
                }
                .frame(width: 330)
                VStack(alignment: .leading, spacing: 14) {
                    SheetField(label: "Periode") {
                        WrapStack(spacing: 6) {
                            ForEach(MailSearchForm.Period.allCases) { period in
                                Button(period.title) { form.period = period }
                                    .buttonStyle(MailFilterChipStyle(isOn: form.period == period))
                            }
                        }
                    }
                    SheetField(label: "Bijlage") {
                        Toggle("Met bijlage", isOn: $form.hasAttachment)
                    }
                    SheetField(label: "Naam of soort bijlage") {
                        TextField("", text: $form.attachmentName)
                            .sheetInput()
                            .onSubmit(search)
                    }
                    SheetField(label: "Alleen") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Ongelezen", isOn: $form.unread)
                            Toggle("Met ster", isOn: $form.starred)
                            Toggle("Ook spam en prullenbak", isOn: $form.includeSpamTrash)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .font(.werk(size: 13))
            }
            SheetField(label: "Mailboxen") {
                SheetList(items: gmail.accounts) { account in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { mailboxes.contains(account) },
                                                 set: { on in if on { mailboxes.insert(account) } else { mailboxes.remove(account) } }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        Initials(text: gmail.displayName(account))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(gmail.displayName(account))
                                .font(.werk(size: 13.5, weight: .semibold))
                                .foregroundStyle(ThingsColor.textPrimary)
                            Text(account)
                                .font(.werk(size: 12))
                                .foregroundStyle(ThingsColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if mailboxes.contains(account) { mailboxes.remove(account) } else { mailboxes.insert(account) }
                    }
                }
            }
        } buttons: {
            Button("Wissen") {
                form = MailSearchForm()
                mailboxes = Set(gmail.accounts)
            }
            .buttonStyle(SheetButtonStyle(kind: .plain))
            .disabled(form.isEmpty && mailboxes == Set(gmail.accounts))
            Spacer(minLength: 0)
            Button("Annuleren") { store.closeSheet() }
                .buttonStyle(SheetButtonStyle(kind: .plain))
            Button("Zoeken", action: search)
                .buttonStyle(SheetButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(form.isEmpty || mailboxes.isEmpty)
        }
        .onAppear { focused = true }
    }

    private var detail: String {
        mailboxes.count == gmail.accounts.count ? "Alle mail"
            : (mailboxes.count == 1 ? "1 mailbox" : "\(mailboxes.count) mailboxen")
    }

    private func search() {
        guard !form.isEmpty, !mailboxes.isEmpty else { return }
        store.applySearch(form, mailboxes: gmail.accounts.filter { mailboxes.contains($0) })
    }
}
