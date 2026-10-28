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
    /// Zelf gekozen te factureren tijd ("0,75"); zolang `billedChosen` uit staat volgt hij de gewerkte tijd.
    @State private var billedText = ""
    @State private var billedChosen = false
    @FocusState private var billedFocused: Bool
    @State private var confirmDelete = false
    @State private var workDescription = ""
    @State private var caseTitle = ""
    @State private var clientName = ""
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
    /// Eén stap in de te factureren tijd: de afrondingseenheid (bijv. 0,25 u).
    private var unitHours: Double { Double(max(1, AppSettings.roundingMinutes)) / 60 }
    /// Automatisch: de gewerkte tijd, naar boven afgerond op de eenheid.
    private var autoBilled: Double {
        Billing.billedHours(seconds: worked, unitMinutes: AppSettings.roundingMinutes)
    }
    /// "0,75", "1", "1.5" → uren.
    private var typedBilled: Double? {
        Double(billedText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")).map { max(0, $0) }
    }
    private var billed: Double {
        guard billedChosen, let typed = typedBilled else { return autoBilled }
        return Billing.billedHours(seconds: typed * 3600, unitMinutes: AppSettings.roundingMinutes)
    }
    /// Verschil tussen gewerkt en te factureren; negatief als er meer gefactureerd wordt dan er gemeten is.
    private var correction: TimeInterval { billedChosen ? worked - billed * 3600 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Werkzaamheden omschrijven")
                    .thingsFont(.listTitle)
                    .foregroundStyle(ThingsColor.textPrimary)
            }

            bookingFields

            endTimeSection
            billingSection
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
        // Vaste breedte: anders groeit het blad met de langste regel van Uitgevoerd mee en springt de tekst bij elk
        // woord naar een andere plek.
        .frame(width: 480)
        #endif
        .background(ThingsColor.backgroundContent)
        .onAppear {
            startText = DutchDate.time(firstStart)
            endText = DutchDate.time(defaultEnd)
            caseTitle = entry.title
            // Al ingevuld bij het starten (snelle invoer): meenemen.
            if workDescription.isEmpty { workDescription = entry.workDescription }
            clientName = entry.client == TimerService.noClient ? "" : entry.client
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
                Text("De eindtijd moet na \(DutchDate.time(lastStart)) liggen.")
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
            } else if evaluation.subtractedSeconds < 0 {
                Text("\(Int((-evaluation.subtractedSeconds / 60).rounded())) min erbij door de latere eindtijd")
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

    // MARK: Te factureren

    /// De tijd die je schrijft, in stappen van de afrondingseenheid; standaard de gewerkte tijd naar boven afgerond.
    /// De gewerkte tijd blijft in de regel staan.
    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Te factureren")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)

            HStack(spacing: 8) {
                SmallIconButton(symbol: "minus", label: "Minder") { step(-1) }
                    .disabled(billed <= 0)
                TextField("", text: billedBinding)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                            .strokeBorder(billedChosen && typedBilled == nil ? ThingsColor.error : ThingsColor.separator,
                                          lineWidth: 1.5)
                    )
                    .focused($billedFocused)
                    .onSubmit(snapBilled)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Te factureren uren")
                SmallIconButton(symbol: "plus", label: "Meer") { step(1) }
                Text("u")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)

                if billedChosen && billed != autoBilled {
                    Button {
                        billedChosen = false
                    } label: {
                        Label("Terug naar \(Billing.formatHours(autoBilled))", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .thingsFont(.metadata)
                }
            }
        }
        .onChange(of: billedFocused) { _, focused in if !focused { snapBilled() } }
    }

    /// Het veld toont de automatische tijd tot je zelf iets kiest.
    private var billedBinding: Binding<String> {
        Binding(get: { billedChosen ? billedText : Billing.formatHours(autoBilled) },
                set: { billedText = $0; billedChosen = true })
    }

    /// Eén eenheid erbij of eraf.
    private func step(_ direction: Double) {
        let next = max(0, ((billed / unitHours).rounded() + direction) * unitHours)
        billedText = Billing.formatHours(next)
        billedChosen = true
    }

    /// Wat je typte, afgerond op de eenheid terug in het veld ("0,6" → "0,75").
    private func snapBilled() {
        guard billedChosen else { return }
        billedText = Billing.formatHours(billed)
    }

    private var summaryText: String {
        "Gewerkt \(Billing.formatHMS(worked)) · te factureren \(Billing.formatHours(billed)) u"
    }

    private var infoText: String {
        let first = DutchDate.time(entry.firstStart ?? lastStart)
        let last = DutchDate.time(lastStart)
        return "Eerste start \(first) · laatst gestart \(last) · daarna \(Billing.formatHM(evaluation.continuousSeconds)) onafgebroken"
    }

    // MARK: Klant en case

    /// Zoals de regel in het boekhoudpakket komt: klant, case (zeer kort) en wat er is uitgevoerd.
    private var bookingFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            bookingRow("Klant") {
                ClientField(text: $clientName)
            }
            bookingRow("Case") {
                TextField("", text: $caseTitle)
            }
        }
    }

    private func bookingRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.werk(size: 13, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
                .frame(width: 84, alignment: .leading)
            field()
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Omschrijving

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Uitgevoerd")
                .font(.werk(size: 13, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)

            TextEditor(text: $workDescription)
                .thingsFont(.notes)
                .scrollContentBackground(.hidden)
                // Geen schuifbalk die bij het typen verschijnt en verdwijnt (dan loopt de tekst steeds anders af).
                .scrollIndicators(.never)
                .focused($descriptionFocused)
                .frame(minHeight: 110)
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
                Text("Vul in wat er is uitgevoerd (minimaal 3 tekens).")
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
                            correction: correction, caseTitle: caseTitle, client: clientName, in: context)
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
