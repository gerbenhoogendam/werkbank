import SwiftUI

/// Nieuwe afspraak: titel, dag, begin en einde, plaats en agenda. Bewaart via EventKit (`CalendarService`).
struct AgendaEventEditor: View {
    private let service = CalendarService.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var location = ""
    @State private var calendarID = ""
    @State private var failure: String?
    @FocusState private var titleFocused: Bool

    init(day: Date) {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: day)
        let begin: Date
        if calendar.isDateInToday(day) {
            let nextHour = calendar.component(.hour, from: .now) + 1
            begin = calendar.date(byAdding: .hour, value: min(nextHour, 23), to: base) ?? .now
        } else {
            begin = calendar.date(byAdding: .hour, value: 9, to: base) ?? base
        }
        _day = State(initialValue: base)
        _start = State(initialValue: begin)
        _end = State(initialValue: begin.addingTimeInterval(3600))
    }

    private var selectedCalendar: AgendaCalendar? {
        service.writableCalendars.first { $0.id == calendarID }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCalendar != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("NIEUWE AFSPRAAK")
                        .font(Ph.poster(36))
                        .foregroundStyle(Ph.ink)
                    fields
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
        .onAppear {
            if calendarID.isEmpty {
                calendarID = service.defaultTargetCalendarID(hiddenCalendarIDs: AppSettings.hiddenCalendarIDs) ?? ""
            }
            titleFocused = true
        }
        // Begin verschuiven neemt het einde mee (zelfde duur).
        .onChange(of: start) { old, new in
            end = end.addingTimeInterval(new.timeIntervalSince(old))
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
            PhFieldRow(label: "Dag") {
                DatePicker("Dag", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
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
            PhFieldRow(label: "Waar") {
                TextField("Plaats", text: $location)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
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
        }
        .phCard()
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
        let begin = combine(day, start)
        let finish = combine(day, end)
        guard finish > begin else {
            failure = CalendarService.CalendarError.invalidRange.errorDescription
            return
        }
        var edit = service.blankEdit(start: begin, end: finish, hiddenCalendarIDs: AppSettings.hiddenCalendarIDs)
        edit.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edit.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        edit.calendarID = calendarID
        do {
            try service.createEvent(edit: edit)
            appState.showToast("Afspraak gemaakt")
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
