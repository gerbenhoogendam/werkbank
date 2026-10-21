import SwiftData
import SwiftUI

/// Details van een agenda-afspraak, als paneel boven het hoofdvenster.
struct EventDetailView: View {
    let event: AgendaEvent

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
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
            }
            .padding(12)
        }
        .background(ThingsColor.backgroundContent)
    }

    private var whenText: String {
        let calendar = Calendar.current
        if event.isAllDay {
            // Bij een hele dag is `end` de start van de dag erna.
            let last = calendar.date(byAdding: .day, value: -1, to: event.end) ?? event.end
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
