import SwiftData
import SwiftUI
import WerkbankCore

/// De lopende timer over het hele scherm: grote cijfers in een vierkant spoor dat elk uur volloopt, klant en
/// omschrijving, pauze/hervat en stop. Stoppen sluit dit scherm en opent daarna de stopsheet.
struct TijdFocusView: View {
    let entry: TimeEntry
    /// Wat er vandaag in totaal op de klok staat (afgerond en lopend).
    let todayTotal: (Date) -> TimeInterval
    /// Stop gekozen: het scherm gaat dicht en de lijst opent de stopsheet.
    let onStop: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let running = entry.status == .running
        VStack(spacing: 0) {
            nav
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                dial(elapsed: entry.elapsed(at: timeline.date), running: running)
            }
            .padding(.top, 22)
            details
                .padding(.top, 18)
            Spacer(minLength: 12)
            buttons(running: running)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .phScreen()
        // Afgerond of verwijderd buiten dit scherm (bijv. op de Mac): dicht.
        .onChange(of: entry.status) { _, status in
            if status == .finished { dismiss() }
        }
    }

    // MARK: Kop

    private var nav: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(PhIconButtonStyle())
            .accessibilityLabel("Verklein")
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                PhEyebrow(text: eyebrow(at: timeline.date))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func eyebrow(at now: Date) -> String {
        let total = "VANDAAG \(Billing.formatHM(todayTotal(now)))"
        guard let start = entry.firstStart else { return total }
        return "SINDS \(DutchDate.time(start)) · \(total)"
    }

    // MARK: Spoor en cijfers

    /// Een vierkant putje met een limoen spoor dat elk uur rondloopt; in het midden de witte kaart met de tijd.
    private func dial(elapsed: TimeInterval, running: Bool) -> some View {
        let seconds = Int(max(0, elapsed))
        let inHour = seconds % 3600
        let fraction = CGFloat(inHour) / 3600
        let side: CGFloat = 318
        return ZStack {
            Rectangle()
                .fill(Ph.well.shadow(.inner(color: Ph.ink.opacity(0.18), radius: 3, y: 2)))
            Rectangle()
                .inset(by: 9)
                .trim(from: 0, to: max(0.002, fraction))
                .stroke(Ph.lime, style: StrokeStyle(lineWidth: 14, lineCap: .butt, lineJoin: .miter))
            Rectangle()
                .inset(by: 9)
                .trim(from: 0, to: max(0.002, fraction))
                .stroke(Ph.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(running ? Ph.late : Ph.ink3)
                        .frame(width: 8, height: 8)
                    PhCaps(text: running ? "Loopt" : "Pauze", size: 10.5, color: Ph.ink2)
                }
                Text(Billing.formatHMS(elapsed))
                    .font(Ph.poster(78))
                    .monospacedDigit()
                    .foregroundStyle(running ? Ph.ink : Ph.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, -8)
                    .accessibilityLabel(Billing.formatHMS(elapsed))
                PhCaps(text: "+\(Billing.formatHM(TimeInterval(inHour))) dit uur", size: 10.5, color: Ph.ink3)
            }
            .padding(.horizontal, 12)
            .frame(width: side - 64, height: side - 64)
            .phCard()
        }
        .frame(width: side, height: side)
    }

    // MARK: Klant en omschrijving

    private var details: some View {
        VStack(spacing: 8) {
            Text(entry.client.uppercased())
                .font(Ph.text(11.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(Ph.lime)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Ph.ink)
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(Ph.text(16, .medium))
                    .foregroundStyle(Ph.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if !entry.workDescription.isEmpty {
                Text(entry.workDescription)
                    .font(Ph.text(13))
                    .foregroundStyle(Ph.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Knoppen

    private func buttons(running: Bool) -> some View {
        HStack(spacing: 8) {
            Button(running ? "PAUZE" : "HERVAT") {
                if running {
                    TimerService.pause(entry, in: context)
                } else {
                    TimerService.start(entry, in: context)
                }
            }
            .buttonStyle(PhSecondaryStyle(height: 60))
            .frame(width: 140)
            Button {
                onStop()
            } label: {
                HStack(spacing: 10) {
                    Rectangle().fill(Ph.late).frame(width: 14, height: 14)
                    Text("STOP")
                }
            }
            .buttonStyle(PhInkStyle(height: 60))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}
