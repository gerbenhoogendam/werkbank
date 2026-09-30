import SwiftUI

/// Uitleg en knop voor agenda-toegang (eerste keer) of doorverwijzing naar Systeeminstellingen (geweigerd).
struct CalendarAccessView: View {
    let service: CalendarService

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(ThingsColor.textTertiary.opacity(0.7))

            if service.isDenied || service.status == .writeOnly {
                Text("Werkbank heeft geen toegang tot je agenda's")
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("Sta toegang toe via Systeeminstellingen › Privacy en beveiliging › Agenda's.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Open Systeeminstellingen") { SystemSettings.openCalendarPrivacy() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Toon je agenda en plan to-do's in")
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("Werkbank toont je afspraken naast het board en maakt afspraken aan als je een kaart op de agenda sleept.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Toegang tot agenda's geven…") {
                    Task { await service.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
