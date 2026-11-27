import SwiftUI
import WerkbankCore

/// Nieuwe afspraak, een afspraak wijzigen of dupliceren: titel, agenda, dag, begin en einde (of hele dag), plaats en
/// herinnering. Bewaart via EventKit (`CalendarService`); bij wijzigen blijven de overige velden (herhaling, link,
/// notities, beschikbaarheid) zoals ze waren.
struct AgendaEventEditor: View {
    enum Mode {
        case new(Date)
        case edit(AgendaEvent)
        case duplicate(AgendaEvent)
        /// Een uitnodiging uit een `.ics`-bestand (Open met › Zwoeg Bank).
        case invite(ICSEvent)
    }

    private let service = CalendarService.shared
    private let mode: Mode
    /// Na bewaren (het blad sluit zichzelf).
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// De velden zoals ze in EventKit stonden (wijzigen, dupliceren); nil bij een nieuwe afspraak.
    @State private var original: EventEdit?
    @State private var title = ""
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var calendarID = ""
    @State private var alert: EventAlert = .none
    @State private var failure: String?
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    init(day: Date) {
        self.init(mode: .new(day))
    }

    init(mode: Mode, onSaved: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSaved = onSaved
        let calendar = Calendar.current
        let begin: Date
        let finish: Date
        switch mode {
        case .new(let day):
            let base = calendar.startOfDay(for: day)
            if calendar.isDateInToday(day) {
                let nextHour = calendar.component(.hour, from: .now) + 1
                begin = calendar.date(byAdding: .hour, value: min(nextHour, 23), to: base) ?? .now
            } else {
                begin = calendar.date(byAdding: .hour, value: 9, to: base) ?? base
            }
            finish = begin.addingTimeInterval(3600)
        case .edit(let event), .duplicate(let event):
            begin = event.start
            finish = event.end
        case .invite(let invite):
            begin = invite.start
            finish = invite.isAllDay ? invite.start.addingTimeInterval(3600) : invite.end
        }
        _day = State(initialValue: calendar.startOfDay(for: begin))
        _start = State(initialValue: begin)
        _end = State(initialValue: finish)
    }

    private var heading: String {
        switch mode {
        case .new: return "NIEUWE AFSPRAAK"
        case .edit: return "AFSPRAAK WIJZIGEN"
        case .duplicate: return "KOPIE AFSPRAAK"
        case .invite: return "UITNODIGING"
        }
    }

    private var selectedCalendar: AgendaCalendar? {
        service.writableCalendars.first { $0.id == calendarID }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCalendar != nil
    }

    /// Duur van begin tot einde (uren en minuten van de tijdvelden).
    private var duration: TimeInterval {
        let calendar = Calendar.current
        let a = calendar.dateComponents([.hour, .minute], from: start)
        let b = calendar.dateComponents([.hour, .minute], from: end)
        let minutes = ((b.hour ?? 0) * 60 + (b.minute ?? 0)) - ((a.hour ?? 0) * 60 + (a.minute ?? 0))
        return TimeInterval(max(0, minutes) * 60)
    }

    private var alertItems: [PhSegmented<EventAlert>.Item] {
        [PhSegmented<EventAlert>.Item(value: .none, title: "Geen"),
         PhSegmented<EventAlert>.Item(value: .min5, title: "5 min"),
         PhSegmented<EventAlert>.Item(value: .min15, title: "15 min"),
         PhSegmented<EventAlert>.Item(value: .min30, title: "30 min"),
         PhSegmented<EventAlert>.Item(value: .hour1, title: "1 uur")]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(heading)
                            .font(Ph.poster(36))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        if !isAllDay {
                            Text(Billing.formatHM(duration))
                                .font(Ph.poster(26))
                                .foregroundStyle(Ph.ink2)
                        }
                    }
                    fields
                    reminder
                    if let failure {
                        Text(failure)
                            .font(Ph.text(13, .medium))
                            .foregroundStyle(Ph.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            buttons
        }
        .background(Ph.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Ph.paper)
        .environment(\.locale, Locale(identifier: "nl_NL"))
        .tint(Ph.ink)
        .onAppear(perform: load)
        // Begin verschuiven neemt het einde mee (zelfde duur).
        .onChange(of: start) { old, new in
            end = end.addingTimeInterval(new.timeIntervalSince(old))
        }
    }

