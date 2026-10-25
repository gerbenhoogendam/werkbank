import Foundation
import Observation
import SwiftData
import SwiftUI
import WerkbankCore

// MARK: - Voorstel

/// Eén voorgestelde tijdregel; alles is aan te passen voordat hij erin gaat.
struct DayProposal: Identifiable, Equatable {
    let id = UUID()
    var isOn = true
    var client: String
    var caseTitle: String
    var performed: String
    var start: Date
    var minutes: Int
    var basis: String
    /// De afspraak waar de regel precies op slaat; voorkomt dat dezelfde afspraak later nog eens wordt toegevoegd.
    var eventID: String?
}

// MARK: - Wat Claude te zien krijgt

/// De dag in tekst: afspraken, verzonden mails, afgeronde taken en wat al in Tijd schrijven staat.
struct DayCloseInput {
    let day: Date
    let rounding: Int
    let prompt: String
    /// "A1", "A2", … → afspraak.
    let events: [String: AgendaEvent]

    @MainActor
    static func gather(day: Date, context: ModelContext) async -> DayCloseInput {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let rounding = max(1, AppSettings.roundingMinutes)

        let defaults = UserDefaults.standard
        let hidden = AppSettings.parseHidden(defaults.string(forKey: SettingsKey.hiddenCalendars))
            .union(AppSettings.parseHidden(defaults.string(forKey: SettingsKey.agendaHidden)))
        let entries = TimerService.allEntries(in: context)
        let booked = Set(entries.compactMap(\.externalID))
        let events = CalendarService.shared.events(from: start, to: end, hiddenCalendarIDs: hidden)
            .filter { !$0.isAllDay && !booked.contains($0.id) }
            .sorted { $0.start < $1.start }
        let today = entries
            .filter { ($0.firstStart ?? $0.createdAt) >= start && ($0.firstStart ?? $0.createdAt) < end }
            .sorted { ($0.firstStart ?? $0.createdAt) < ($1.firstStart ?? $1.createdAt) }
        let done = BoardService.allCards(in: context)
            .filter { ($0.completedAt ?? .distantPast) >= start && ($0.completedAt ?? .distantPast) < end }
        let gmail = GmailSession.shared
        var sent: [(account: String?, mail: GmailThreadMessage)] = []
        if gmail.state == .signedIn { sent = await gmail.sentMails(from: start, to: end) }
        let mapped = ((try? context.fetch(FetchDescriptor<ClientMapping>())) ?? []).map(\.client)
        let clients = Set(entries.map(\.client) + mapped).subtracting([TimerService.noClient]).sorted()

        let nl = Locale(identifier: "nl_NL")
        let time = DateFormatter()
        time.locale = nl
        time.dateFormat = "HH:mm"
        let date = DateFormatter()
        date.locale = nl
        date.dateFormat = "EEEE d MMMM yyyy"

        var lines = ["Datum: \(date.string(from: start))",
                     "Afronding: \(rounding) minuten",
                     "Mijn mailadressen: \(gmail.accounts.joined(separator: ", "))",
                     "", "=== AFSPRAKEN ==="]
        var refs: [String: AgendaEvent] = [:]
        for (index, event) in events.enumerated() {
            let ref = "A\(index + 1)"
            refs[ref] = event
            var line = "\(ref) | \(time.string(from: event.start))–\(time.string(from: event.end)) | \(event.title) | agenda: \(event.calendarTitle)"
            if let location = event.location, !location.isEmpty { line += " | locatie: \(location)" }
            if !event.attendees.isEmpty { line += " | deelnemers: \(event.attendees.prefix(6).joined(separator: ", "))" }
            lines.append(line)
        }
        if events.isEmpty { lines.append("(geen)") }

        lines += ["", "=== VERZONDEN MAILS ==="]
        for (index, item) in sent.enumerated() {
            let mail = item.mail
            var line = "M\(index + 1) | \(time.string(from: mail.date)) | aan: \(mail.to)"
            if !mail.cc.isEmpty { line += " | cc: \(mail.cc)" }
            line += " | onderwerp: \(mail.subject) | \(mail.snippet.prefix(300))"
            lines.append(line)
        }
        if sent.isEmpty { lines.append("(geen)") }

        lines += ["", "=== AFGERONDE TAKEN ==="]
        for card in done {
            lines.append("- \(card.title)" + (card.clientLabel.map { " (\($0))" } ?? ""))
        }
        if done.isEmpty { lines.append("(geen)") }

        lines += ["", "=== AL IN TIJD SCHRIJVEN ==="]
        for entry in today {
            let minutes = Int((entry.elapsed() / 60).rounded())
            var line = "- \(time.string(from: entry.firstStart ?? entry.createdAt)), \(minutes) min | \(entry.client) | \(entry.title)"
            if !entry.workDescription.isEmpty { line += " | uitgevoerd: \(entry.workDescription)" }
            if entry.status == .running || entry.status == .paused { line += " | loopt nog" }
            lines.append(line)
        }
        if today.isEmpty { lines.append("(geen)") }

        lines += ["", "=== BEKENDE KLANTNAMEN ===", clients.prefix(200).joined(separator: ", ")]
        return DayCloseInput(day: start, rounding: rounding, prompt: lines.joined(separator: "\n"), events: refs)
    }

