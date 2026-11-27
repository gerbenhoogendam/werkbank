import SwiftData
import SwiftUI
import WerkbankCore

/// "+ TIJD": eerst kiezen tussen inspreken (de bestaande tijdinvoer) en typen (het formulier hieronder).
struct TijdAddSheet: View {
    /// Inspreken gekozen: de lijst sluit dit blad en opent daarna de tijdinvoer met inspreken.
    let onVoice: () -> Void

    @State private var manual = false

    private var detents: Set<PresentationDetent> {
        manual ? [.large] : [.height(250)]
    }

    var body: some View {
        Group {
            if manual {
                TijdManualEntry()
            } else {
                chooser
            }
        }
        .presentationDetents(detents)
        .presentationBackground(Ph.paper)
        .presentationDragIndicator(manual ? .hidden : .visible)
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TIJD SCHRIJVEN")
                .font(Ph.poster(32))
                .foregroundStyle(Ph.ink)
            HStack(spacing: 8) {
                Button(action: onVoice) {
                    VStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                        Text("INSPREKEN")
                    }
                }
                .buttonStyle(PhPrimaryStyle(height: 120))
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { manual = true }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 24, weight: .medium))
                        Text("TYPEN")
                    }
                }
                .buttonStyle(PhSecondaryStyle(height: 120))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ph.paper.ignoresSafeArea())
    }
}