    /// Eén keer bij het openen: de velden uit EventKit (wijzigen, dupliceren) of de standaardagenda (nieuw).
    private func load() {
        guard !loaded else { return }
        loaded = true
        let defaultCalendar = service.defaultTargetCalendarID(hiddenCalendarIDs: AppSettings.hiddenCalendarIDs) ?? ""
        switch mode {
        case .new:
            calendarID = defaultCalendar
            titleFocused = true
        case .invite(let invite):
            calendarID = defaultCalendar
            title = invite.title
            location = invite.location
            isAllDay = invite.isAllDay
        case .edit(let event), .duplicate(let event):
            let edit = service.editableEvent(for: event)
            original = edit
            title = edit?.title ?? event.title
            location = edit?.location ?? (event.location ?? "")
            isAllDay = edit?.isAllDay ?? event.isAllDay
            alert = edit?.alert ?? .none
            let writable = service.writableCalendars
            if let id = edit?.calendarID, writable.contains(where: { $0.id == id }) {
                calendarID = id
            } else if writable.contains(where: { $0.id == event.calendarID }) {
                calendarID = event.calendarID
            } else {
                calendarID = defaultCalendar
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            PhFieldRow(label: "Titel") {
                TextField("Titel", text: $title)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
                    .focused($titleFocused)
                    .submitLabel(.done)
            }
            PhFieldRow(label: "Agenda") {
                Menu {
                    ForEach(service.writableCalendars) { calendar in
                        Button(calendar.title) { calendarID = calendar.id }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Rectangle().fill(selectedCalendar?.color ?? Ph.line).frame(width: 10, height: 10)
                        Text(selectedCalendar?.title ?? "Kies")
                            .font(Ph.text(15))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ph.ink2)
                    }
                    .contentShape(Rectangle())
                }
            }
            PhFieldRow(label: "Dag") {
                DatePicker("Dag", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            Toggle(isOn: $isAllDay) {
                PhCaps(text: "Hele dag", size: 11)
            }
            .toggleStyle(PhToggleStyle())
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
            if !isAllDay {
                PhFieldRow(label: "Begin") {
                    DatePicker("Begin", selection: $start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
                PhFieldRow(label: "Einde") {
                    DatePicker("Einde", selection: $end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
            }
            PhFieldRow(label: "Waar") {
                TextField("Plaats", text: $location)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
            }
        }
        .phCard()
    }

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: alert == .custom ? "Herinnering · aangepast" : "Herinnering")
            PhSegmented(items: alertItems, selection: $alert)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("ANNULEER") { dismiss() }
                .buttonStyle(PhSecondaryStyle(height: 52))
                .frame(width: 130)
            Button("BEWAAR", action: save)
                .buttonStyle(PhPrimaryStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    /// Dag uit het datumveld, uur en minuut uit de tijdvelden.
    private func combine(_ day: Date, _ time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private func save() {
        let begin: Date
        let finish: Date
        if isAllDay {
            // `CalendarService` maakt er het begin en het einde van de dag van.
            begin = Calendar.current.startOfDay(for: day)
            finish = begin
        } else {
            begin = combine(day, start)
            finish = combine(day, end)
            guard finish > begin else {
                failure = CalendarService.CalendarError.invalidRange.errorDescription
                return
            }
        }
        var edit = original
            ?? service.blankEdit(start: begin, end: finish, hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
        var chosenAlert = alert
        if case .duplicate = mode {
            // Een kopie is een nieuwe afspraak: een aangepaste herhaling of herinnering gaat niet mee.
            if edit.repeatOption == .custom { edit.repeatOption = .none }
            if chosenAlert == .custom { chosenAlert = .none }
        }
        edit.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edit.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        edit.calendarID = calendarID
        edit.isAllDay = isAllDay
        edit.start = begin
        edit.end = finish
        edit.alert = chosenAlert
        if case .invite(let invite) = mode {
            var lines: [String] = []
            if !invite.organizerEmail.isEmpty {
                lines.append(invite.organizerName.isEmpty ? invite.organizerEmail
                                                          : "\(invite.organizerName) <\(invite.organizerEmail)>")
            }
            if !invite.notes.isEmpty { lines.append(invite.notes) }
            edit.notes = lines.joined(separator: "\n\n")
            edit.urlText = invite.url
        }
        do {
            switch mode {
            case .edit(let event):
                guard let source = original else { throw CalendarService.CalendarError.eventNotFound }
                try service.saveEvent(event, edit: edit, original: source, thisAndFuture: false)
                appState.showToast("Afspraak gewijzigd")
            case .new, .duplicate, .invite:
                try service.createEvent(edit: edit)
                appState.showToast("Afspraak gemaakt")
            }
            onSaved()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