    /// Zoals Claude het teruggeeft.
    struct Raw: Decodable {
        let client: String
        let caseTitle: String
        let performed: String
        let start: String
        let minutes: Int
        let basis: String
        let event: String

        private enum CodingKeys: String, CodingKey {
            case client, caseTitle = "case", performed, start, minutes, basis, event
        }
    }

    func proposal(from raw: Raw) -> DayProposal? {
        let event = events[raw.event.trimmingCharacters(in: .whitespaces)]
        let parts = raw.start.split(separator: ":").compactMap { Int($0) }
        let parsed = parts.count == 2
            ? Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
            : nil
        guard let start = parsed ?? event?.start, raw.minutes > 0 else { return nil }
        // Naar boven op de afronding, minimaal één eenheid.
        let minutes = max(rounding, Int((Double(raw.minutes) / Double(rounding)).rounded(.up)) * rounding)
        return DayProposal(client: raw.client, caseTitle: raw.caseTitle, performed: raw.performed, start: start,
                           minutes: minutes, basis: raw.basis, eventID: event?.id)
    }
}

// MARK: - Model

@MainActor
@Observable
final class DayCloseModel {
    enum Phase: Equatable { case loading, ready, failed(String) }

    private(set) var phase: Phase = .loading
    var proposals: [DayProposal] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func run(day: Date, context: ModelContext) {
        task?.cancel()
        proposals = []
        guard let key = ClaudeKeychain.read() else {
            phase = .failed("Er is nog geen API-sleutel ingesteld (Voorkeuren › Claude).")
            return
        }
        phase = .loading
        let model = ClaudeSettings.model
        let orgContext = ClaudeSettings.context
        task = Task { [weak self] in
            let input = await DayCloseInput.gather(day: day, context: context)
            guard !Task.isCancelled else { return }
            let prompt = input.prompt
            let rounding = input.rounding
            do {
                let result = try await ClaudeStreamer.run(
                    key: key,
                    makeBody: { useFallbacks in
                        ClaudeRequest.dayCloseBody(day: prompt, model: model, context: orgContext, rounding: rounding,
                                                   useFallbacks: useFallbacks)
                    },
                    onText: { _ in })
                guard let self, !Task.isCancelled else { return }
                if result.stopReason == "refusal" {
                    self.phase = .failed(result.finalText)
                    return
                }
                struct Answer: Decodable { let proposals: [DayCloseInput.Raw] }
                guard let data = result.text.data(using: .utf8),
                      let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
                    self.phase = .failed("Het antwoord van Claude was niet te lezen.")
                    return
                }
                self.proposals = answer.proposals.compactMap(input.proposal(from:)).sorted { $0.start < $1.start }
                self.phase = .ready
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel() }

    var chosen: [DayProposal] { proposals.filter { $0.isOn && $0.minutes > 0 } }

    /// Zet de aangevinkte voorstellen in Tijd schrijven als afgeronde regels. ⌘Z haalt ze er samen weer uit.
    func add(in context: ModelContext) -> Int {
        let booked = Set(TimerService.allEntries(in: context).compactMap(\.externalID))
        var snapshots: [TimeEntrySnapshot] = []
        for proposal in chosen where proposal.eventID.map({ !booked.contains($0) }) ?? true {
            let title = proposal.caseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = TimeEntry(title: title, client: TimerService.normalized(proposal.client),
                                  source: proposal.eventID == nil ? .support : .calendar)
            entry.accumulated = Double(proposal.minutes) * 60
            entry.firstStart = proposal.start
            entry.lastStart = proposal.start
            entry.finishedAt = proposal.start.addingTimeInterval(Double(proposal.minutes) * 60)
            entry.workDescription = proposal.performed.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.externalID = proposal.eventID
            entry.status = .finished
            context.insert(entry)
            snapshots.append(TimeEntrySnapshot(entry))
        }
        TimerService.save(context)
        guard !snapshots.isEmpty else { return 0 }
        UndoCenter.shared.record("Dagafsluiting", undo: {
            for snapshot in snapshots {
                if let entry = TimerService.entry(withID: snapshot.id, in: context) { context.delete(entry) }
            }
            TimerService.save(context)
        }, redo: {
            for snapshot in snapshots { snapshot.recreate(in: context) }
            TimerService.save(context)
        })
        return snapshots.count
    }
}

// MARK: - Vraag aan Claude

extension ClaudeRequest {
    private static let dayCloseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "proposals": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "client": ["type": "string"],
                        "case": ["type": "string"],
                        "performed": ["type": "string"],
                        "start": ["type": "string"],
                        "minutes": ["type": "integer"],
                        "basis": ["type": "string"],
                        "event": ["type": "string"],
                    ],
                    "required": ["client", "case", "performed", "start", "minutes", "basis", "event"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["proposals"],
        "additionalProperties": false,
    ]

