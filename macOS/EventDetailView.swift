import AppKit
import SwiftData
import SwiftUI

/// Details van een agenda-afspraak, als paneel boven het hoofdvenster.
struct EventDetailView: View {
    let target: EventTarget
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private let service = CalendarService.shared
    @AppStorage(SettingsKey.hiddenCalendars) private var disabledRaw = ""

    private var existing: AgendaEvent? {
        if case .existing(let event) = target { return event }
        return nil
    }

    /// Hulp voor de weergave van een nieuwe afspraak: een lege "afspraak" met het gekozen tijdvak.
    private var event: AgendaEvent {
        if let existing { return existing }
        guard case .new(let start, let end) = target else { fatalError("onbereikbaar") }
        return AgendaEvent(id: "new", title: "", start: start, end: end, isAllDay: false, calendarID: "",
                           calendarTitle: "", color: .accentColor, eventIdentifier: "", isRecurring: false,
                           location: nil, notes: nil, url: nil, organizer: nil, attendees: [])
    }
    @State private var original: EventEdit?
    @State private var draft: EventEdit?
    @State private var isEditing = false
    @State private var errorText: String?
    @State private var askSpan: SpanAction?

    private enum SpanAction: Hashable, Identifiable {
        case save, delete
        case move(AgendaCalendar)
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
        // Klik buiten het venster sluit het (niet als je wijzigingen hebt die nog niet zijn opgeslagen).
        .background(OutsideClickCatcher {
            if !isEditing || draft == original { onClose() }
        })
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(ThingsColor.textTertiary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .help("Sluiten")
        }
        .task {
            if let existing {
                original = service.editableEvent(for: existing)
            } else if case .new(let start, let end) = target {
                let blank = service.blankEdit(start: start, end: end, hiddenCalendarIDs: AppSettings.parseHidden(disabledRaw))
                original = blank
                draft = blank
                isEditing = true
            }
        }
        .confirmationDialog("Deze afspraak herhaalt",
                            isPresented: Binding(get: { askSpan != nil }, set: { if !$0 { askSpan = nil } }),
                            titleVisibility: .visible, presenting: askSpan) { action in
            Button("Alleen deze \(Self.verb(action))") { commit(action, future: false) }
            Button("Deze en alle volgende \(Self.verb(action))") {
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
                            calendarLabel
                            if event.isRecurring {
                                Image(systemName: "repeat")
                                    .font(.system(size: 10))
                                    .foregroundStyle(ThingsColor.textTertiary)
                            }
                        }
                    }
                    .padding(.trailing, 28)

                    row("clock", whenText)
                    if let location = event.location {
                        row("mappin.and.ellipse", location)
                        EventLocationView(location: location, arrival: event.start)
                    }
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
                    TextField("Titel", text: edit.title, prompt: Text(existing == nil ? "Nieuwe afspraak" : ""))
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
                    if existing != nil {
                        Button("Verwijderen", role: .destructive) {
                            if event.isRecurring { askSpan = .delete } else { commit(.delete, future: false) }
                        }
                    }
                    Spacer()
                    Button("Annuleer") { if existing == nil { onClose() } else { isEditing = false } }
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

    private static func verb(_ action: SpanAction) -> String {
        switch action {
        case .save: "opslaan"
        case .delete: "verwijderen"
        case .move: "verplaatsen"
        }
    }

    // MARK: Agenda wisselen

    /// De agenda van de afspraak; aanklikken geeft een menu met de andere agenda's waarin je mag schrijven.
    @ViewBuilder private var calendarLabel: some View {
        let label = HStack(spacing: 6) {
            Circle().fill(event.color).frame(width: 9, height: 9)
            Text(event.calendarTitle)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
        }
        let targets = service.writableCalendars.filter { $0.id != event.calendarID }
        if existing != nil, original?.canModify == true, !targets.isEmpty {
            Menu {
                ForEach(targets) { target in
                    Button {
                        if event.isRecurring { askSpan = .move(target) } else { commit(.move(target), future: false) }
                    } label: {
                        Label { Text(target.title) } icon: { Image(nsImage: Self.dot(target.color)) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    label
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ThingsColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Andere agenda kiezen")
        } else {
            label
        }
    }

    /// Gekleurd rondje voor een menu-item (SF Symbols worden in een menu eenkleurig getekend).
    private static func dot(_ color: Color) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func commit(_ action: SpanAction?, future: Bool) {
        if case .move(let target) = action, let existing {
            do {
                try service.moveEvent(existing, toCalendarID: target.id, thisAndFuture: future)
                appState.showToast("Verplaatst naar \(target.title)")
                onClose()   // EventKit kan de afspraak bij een andere agenda een nieuw id geven
            } catch {
                errorText = error.localizedDescription
                appState.showToast("Verplaatsen mislukt: \(error.localizedDescription)", seconds: 5)
            }
            return
        }
        guard let action, let draft, let original else { return }
        do {
            switch action {
            case .save:
                if let existing {
                    try service.saveEvent(existing, edit: draft, original: original, thisAndFuture: future)
                } else {
                    try service.createEvent(edit: draft)
                }
            case .delete:
                if let existing { try service.deleteEvent(existing, thisAndFuture: future) }
            case .move:
                return
            }
            appState.showToast(action == .save ? "Afspraak opgeslagen" : "Afspraak verwijderd")
            onClose()
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

/// Meldt een muisklik in hetzelfde venster maar buiten deze view (menu's en kalenderpopovers zijn eigen vensters
/// en tellen dus niet mee).
struct OutsideClickCatcher: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class CatcherView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    DispatchQueue.main.async { self.onOutsideClick?() }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
