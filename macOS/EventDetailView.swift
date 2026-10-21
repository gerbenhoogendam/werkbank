import SwiftData
import SwiftUI

/// Details van een agenda-afspraak, als paneel boven het hoofdvenster.
struct EventDetailView: View {
    let event: AgendaEvent

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private let service = CalendarService.shared
    @State private var original: EventEdit?
    @State private var draft: EventEdit?
    @State private var isEditing = false
    @State private var errorText: String?
    @State private var askSpan: SpanAction?

    private enum SpanAction: Identifiable {
        case save, delete
        var id: Self { self }
    }

    var body: some View {
        Group {
            if isEditing, let binding = Binding($draft) {
                editor(binding)
            } else {
                reader
            }
        }
        .background(ThingsColor.backgroundContent)
        .task { original = service.editableEvent(for: event) }
        .confirmationDialog("Deze afspraak herhaalt",
                            isPresented: Binding(get: { askSpan != nil }, set: { if !$0 { askSpan = nil } }),
                            titleVisibility: .visible, presenting: askSpan) { action in
            Button(action == .delete ? "Alleen deze verwijderen" : "Alleen deze opslaan") { commit(action, future: false) }
            Button(action == .delete ? "Deze en alle volgende verwijderen" : "Deze en alle volgende opslaan") {
                commit(action, future: true)
            }
            Button("Annuleer", role: .cancel) {}
        }
    }

    // MARK: Lezen

    private var reader: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ThingsColor.textPrimary)
                            .textSelection(.enabled)
                        HStack(spacing: 6) {
                            Circle().fill(event.color).frame(width: 9, height: 9)
                            Text(event.calendarTitle)
                                .thingsFont(.metadata)
                                .foregroundStyle(ThingsColor.textSecondary)
                            if event.isRecurring {
                                Image(systemName: "repeat")
                                    .font(.system(size: 10))
                                    .foregroundStyle(ThingsColor.textTertiary)
                            }
                        }
                    }
                    .padding(.trailing, 28)

                    row("clock", whenText)
                    if let location = event.location { row("mappin.and.ellipse", location) }
                    if let url = event.url {
                        row("link", url.absoluteString) { NSWorkspace.shared.open(url) }
                    }
                    if let organizer = event.organizer { row("person.crop.circle", "Organisator: \(organizer)") }
                    if !event.attendees.isEmpty {
                        row("person.2", event.attendees.joined(separator: ", "))
                    }
                    if let notes = event.notes {
                        Rectangle().fill(ThingsColor.separator).frame(height: 1)
                        Text(notes)
                            .thingsFont(.notes)
                            .foregroundStyle(ThingsColor.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            HStack {
                Button {
                    if TimerService.addCalendarEvent(event, in: context) != nil {
                        appState.showToast("Afspraak toegevoegd aan Tijd schrijven")
                    } else {
                        appState.showToast("Deze afspraak staat al in Tijd schrijven")
                    }
                } label: {
                    Label("Toevoegen aan Tijd schrijven", systemImage: "clock.badge.checkmark")
                }
                Spacer()
                if let original, original.canModify {
                    Button {
                        draft = original
                        errorText = nil
                        isEditing = true
                    } label: {
                        Label("Bewerken", systemImage: "pencil")
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: Bewerken

    private func editor(_ edit: Binding<EventEdit>) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Titel", text: edit.title)
                    TextField("Locatie", text: edit.location)
                    TextField("Link (URL)", text: edit.urlText)
                }
                Section {
                    Toggle("Hele dag", isOn: edit.isAllDay)
                    DatePicker("Begin", selection: edit.start,
                               displayedComponents: edit.wrappedValue.isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Einde", selection: edit.end,
                               displayedComponents: edit.wrappedValue.isAllDay ? .date : [.date, .hourAndMinute])
                    Picker("Herhalen", selection: edit.repeatOption) {
                        ForEach(EventRepeat.allCases.filter { $0 != .custom || edit.wrappedValue.repeatOption == .custom }) {
                            Text($0.title).tag($0)
                        }
                    }
                    Picker("Herinnering", selection: edit.alert) {
                        ForEach(EventAlert.allCases.filter { $0 != .custom || edit.wrappedValue.alert == .custom }) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section {
                    Picker("Agenda", selection: edit.calendarID) {
                        ForEach(service.writableCalendars) { Text($0.title).tag($0.id) }
                    }
                    Picker("Toon als", selection: edit.availability) {
                        ForEach(EventAvailability.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Notities") {
                    TextEditor(text: edit.notes)
                        .font(.system(size: 13))
                        .frame(minHeight: 110)
                }
                if !event.attendees.isEmpty {
                    Section("Deelnemers (alleen lezen)") {
                        Text(event.attendees.joined(separator: ", "))
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                }
            }
            .formStyle(.grouped)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                if let errorText {
                    Text(errorText)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.deadline)
                }
                HStack {
                    Button("Verwijderen", role: .destructive) {
                        if event.isRecurring { askSpan = .delete } else { commit(.delete, future: false) }
                    }
                    Spacer()
                    Button("Annuleer") { isEditing = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Opslaan") {
                        if event.isRecurring { askSpan = .save } else { commit(.save, future: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }

    private func commit(_ action: SpanAction?, future: Bool) {
        guard let action, let draft, let original else { return }
        do {
            switch action {
            case .save: try service.saveEvent(event, edit: draft, original: original, thisAndFuture: future)
            case .delete: try service.deleteEvent(event, thisAndFuture: future)
            }
            appState.showToast(action == .save ? "Afspraak opgeslagen" : "Afspraak verwijderd")
            PanelStore.shared.close(.event(event))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var whenText: String {
        let calendar = Calendar.current
        if event.isAllDay {
            // Het einde van een hele dag is 23:59:59 of de start van de dag erna.
            let last = event.end.addingTimeInterval(-1)
            let first = event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "nl_NL")))
            if calendar.isDate(last, inSameDayAs: event.start) { return "\(first), hele dag" }
            let end = last.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "nl_NL")))
            return "\(first) t/m \(end)"
        }
        let day = event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "nl_NL")))
        if calendar.isDate(event.start, inSameDayAs: event.end) {
            return "\(day), \(DutchDate.range(event.start, event.end))"
        }
        let endDay = event.end.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "nl_NL")))
        return "\(day) \(event.start.formatted(date: .omitted, time: .shortened)) – \(endDay) \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func row(_ symbol: String, _ text: String, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(ThingsColor.textTertiary)
                .frame(width: 18)
            if let action {
                Button(action: action) {
                    Text(text).foregroundStyle(ThingsColor.accent).lineLimit(2)
                }
                .buttonStyle(.plain)
            } else {
                Text(text)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .thingsFont(.notes)
    }
}
