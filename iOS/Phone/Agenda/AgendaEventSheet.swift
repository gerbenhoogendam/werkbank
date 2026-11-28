import SwiftUI
import WerkbankCore

/// Het bewerkblad dat vanuit een afspraak opent (wijzigen of dupliceren).
struct AgendaEditorStart: Identifiable {
    let id = UUID()
    let mode: AgendaEventEditor.Mode
}

/// Een afspraak bekijken: titel, tijd, plaats (navigeren), notities en deelnemers; wijzigen, dupliceren, verwijderen,
/// tijd schrijven of openen in Agenda.
struct AgendaEventSheet: View {
    let event: AgendaEvent
    /// Sluit het blad en opent daarna de tijdinvoer.
    let onWriteTime: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var editor: AgendaEditorStart?
    /// Bewaard in het bewerkblad: dit blad toont dan oude gegevens en gaat ook dicht.
    @State private var savedInEditor = false
    @State private var confirmDelete = false
    @State private var failure: String?

    /// Staat de afspraak in een agenda die je kunt wijzigen?
    private var canModify: Bool {
        CalendarService.shared.writableCalendars.contains { $0.id == event.calendarID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            PhEyebrow(text: event.calendarTitle)
                            Spacer(minLength: 8)
                            if canModify {
                                Button {
                                    confirmDelete = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(PhIconButtonStyle(size: 40))
                                .accessibilityLabel("Verwijder")
                            }
                        }
                        Text(event.title.uppercased())
                            .font(Ph.poster(40))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .padding(.bottom, -4)
                        if !event.isAllDay {
                            HStack(alignment: .lastTextBaseline, spacing: 10) {
                                Text("\(DutchDate.time(event.start)) – \(DutchDate.time(event.end))")
                                    .font(Ph.poster(28))
                                    .foregroundStyle(Ph.ink)
                                PhCaps(text: Billing.formatHM(event.end.timeIntervalSince(event.start)), size: 10.5)
                            }
                        }
                    }
                    details
                    if let notes = event.notes { notesCard(notes) }
                    if !event.attendees.isEmpty { attendeesCard }
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
            actions
        }
        .background(Ph.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Ph.paper)
        .presentationDragIndicator(.visible)
        .sheet(item: $editor, onDismiss: {
            if savedInEditor { dismiss() }
        }) { start in
            AgendaEventEditor(mode: start.mode) { savedInEditor = true }
        }
        .confirmationDialog("Afspraak verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if event.isRecurring {
                Button("Alleen deze", role: .destructive) { delete(thisAndFuture: false) }
                Button("Deze en alle volgende", role: .destructive) { delete(thisAndFuture: true) }
            } else {
                Button("Verwijder", role: .destructive) { delete(thisAndFuture: false) }
            }
            Button("Annuleer", role: .cancel) {}
        }
    }

    private func delete(thisAndFuture: Bool) {
        do {
            try CalendarService.shared.deleteEvent(event, thisAndFuture: thisAndFuture)
            appState.showToast("Afspraak verwijderd")
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Route naar de plaats in de gekozen app (Voorkeuren › Agenda; standaard Waze).
    private func navigate(to location: String) {
        guard let url = PhoneNavigationApp.current.url(to: location) else { return }
        openURL(url)
    }

    private var timeText: String {
        let day = AgendaDates.dayAndMonth(event.start)
        if event.isAllDay { return "\(day) · HELE DAG" }
        if !AgendaDates.sameDay(event.start, event.end.addingTimeInterval(-1)) {
            return "\(day) \(DutchDate.time(event.start)) – \(AgendaDates.dayAndMonth(event.end)) \(DutchDate.time(event.end))"
        }
        return "\(day) · \(DutchDate.time(event.start)) – \(DutchDate.time(event.end))"
    }

    private var details: some View {
        VStack(spacing: 0) {
            PhFieldRow(label: "Tijd") {
                Text(timeText)
                    .font(Ph.text(14))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            if let location = event.location {
                PhFieldRow(label: "Waar") {
                    Text(location)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    Button {
                        navigate(to: location)
                    } label: {
                        Label("NAVIGEER", systemImage: "location.fill")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(PhSecondaryStyle(height: 34))
                    .fixedSize()
                }
            }
            PhFieldRow(label: "Agenda") {
                HStack(spacing: 8) {
                    Rectangle().fill(event.color).frame(width: 10, height: 10)
                    Text(event.calendarTitle)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if let organizer = event.organizer {
                PhFieldRow(label: "Van") {
                    Text(organizer)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let url = event.url {
                PhFieldRow(label: "Link") {
                    Button {
                        openURL(url)
                    } label: {
                        Text(url.host ?? url.absoluteString)
                            .font(Ph.text(14, .medium))
                            .foregroundStyle(Ph.olive)
                            .underline()
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .phCard()
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhCaps(text: "Notities")
            Text(notes)
                .font(Ph.text(14))
                .foregroundStyle(Ph.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .phCard()
        }
    }

    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhCaps(text: "Deelnemers \(event.attendees.count)")
            VStack(spacing: 0) {
                ForEach(Array(event.attendees.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 10) {
                        PhAvatar(name: name, size: 28)
                        Text(name)
                            .font(Ph.text(14))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if index < event.attendees.count - 1 { Rectangle().fill(Ph.hair).frame(height: 1) }
                    }
                }
            }
            .phCard()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    editor = AgendaEditorStart(mode: .duplicate(event))
                } label: {
                    Label("DUPLICEER", systemImage: "plus.square.on.square")
                }
                .buttonStyle(PhSecondaryStyle())
                Button {
                    let seconds = Int(event.start.timeIntervalSinceReferenceDate)
                    if let url = URL(string: "calshow:\(seconds)") { openURL(url) }
                } label: {
                    Label("IN AGENDA", systemImage: "calendar")
                }
                .buttonStyle(PhSecondaryStyle())
            }
            HStack(spacing: 8) {
                if canModify {
                    Button("BEWERK") { editor = AgendaEditorStart(mode: .edit(event)) }
                        .buttonStyle(PhSecondaryStyle(height: 52))
                        .frame(width: 130)
                }
                Button(action: onWriteTime) {
                    Label("TIJD SCHRIJVEN", systemImage: "clock")
                }
                .buttonStyle(PhPrimaryStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }
}