    nonisolated static func dayCloseBody(day: String, model: ClaudeModel, context: String, rounding: Int,
                                         useFallbacks: Bool) -> Data {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16_000,
            "stream": true,
            "system": dayCloseSystemPrompt(context: context, rounding: rounding),
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": dayCloseSchema],
            ],
            "messages": [["role": "user", "content": [["type": "text", "text": day]]]],
        ]
        if useFallbacks { body["fallbacks"] = "default" }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    nonisolated static func dayCloseSystemPrompt(context: String, rounding: Int) -> String {
        """
        Je helpt een IT-specialist zijn werkdag af te sluiten. Je krijgt zijn afspraken, verzonden mails en afgeronde \
        taken van één dag, en wat al in Tijd schrijven staat. Stel tijdregels voor van klantwerk dat nog niet \
        geschreven is. Jij boekt niets: hij vinkt zelf aan wat klopt.

        Over de organisatie:
        \(context)

        Regels:
        - Niets dubbel: werk dat al in Tijd schrijven staat (zelfde klant en onderwerp, of overlappende tijd) stel je \
        niet opnieuw voor.
        - Afspraken: werk voor of bij een klant krijgt de duur van de afspraak. Titels die met "GH:" beginnen zijn \
        ingeplande taken; stel ze voor met die duur. Sla privé en intern werk zonder klant over (lunch, sport, \
        verjaardagen, eigen administratie, overleg zonder klant).
        - Verzonden mails: een inhoudelijk antwoord aan een klant kost meestal 5 tot 15 minuten, een uitgebreide \
        technische uitleg meer. Bundel mails over hetzelfde onderwerp aan dezelfde klant tot één regel. Korte \
        bevestigingen en bedankjes tellen niet. Mails aan collega's (hetzelfde domein als mijn mailadressen) alleen \
        als ze duidelijk over klantwerk gaan.
        - Afgeronde taken zonder tijdregel: alleen als er redelijkerwijs tijd in heeft gezeten; schat voorzichtig.
        - client: de klantnaam, bij voorkeur precies zoals in de bekende klantnamen; anders afgeleid van het maildomein \
        of de agenda.
        - case: kort, als een ticketonderwerp, hooguit zes woorden.
        - performed: één zin in de verleden tijd over wat er gedaan is.
        - start: begintijd als UU:MM; bij mail ongeveer de verzendtijd min de duur.
        - minutes: een veelvoud van \(rounding), minimaal \(rounding).
        - basis: de bron in een paar woorden, zoals "Afspraak 10:00–11:00" of "2 verzonden mails".
        - event: de code van de afspraak (A1, A2, …) als de regel precies één afspraak is, anders leeg.
        Liever een paar voorstellen die kloppen dan veel twijfelgevallen. Geen voorstellen is een goed antwoord als \
        alles al geschreven is. Schrijf in het Nederlands.
        """
    }
}

