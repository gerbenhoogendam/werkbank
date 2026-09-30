import SwiftUI
import WerkbankCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Concept-afspraak tijdens het inplannen van een to-do.
struct ScheduleDraft: Equatable {
    enum Step { case end, confirm }

    var cardID: UUID
    var todoTitle: String
    /// Begin van de dag (kalenderdag van de afspraak).
    var day: Date
    var start: Date
    var end: Date
    var step: Step = .end
}

/// Stap 3 van het inplannen: prefix na "GH:", doelagenda en bevestigen.
/// Wordt op macOS in een zwevende popover naast de afspraak getoond en op iOS in een blad.
struct ScheduleConfirmView: View {
    let todoTitle: String
    let start: Date
    let end: Date
    var showsDateHeader = true
    let onCancel: () -> Void
    let onSchedule: (_ title: String, _ calendarID: String) -> Void

    @State private var choice: PrefixChoice
    @State private var calendarID: String

    private let service = CalendarService.shared

    init(todoTitle: String, start: Date, end: Date, showsDateHeader: Bool = true,
         onCancel: @escaping () -> Void,
         onSchedule: @escaping (_ title: String, _ calendarID: String) -> Void) {
        self.todoTitle = todoTitle
        self.start = start
        self.end = end
        self.showsDateHeader = showsDateHeader
        self.onCancel = onCancel
        self.onSchedule = onSchedule
        _choice = State(initialValue: Scheduling.defaultPrefix(forStart: start))
        _calendarID = State(initialValue: CalendarService.shared
            .defaultTargetCalendarID(hiddenCalendarIDs: AppSettings.hiddenCalendarIDs) ?? "")
    }

    private var title: String {
        Scheduling.eventTitle(choice: choice, start: start, todoTitle: todoTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDateHeader {
                Text("\(DutchDate.weekdayAndDay(start)) · \(DutchDate.range(start, end))")
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                caption("Titel")
                Text(title)
                    .thingsFont(.todoTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 5) {
                caption("Na \"GH:\"")
                HStack(spacing: 6) {
                    ForEach(PrefixChoice.allCases) { option in
                        let selected = option == choice
                        Button {
                            choice = option
                        } label: {
                            Text(Scheduling.prefixText(option, start: start))
                                .thingsFont(.tag)
                                .foregroundStyle(selected ? Color.white : ThingsColor.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius + 2, style: .continuous)
                                        .fill(selected ? ThingsColor.accent : ThingsColor.tagBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                caption("Agenda")
                if service.writableCalendars.isEmpty {
                    Text("Geen schrijfbare agenda beschikbaar.")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.error)
                } else {
                    Picker("Agenda", selection: $calendarID) {
                        ForEach(service.writableCalendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Annuleer", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Inplannen") { onSchedule(title, calendarID) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(calendarID.isEmpty)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
    }
}

/// Opent de privacy-instellingen voor agenda's.
@MainActor
enum SystemSettings {
    static func openCalendarPrivacy() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
