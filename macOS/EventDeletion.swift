import SwiftUI

/// Een afspraak verwijderen: met de rechtermuisknop, met Delete als de details open staan, of met de knop in de details.
/// Een losse afspraak gaat meteen weg (⌘Z zet hem terug); bij een herhalende afspraak komt de vraag "alleen deze of ook
/// de volgende", bij een afspraak met deelnemers eerst een bevestiging (de deelnemers komen met ⌘Z niet terug).
@MainActor
enum EventDeletion {
    enum Question { case none, span, confirm }

    static func question(for event: AgendaEvent) -> Question {
        if event.isRecurring { return .span }
        return event.attendees.isEmpty ? .none : .confirm
    }

    /// Alleen in een agenda die je mag wijzigen.
    static func canDelete(_ event: AgendaEvent) -> Bool {
        CalendarService.shared.calendars.contains { $0.id == event.calendarID && $0.allowsModifications }
    }

    /// Verwijdert de afspraak; `true` als het lukte. Staan de details van deze afspraak open, dan gaan die dicht.
    @discardableResult
    static func delete(_ event: AgendaEvent, thisAndFuture: Bool, appState: AppState) -> Bool {
        do {
            try CalendarService.shared.deleteEvent(event, thisAndFuture: thisAndFuture)
        } catch {
            appState.showToast("Verwijderen mislukt: \(error.localizedDescription)", seconds: 5)
            return false
        }
        if case .existing(let shown) = EventDetailStore.shared.presented?.target, shown.id == event.id {
            EventDetailStore.shared.close()
        }
        appState.showToast("Afspraak verwijderd")
        return true
    }

    /// Meteen weg, of eerst de vraag (via `pending` en `eventDeletionDialog`).
    static func request(_ event: AgendaEvent, pending: Binding<AgendaEvent?>, appState: AppState) {
        if question(for: event) == .none {
            delete(event, thisAndFuture: false, appState: appState)
        } else {
            pending.wrappedValue = event
        }
    }
}

/// De vraag bij het verwijderen van een herhalende afspraak of een afspraak met deelnemers.
private struct EventDeletionDialog: ViewModifier {
    @Binding var pending: AgendaEvent?
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                   titleVisibility: .visible, presenting: pending) { event in
            if event.isRecurring {
                Button("Alleen deze verwijderen", role: .destructive) {
                    EventDeletion.delete(event, thisAndFuture: false, appState: appState)
                }
                Button("Deze en alle volgende verwijderen", role: .destructive) {
                    EventDeletion.delete(event, thisAndFuture: true, appState: appState)
                }
            } else {
                Button("Verwijderen", role: .destructive) {
                    EventDeletion.delete(event, thisAndFuture: false, appState: appState)
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { event in
            Text(event.attendees.isEmpty ? event.title : "\(event.title) · \(event.attendees.count) deelnemers")
        }
    }

    private var title: String {
        guard let pending else { return "" }
        return pending.isRecurring ? "Deze afspraak herhaalt" : "Afspraak met deelnemers verwijderen?"
    }
}

extension View {
    /// Toont de vraag zodra `pending` een afspraak is (zie `EventDeletion.request`).
    func eventDeletionDialog(_ pending: Binding<AgendaEvent?>) -> some View {
        modifier(EventDeletionDialog(pending: pending))
    }
}
