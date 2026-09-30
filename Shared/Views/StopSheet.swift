import SwiftUI
import WerkbankCore

/// "Werkzaamheden omschrijven": verplichte stopsheet met eindtijdcontrole.
/// De timer staat bevroren zolang de sheet open is; annuleren laat de regel gepauzeerd.
struct StopSheet: View {
    let entry: TimeEntry
    let defaultEnd: Date

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var startText = ""
    @State private var endText = ""
    @State private var correctionText = ""
    @State private var confirmDelete = false
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

    private var firstStart: Date { entry.firstStart ?? lastStart }
    private var startIsCustomised: Bool { startText != DutchDate.time(firstStart) }

    /// Begintijd op de dag van de eerste start. Ongeldige invoer telt als "niet aangepast".
    private var parsedStart: Date? {
        guard let (h, m) = Self.parse(startText) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: firstStart)
    }

    private var startEvaluation: StartTimeEvaluation {
        StartTimeCorrection.evaluate(firstStart: firstStart, requestedStart: parsedStart ?? firstStart,
                                     end: evaluation.end,
                                     measuredSeconds: entry.accumulated - evaluation.subtractedSeconds)
    }

    private var isInvalidStartText: Bool { parsedStart == nil && !startText.isEmpty }
    private var showsStartRange: Bool { startEvaluation.isOutOfRange || isInvalidStartText }

    /// Werkelijk gewerkt: gemeten tijd na begin- en eindtijdcorrectie.
    private var worked: TimeInterval {
        max(0, entry.accumulated - evaluation.subtractedSeconds + startEvaluation.adjustmentSeconds)
    }
    /// Aftrek op de te factureren tijd (bijv. een kwartier dat niet telt); nooit meer dan gewerkt.
    private var correction: TimeInterval { min(Double(Int(correctionText) ?? 0) * 60, worked) }
    private var billed: Double {
        Billing.billedHours(seconds: max(0, worked - correction), unitMinutes: AppSettings.roundingMinutes)
    }

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
            correctionSection
            descriptionSection

            Text(summaryText)
                .thingsFont(.todoTitleOpen)
                .foregroundStyle(ThingsColor.textPrimary)
                .monospacedDigit()

            HStack {
                Button("Tijdregel verwijderen", role: .destructive) { confirmDelete = true }
                    .help("Verwijdert deze tijdregel zonder iets te bewaren")
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
            startText = DutchDate.time(firstStart)
            endText = DutchDate.time(defaultEnd)
            descriptionFocused = true
        }
        .confirmationDialog("Tijdregel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder tijdregel", role: .destructive) { discard() }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("De gemeten tijd van \"\(entry.title)\" wordt niet bewaard.")
        }
    }

    // MARK: Eindtijd

    private var endTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tijd controleren")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)

            HStack(spacing: 12) {
                timeField("Van", text: $startText, invalid: showsStartRange, onSubmit: {})
                timeField("Tot", text: $endText, invalid: showsRange, onSubmit: clampText)

                if startIsCustomised || endIsCustomised {
                    Button {
                        startText = DutchDate.time(firstStart)
                        endText = DutchDate.time(defaultEnd)
                    } label: {
                        Label("Terug naar standaard", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .thingsFont(.metadata)
                }
            }

            Text(infoText)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)

            if showsStartRange {
                Text("De begintijd moet vóór de eindtijd (\(DutchDate.time(evaluation.end))) liggen.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.error)
            }

            if showsRange {
                Text("De eindtijd moet tussen \(DutchDate.time(lastStart)) en \(DutchDate.time(defaultEnd)) liggen.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.error)
            }

            if startEvaluation.adjustmentSeconds != 0 {
                let minutes = Int((abs(startEvaluation.adjustmentSeconds) / 60).rounded())
                Text(startEvaluation.adjustmentSeconds > 0
                     ? "\(minutes) min erbij door de eerdere begintijd"
                     : "\(minutes) min eraf door de latere begintijd")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textPrimary)
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

    private func timeField(_ title: String, text: Binding<String>, invalid: Bool,
                           onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
            TextField("uu:mm", text: text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                        .strokeBorder(invalid ? ThingsColor.error : ThingsColor.separator, lineWidth: 1.5)
                )
                .onSubmit(onSubmit)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityLabel(title == "Van" ? "Begintijd" : "Eindtijd")
        }
    }

    // MARK: Correctie

    /// Tijd die wel gewerkt is maar niet gefactureerd wordt (bijv. een kwartier afgeleid): de gewerkte tijd
    /// blijft in de regel staan, alleen de te factureren tijd gaat omlaag.
    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Correctie")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)

            HStack(spacing: 8) {
                Text("Niet factureren")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                TextField("", text: $correctionText, prompt: Text("0"))
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                            .strokeBorder(ThingsColor.separator, lineWidth: 1.5)
                    )
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: correctionText) { _, new in
                        let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(3))
                        if digits != new { correctionText = digits }
                    }
                Text("min")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
            }

            Text("De gewerkte tijd blijft in de regel staan; alleen de te factureren tijd wordt lager.")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
        }
    }

    private var summaryText: String {
        var text = "Gewerkt \(Billing.formatHMS(worked))"
        if correction >= 60 { text += " · correctie −\(Int(correction / 60)) min" }
        return text + " · te factureren \(Billing.formatHours(billed)) u"
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
        let start = startEvaluation
        TimerService.finish(entry, description: workDescription, end: result.end,
                            subtracted: result.subtractedSeconds,
                            startAdjust: start.adjustmentSeconds,
                            newFirstStart: start.adjustmentSeconds != 0 ? start.start : nil,
                            correction: correction, in: context)
        appState.stopContext = nil
        appState.showToast("Tijd vastgelegd, klaar om te factureren")
    }

    private func discard() {
        TimerService.discard(entry, in: context)
        appState.stopContext = nil
        appState.showToast("Tijdregel verwijderd")
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
