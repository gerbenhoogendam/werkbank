import SwiftData
import SwiftUI
import WerkbankCore

/// Een tijdregel aanpassen: klant, case, uitgevoerd, duur en geschreven; of verwijderen.
/// Het blad leest de regel alleen bij het openen (in `init`) en bij het bewaren.
struct TijdEntryEditor: View {
    let entry: TimeEntry
    /// Verwijderen gaat via de lijst: die sluit eerst het blad en verwijdert dan de regel.
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let isFinished: Bool
    private let originalMinutes: Int
    @State private var client: String
    @State private var caseTitle: String
    @State private var performed: String
    @State private var minutes: Int
    @State private var durationText: String
    @State private var written: Bool
    @State private var failure: String?
    @State private var confirmDelete = false
    @FocusState private var durationFocused: Bool

    init(entry: TimeEntry, onDelete: @escaping () -> Void) {
        self.entry = entry
        self.onDelete = onDelete
        let minutes = Int((entry.accumulated / 60).rounded())
        isFinished = entry.status == .finished
        originalMinutes = minutes
        _client = State(initialValue: entry.client == TimerService.noClient ? "" : entry.client)
        _caseTitle = State(initialValue: entry.title)
        _performed = State(initialValue: entry.workDescription)
        _minutes = State(initialValue: minutes)
        _durationText = State(initialValue: Self.format(minutes))
        _written = State(initialValue: entry.isWritten)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("TIJDREGEL")
                        .font(Ph.poster(36))
                        .foregroundStyle(Ph.ink)
                    fields
                    if isFinished { duration }
                    if isFinished {
                        Toggle(isOn: $written) {
                            PhCaps(text: "Geschreven", size: 11, color: Ph.ink)
                        }
                        .toggleStyle(PhToggleStyle())
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .phCard()
                    }
                    if let failure {
                        Text(failure)
                            .font(Ph.text(13, .medium))
                            .foregroundStyle(Ph.danger)
                    }
                    Button("VERWIJDER") { confirmDelete = true }
                        .buttonStyle(PhSecondaryStyle(tint: Ph.danger))
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            buttons
        }
        .background(Ph.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Ph.paper)
        .tint(Ph.ink)
        .confirmationDialog("Tijdregel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive, action: onDelete)
            Button("Annuleer", role: .cancel) {}
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            PhFieldRow(label: "Klant") {
                TextField("Klant", text: $client)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
                    .textInputAutocapitalization(.words)
            }
            PhFieldRow(label: "Case") {
                TextField("Case", text: $caseTitle)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
            }
            // Eigen regel (de naam past niet in de smalle kolom van PhFieldRow).
            VStack(alignment: .leading, spacing: 6) {
                PhCaps(text: "Uitgevoerd", size: 11)
                TextField("Uitgevoerd", text: $performed, axis: .vertical)
                    .font(Ph.text(15))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1...6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .phCard()
    }

    private var duration: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: "Duur")
            HStack(spacing: 8) {
                Button {
                    setMinutes(minutes - 15)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(PhIconButtonStyle(size: 52))
                .accessibilityLabel("Kwartier minder")
                TextField("0:00", text: $durationText)
                    .font(Ph.poster(34))
                    .foregroundStyle(Ph.ink)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($durationFocused)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .phWell(Ph.card)
                    .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
                    .onSubmit(readDuration)
                    .onChange(of: durationFocused) { _, focused in
                        if !focused { readDuration() }
                    }
                Button {
                    setMinutes(minutes + 15)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(PhIconButtonStyle(size: 52))
                .accessibilityLabel("Kwartier meer")
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("ANNULEER") { dismiss() }
                .buttonStyle(PhSecondaryStyle(height: 52))
                .frame(width: 130)
            Button("BEWAAR", action: save)
                .buttonStyle(PhPrimaryStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    // MARK: Duur

    private static func format(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "1:30" → 90, "1,5" → 90, "45" → 45 (minuten).
    static func parseMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0, (0..<60).contains(m) {
            return h * 60 + m
        }
        let decimal = trimmed.replacingOccurrences(of: ",", with: ".")
        if decimal.contains("."), let hours = Double(decimal), hours >= 0 {
            return Int((hours * 60).rounded())
        }
        if let value = Int(trimmed), value >= 0 { return value }
        return nil
    }

    private func setMinutes(_ value: Int) {
        minutes = min(max(0, value), 24 * 60)
        durationText = Self.format(minutes)
        failure = nil
    }

    private func readDuration() {
        if let parsed = Self.parseMinutes(durationText) {
            setMinutes(parsed)
        } else {
            failure = "Duur niet herkend: \(durationText)"
        }
    }

    // MARK: Bewaren

    private func save() {
        if isFinished {
            guard let parsed = Self.parseMinutes(durationText) else {
                failure = "Duur niet herkend: \(durationText)"
                return
            }
            minutes = parsed
        }
        let newClient = TimerService.normalized(client)
        if newClient != entry.client {
            entry.client = newClient
            entry.dictatedFields.remove(.client)
        }
        let newTitle = caseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty, newTitle != entry.title {
            entry.title = newTitle
            entry.dictatedFields.remove(.caseTitle)
        }
        let newPerformed = performed.trimmingCharacters(in: .whitespacesAndNewlines)
        if newPerformed != entry.workDescription {
            entry.workDescription = newPerformed
            entry.dictatedFields.remove(.performed)
        }
        if isFinished, minutes != originalMinutes {
            entry.accumulated = Double(minutes) * 60
            if let start = entry.firstStart { entry.finishedAt = start.addingTimeInterval(entry.accumulated) }
        }
        TimerService.save(context)
        if isFinished, written != entry.isWritten {
            TimerService.setWritten(entry, written, in: context)
        }
        dismiss()
    }
}
