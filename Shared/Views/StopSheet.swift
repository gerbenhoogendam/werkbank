import SwiftUI
import WerkbankCore

/// "Werkzaamheden omschrijven": verplichte stopsheet met eindtijdcontrole.
/// De timer staat bevroren zolang de sheet open is; annuleren laat de regel gepauzeerd.
struct StopSheet: View {
    let entry: TimeEntry
    let defaultEnd: Date

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var endText = ""
    @State private var workDescription = ""
    @State private var descriptionError = false
    @State private var shakes: CGFloat = 0
    @FocusState private var descriptionFocused: Bool

    private var lastStart: Date { entry.lastStart ?? entry.firstStart ?? defaultEnd }
    private var endIsCustomised: Bool { endText != DutchDate.time(defaultEnd) }

    /// Ingevoerde tijd → datum. Ongeldige invoer telt als "niet aangepast".
    private var parsedEnd: Date? {
        guard let (h, m) = Self.parse(endText) else { return nil }
        return EndTimeCorrection.date(hour: h, minute: m, near: defaultEnd, notBefore: lastStart)
    }

    private var evaluation: EndTimeEvaluation {
        EndTimeCorrection.evaluate(lastStart: lastStart, defaultEnd: defaultEnd,
                                   requestedEnd: parsedEnd ?? defaultEnd,
                                   warningThresholdMinutes: AppSettings.longRunMinutes)
    }

    private var isInvalidText: Bool { parsedEnd == nil && !endText.isEmpty }
    private var showsRange: Bool { evaluation.isOutOfRange || isInvalidText }

    private var worked: TimeInterval { max(0, entry.accumulated - evaluation.subtractedSeconds) }
    private var billed: Double { Billing.billedHours(seconds: worked, unitMinutes: AppSettings.roundingMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Werkzaamheden omschrijven")
                    .thingsFont(.listTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("\(entry.title) · \(entry.client)")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }

            endTimeSection
            descriptionSection

            HStack {
                Text("Gewerkt \(Billing.formatHMS(worked)) · te factureren \(Billing.formatHours(billed)) u")
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .monospacedDigit()
                Spacer()
                Button("Annuleer") { appState.stopContext = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Bewaar") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 440)
        #endif
        .background(ThingsColor.backgroundContent)
        .onAppear {
            endText = DutchDate.time(defaultEnd)
            descriptionFocused = true
        }
    }

    // MARK: Eindtijd

    private var endTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Eindtijd controleren")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)

            HStack(spacing: 8) {
                TextField("uu:mm", text: $endText)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                            .strokeBorder(showsRange ? ThingsColor.error : ThingsColor.separator, lineWidth: 1.5)
                    )
                    .onSubmit(clampText)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .accessibilityLabel("Eindtijd")

                if endIsCustomised {
                    Button {
                        endText = DutchDate.time(defaultEnd)
                    } label: {
                        Label("Terug naar \(DutchDate.time(defaultEnd))", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .thingsFont(.metadata)
                }
            }

            Text(infoText)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)

            if showsRange {
                Text("De eindtijd moet tussen \(DutchDate.time(lastStart)) en \(DutchDate.time(defaultEnd)) liggen.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.error)
            }

            if evaluation.subtractedSeconds > 0 {
                Text("\(Int((evaluation.subtractedSeconds / 60).rounded())) min afgetrokken van de gemeten tijd")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textPrimary)
            }

            if evaluation.showsLongRunWarning {
                Label("De timer liep \(Billing.formatHM(evaluation.continuousSeconds)) u zonder pauze. Pas de eindtijd aan als je al met iets anders bezig was.",
                      systemImage: "exclamationmark.triangle.fill")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var infoText: String {
        let first = DutchDate.time(entry.firstStart ?? lastStart)
        let last = DutchDate.time(lastStart)
        return "Eerste start \(first) · laatst gestart \(last) · daarna \(Billing.formatHM(evaluation.continuousSeconds)) onafgebroken"
    }

    // MARK: Omschrijving

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Omschrijving")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)

            TextEditor(text: $workDescription)
                .thingsFont(.notes)
                .scrollContentBackground(.hidden)
                .focused($descriptionFocused)
                .frame(minHeight: 84)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                        .strokeBorder(descriptionError ? ThingsColor.error : ThingsColor.separator, lineWidth: 1.5)
                )
                .modifier(ShakeEffect(shakes: shakes))
                .onChange(of: workDescription) { _, _ in
                    if descriptionError && TimerService.validDescription(workDescription) { descriptionError = false }
                }

            if descriptionError {
                Text("Vul een omschrijving in (minimaal 3 tekens).")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.error)
            }
        }
    }

    // MARK: Acties

    private func clampText() {
        // Begrens de waarde en zet die terug in het veld.
        guard let requested = parsedEnd else { endText = DutchDate.time(defaultEnd); return }
        let evaluated = EndTimeCorrection.evaluate(lastStart: lastStart, defaultEnd: defaultEnd, requestedEnd: requested)
        endText = DutchDate.time(evaluated.end)
    }

    private func save() {
        guard TimerService.validDescription(workDescription) else {
            descriptionError = true
            withAnimation(.linear(duration: 0.4)) { shakes += 3 }
            descriptionFocused = true
            return
        }
        let result = evaluation
        TimerService.finish(entry, description: workDescription, end: result.end,
                            subtracted: result.subtractedSeconds, in: context)
        appState.stopContext = nil
        appState.showToast("Tijd vastgelegd, klaar om te factureren")
    }

    /// "10:15", "1015", "9.05" → (uur, minuut).
    static func parse(_ text: String) -> (Int, Int)? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let parts = t.split(whereSeparator: { $0 == ":" || $0 == "." })
        var hour: Int?
        var minute: Int?
        if parts.count == 2 {
            hour = Int(parts[0]); minute = Int(parts[1])
        } else if parts.count == 1, parts[0].count >= 3, parts[0].count <= 4, let n = Int(parts[0]) {
            hour = n / 100; minute = n % 100
        }
        guard let h = hour, let m = minute, (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}
