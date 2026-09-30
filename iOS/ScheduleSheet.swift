import SwiftUI
import WerkbankCore

/// Inplannen op iPhone/iPad: dezelfde regels als op de Mac (kwartieren, "GH: vdm/ndm/tijd …"),
/// maar met datumkiezers in plaats van slepen.
struct ScheduleSheet: View {
    let card: TodoCard
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var start = Scheduling.snapDown(.now)
    @State private var end = Scheduling.snapDown(.now).addingTimeInterval(3600)

    private var snappedStart: Date { Scheduling.snapDown(start) }
    private var snappedEnd: Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: end)
        // Eindtijd is alleen uu:mm; bouw hem op de dag van de start.
        let endOnDay = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: snappedStart) ?? end
        let minutes = Int(endOnDay.timeIntervalSince(snappedStart) / 60)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: snappedStart)) ?? endOnDay
        return Scheduling.clampEnd(start: snappedStart, proposedMinutesAfterStart: minutes, dayEnd: dayEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Einde", selection: $end, displayedComponents: [.hourAndMinute])
                } footer: {
                    Text("Tijden worden afgerond op 15 minuten: \(DutchDate.range(snappedStart, snappedEnd)).")
                }

                Section {
                    ScheduleConfirmView(todoTitle: card.title, start: snappedStart, end: snappedEnd,
                                        showsDateHeader: false,
                                        onCancel: { dismiss() },
                                        onSchedule: schedule)
                        // Nieuwe standaardprefix (vdm/ndm) als de start over 13:00 heen schuift.
                        .id(Scheduling.defaultPrefix(forStart: snappedStart))
                }
            }
            .navigationTitle("Inplannen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func schedule(title: String, calendarID: String) {
        do {
            try CalendarService.shared.createEvent(title: title, start: snappedStart, end: snappedEnd, calendarID: calendarID)
            appState.showToast("Ingepland: \(title)")
            dismiss()
        } catch {
            appState.showToast("Inplannen mislukt: \(error.localizedDescription)")
        }
    }
}
