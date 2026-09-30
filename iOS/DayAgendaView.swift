import SwiftUI
import UIKit

/// Dagagenda op iPhone: compacte lijst zoals "Vandaag" in Things (kleurstip, tijd, titel).
/// Tik op een afspraak om die aan Tijd schrijven toe te voegen.
struct DayAgendaView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.hiddenCalendars) private var hiddenRaw = ""

    private let service = CalendarService.shared
    private let calendar = Calendar.current
    @State private var offset = 0

    private var day: Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
    }
    private var hiddenIDs: Set<String> { AppSettings.parseHidden(hiddenRaw) }

    var body: some View {
        Group {
            if service.hasAccess { content } else { CalendarAccessView(service: service) }
        }
        .background(ThingsColor.backgroundContent)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            service.refreshStatus()
        }
    }

    private var content: some View {
        _ = service.revision
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let events = service.events(from: day, to: next, hiddenCalendarIDs: hiddenIDs)

        return VStack(spacing: 0) {
            HStack {
                Text(calendar.isDateInToday(day) ? "Vandaag" : DutchDate.weekdayAndDay(day))
                    .thingsFont(.listTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                Spacer()
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                Button("Vandaag") { offset = 0 }.thingsFont(.metadata)
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, ThingsMetrics.contentPadding)
            .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(service.calendars) { cal in
                        let hidden = hiddenIDs.contains(cal.id)
                        Button {
                            var ids = hiddenIDs
                            if hidden { ids.remove(cal.id) } else { ids.insert(cal.id) }
                            hiddenRaw = ids.sorted().joined(separator: ",")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hidden ? "circle" : "checkmark.circle.fill").foregroundStyle(cal.color)
                                Text(cal.title).thingsFont(.metadata)
                                    .foregroundStyle(hidden ? ThingsColor.textTertiary : ThingsColor.textSecondary)
                            }
                            .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ThingsMetrics.contentPadding)
            }

            if events.isEmpty {
                ThingsEmptyStateSymbol(symbol: "calendar")
            } else {
                List(events) { event in
                    Button {
                        if TimerService.addCalendarEvent(event, in: context) != nil {
                            appState.showToast("Afspraak toegevoegd aan Tijd schrijven")
                        } else {
                            appState.showToast("Deze afspraak staat al in Tijd schrijven")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(event.color).frame(width: 9, height: 9)
                            Text(event.isAllDay ? "Hele dag" : DutchDate.time(event.start))
                                .thingsFont(.metadata)
                                .foregroundStyle(ThingsColor.textSecondary)
                                .monospacedDigit()
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).thingsFont(.todoTitle).foregroundStyle(ThingsColor.textPrimary)
                                Text(event.calendarTitle).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: ThingsMetrics.rowHeight)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }
}