/// Tijd met de hand invoeren: klant (met suggesties), case, dag, begin en einde, de duur (afgerond zoals in de
/// voorkeuren) en wat er gedaan is. Bewaart een afgeronde regel.
struct TijdManualEntry: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var client = ""
    @State private var caseTitle = ""
    @State private var performed = ""
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var names: [String] = []
    @State private var failure: String?

    init() {
        let calendar = TijdDates.calendar
        let now = Date()
        // Einde nu (op vijf minuten), begin een half uur eerder.
        let minute = calendar.component(.minute, from: now)
        let rounded = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let finish = rounded.addingTimeInterval(-Double(minute % 5) * 60)
        _day = State(initialValue: calendar.startOfDay(for: now))
        _start = State(initialValue: finish.addingTimeInterval(-30 * 60))
        _end = State(initialValue: finish)
    }

    /// De laatste vijf werkdagen tot en met vandaag (vandaag ook als het weekend is).
    private var days: [Date] {
        let calendar = TijdDates.calendar
        let today = calendar.startOfDay(for: .now)
        var result: [Date] = []
        var day = today
        var guardCount = 0
        while result.count < 5 && guardCount < 14 {
            if !calendar.isDateInWeekend(day) || calendar.isDate(day, inSameDayAs: today) {
                result.insert(day, at: 0)
            }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            guardCount += 1
        }
        return result
    }

    private var suggestions: [String] {
        let typed = client.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return Array(names.prefix(6)) }
        let found = ClientDirectory.shared.suggestions(for: typed, known: names, limit: 6).map(\.name)
        return found.filter { $0.caseInsensitiveCompare(typed) != .orderedSame }
    }

    /// Dag uit de dagkeuze, uur en minuut uit de tijdvelden.
    private func combine(_ day: Date, _ time: Date) -> Date {
        let calendar = TijdDates.calendar
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private var measured: TimeInterval {
        max(0, combine(day, end).timeIntervalSince(combine(day, start)))
    }

    private var unit: Int { AppSettings.roundingMinutes }

    private var billedMinutes: Int {
        Billing.billedMinutes(seconds: measured, unitMinutes: unit)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("TIJD INVOEREN")
                            .font(Ph.poster(32))
                            .foregroundStyle(Ph.ink)
                        Spacer(minLength: 8)
                        PhCaps(text: "Handmatig", size: 11)
                    }
                    clientField
                    labeled("Case") {
                        TextField("Case", text: $caseTitle)
                            .font(Ph.text(15))
                            .foregroundStyle(Ph.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 46)
                            .phCard(border: Ph.ink)
                    }
                    labeled("Datum") { dayStrip }
                    times
                    durationRow
                    labeled("Omschrijving") {
                        TextField("Wat is er gedaan", text: $performed, axis: .vertical)
                            .font(Ph.text(15))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(1...5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(minHeight: 46)
                            .phCard()
                    }
                    if let failure {
                        Text(failure)
                            .font(Ph.text(13, .medium))
                            .foregroundStyle(Ph.danger)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            buttons
        }
        .background(Ph.paper.ignoresSafeArea())
        .environment(\.locale, Locale(identifier: "nl_NL"))
        .tint(Ph.ink)
        .onAppear {
            if names.isEmpty { names = WhisperModel.knownClients() }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: label, size: 11)
            content()
        }
    }

    // MARK: Klant

    private var clientField: some View {
        labeled("Klant") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Klant", text: $client)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .phCard(border: Ph.ink)
                let list = suggestions
                if !list.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(list, id: \.self) { name in
                                PhChip(title: name, isOn: name == client) {
                                    client = name
                                }
                            }
                        }
                        .padding(3)
                    }
                    .scrollIndicators(.never)
                    .phWell()
                }
            }
        }
    }

    // MARK: Dag en tijden

    private var dayStrip: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { date in
                let on = TijdDates.calendar.isDate(date, inSameDayAs: day)
                let today = TijdDates.calendar.isDateInToday(date)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { day = date }
                } label: {
                    VStack(spacing: 1) {
                        Text(today ? "VANDAAG" : DutchDate.weekdayShort(date).uppercased())
                            .font(Ph.text(9.5, .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Ph.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(TijdDates.calendar.component(.day, from: date))")
                            .font(Ph.poster(20))
                            .foregroundStyle(Ph.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if on {
                            Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                                .shadow(color: Ph.ink.opacity(0.18), radius: 0, y: 1)
                                .shadow(color: Ph.ink.opacity(0.12), radius: 2, y: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .phWell()
    }

    private var times: some View {
        HStack(spacing: 6) {
            timeWell("Begin", selection: $start)
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ph.ink2)
                .frame(width: 22)
                .accessibilityHidden(true)
            timeWell("Eind", selection: $end)
        }
    }

    private func timeWell(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PhCaps(text: label, size: 10)
            DatePicker(label, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .phWell()
    }

    /// Gemeten duur (doorgestreept als de afronding hem verandert) en de afgeronde duur in limoen.
    private var durationRow: some View {
        let billed = TimeInterval(billedMinutes * 60)
        let changed = Int(measured.rounded()) != billedMinutes * 60
        return HStack(spacing: 12) {
            PhCaps(text: "Duur", size: 11)
            if changed {
                Text(Billing.formatHM(measured))
                    .font(Ph.poster(24))
                    .foregroundStyle(Ph.ink3)
                    .strikethrough(true, color: Ph.ink)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ph.ink2)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            if unit > 1 {
                PhCaps(text: "Op \(unit) min", size: 10, color: Ph.olive)
            }
            Text(Billing.formatHM(billed))
                .font(Ph.poster(34))
                .foregroundStyle(Ph.ink)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Rectangle().fill(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1))))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 58)
        .phCard()
    }

    // MARK: Bewaren

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("ANNULEER") { dismiss() }
                .buttonStyle(PhSecondaryStyle(height: 52))
                .frame(width: 130)
            Button("BEWAAR \(Billing.formatHM(TimeInterval(billedMinutes * 60)))", action: save)
                .buttonStyle(PhPrimaryStyle())
                .disabled(measured <= 0)
                .opacity(measured > 0 ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    /// Een afgeronde regel van begin tot einde op de gekozen dag. De gemeten duur wordt bewaard; afronden gebeurt
    /// bij het factureren (zoals bij elke andere regel).
    private func save() {
        let begin = combine(day, start)
        let finish = combine(day, end)
        guard finish > begin else {
            failure = "Het einde moet na het begin liggen."
            return
        }
        let minutes = Int((finish.timeIntervalSince(begin) / 60).rounded())
        let entry = TimerService.logSupport(client: client,
                                            caseTitle: caseTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                            performed: performed.trimmingCharacters(in: .whitespacesAndNewlines),
                                            minutes: minutes, in: context, now: finish)
        // Op de gekozen dag in de lijst (de lijst haalt regels op aanmaakmoment op).
        entry.createdAt = begin
        TimerService.save(context)
        appState.showToast("Tijd bewaard: \(Billing.formatHM(TimeInterval(billedMinutes * 60)))")
        dismiss()
    }
}