// MARK: - Venster

/// Dag afsluiten (⇧⌘E vanuit Tijd schrijven): Claude stelt tijdregels voor, jij past aan en vinkt af.
struct DayCloseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model = DayCloseModel()
    @State private var day = Date()

    private var dayKey: Date { Calendar.current.startOfDay(for: day) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            footer
        }
        .frame(width: 900, height: 580)
        .background(ThingsColor.backgroundContent)
        .task(id: dayKey) { model.run(day: dayKey, context: context) }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ClaudeSpark()
                .frame(width: 18, height: 18)
            Text("Dag afsluiten")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
            DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .fixedSize()
            Spacer()
            if model.phase == .loading {
                ProgressView().controlSize(.small)
            } else {
                Button { model.run(day: dayKey, context: context) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThingsColor.textSecondary)
                .help("Opnieuw")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .foregroundStyle(ThingsColor.deadline)
                    .multilineTextAlignment(.center)
                Button("Opnieuw") { model.run(day: dayKey, context: context) }
            }
            .padding(24)
        case .ready where model.proposals.isEmpty:
            ThingsEmptyStateSymbol(symbol: "checkmark.circle", text: "Geen voorstellen")
        case .ready:
            VStack(spacing: 0) {
                columnLabels
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($model.proposals) { $proposal in
                            row($proposal)
                            Rectangle().fill(ThingsColor.separator).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private enum Width {
        static let check: CGFloat = 22
        static let client: CGFloat = 150
        static let caseTitle: CGFloat = 190
        static let start: CGFloat = 64
        static let minutes: CGFloat = 52
    }

    private var columnLabels: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: Width.check, height: 1)
            label("Klant").frame(width: Width.client, alignment: .leading)
            label("Case").frame(width: Width.caseTitle, alignment: .leading)
            label("Uitgevoerd").frame(maxWidth: .infinity, alignment: .leading)
            label("Start").frame(width: Width.start, alignment: .leading)
            label("Min").frame(width: Width.minutes, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.werk(size: 12, weight: .semibold))
            .foregroundStyle(Color.fieldLabel)
    }

    private func row(_ proposal: Binding<DayProposal>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: proposal.isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Width.check)
            ClientField(text: proposal.client)
                .frame(width: Width.client)
            TextField("", text: proposal.caseTitle)
                .frame(width: Width.caseTitle)
            VStack(alignment: .leading, spacing: 4) {
                TextField("", text: proposal.performed, axis: .vertical)
                    .lineLimit(1...3)
                Text(proposal.wrappedValue.basis)
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DatePicker("", selection: proposal.start, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: Width.start)
            TextField("", value: proposal.minutes, format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: Width.minutes)
        }
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(proposal.wrappedValue.isOn ? 1 : 0.45)
    }

    private var footer: some View {
        let chosen = model.chosen
        let minutes = chosen.reduce(0) { $0 + $1.minutes }
        return HStack(spacing: 10) {
            if model.phase == .ready, !model.proposals.isEmpty {
                Text("\(chosen.count) regels · \(Billing.formatHM(Double(minutes) * 60)) u")
                    .thingsFont(.metadata)
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            Spacer()
            Button("Annuleer") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Toevoegen") {
                let count = model.add(in: context)
                if count > 0 { appState.announce(count == 1 ? "1 tijdregel toegevoegd" : "\(count) tijdregels toegevoegd") }
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.phase != .ready || chosen.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}
