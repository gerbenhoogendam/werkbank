import SwiftData
import SwiftUI
import WerkbankCore

/// Hoe het blad "Nieuwe taak" opent: in welke kolom, en of het meteen gaat luisteren.
struct BoardNewTaskStart: Identifiable {
    let id = UUID()
    let column: BoardColumn
    let dictate: Bool
}

/// Nieuwe taak: inspreken (WhisperKit op het toestel, als inspreken aan staat in Voorkeuren) of typen, met `#klant`
/// voor het klantlabel; klant en kolom zijn daarna nog te kiezen.
struct BoardNewTaskSheet: View {
    let start: BoardNewTaskStart
    let columns: [BoardColumn]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var text = ""
    @State private var client = ""
    @State private var columnID: String
    @State private var recordingSince: Date?
    @State private var transcribing = false
    @State private var levels: [Double] = []
    @State private var failure: String?
    @FocusState private var textFocused: Bool

    private var dictation: PhoneDictation { PhoneDictation.shared }
    private var canDictate: Bool { PhoneDictation.isEnabled }

    init(start: BoardNewTaskStart, columns: [BoardColumn]) {
        self.start = start
        self.columns = columns
        _columnID = State(initialValue: start.column.id)
    }

    private var parsed: QuickEntry { QuickEntryParser.parse(text) }

    /// Het klantveld gaat voor een `#klant` in de tekst.
    private var label: String? {
        let typed = client.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return parsed.label
    }

    private var selectedColumn: BoardColumn {
        columns.first { $0.id == columnID } ?? start.column
    }

    private var canCreate: Bool { !parsed.title.isEmpty && !transcribing }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("NIEUWE TAAK")
                            .font(Ph.poster(32))
                            .foregroundStyle(Ph.ink)
                        Spacer(minLength: 8)
                        status
                    }
                    if dictation.isRecording { levelWell }
                    textField
                    fieldsGrid
                    columnChips
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
        .presentationDetents([.large])
        .presentationBackground(Ph.paper)
        .tint(Ph.ink)
        .task {
            if start.dictate && canDictate {
                await startRecording()
            } else {
                textFocused = true
            }
        }
        .onChange(of: dictation.level) { _, value in
            guard dictation.isRecording else { return }
            levels.append(value)
            if levels.count > 46 { levels.removeFirst(levels.count - 46) }
        }
        .onDisappear {
            if dictation.isRecording { _ = dictation.stopRecording() }
        }
    }

    // MARK: Status en geluid

    @ViewBuilder private var status: some View {
        if let since = recordingSince {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                pill(dot: Ph.urgent, text: "Luistert \(Billing.formatHM(timeline.date.timeIntervalSince(since) * 60))")
            }
        } else if transcribing {
            pill(dot: Ph.lime, text: "Omzetten")
        }
    }

    /// "LUISTERT 0:06": inkt met een stip ervoor (minuten:seconden).
    private func pill(dot: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text.uppercased())
                .font(Ph.text(10.5, .semibold))
                .tracking(1.4)
                .monospacedDigit()
                .foregroundStyle(Ph.paper)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Ph.ink)
    }

    /// Het geluid van de laatste seconden als staafjes in een putje.
    private var levelWell: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, value in
                Rectangle()
                    .fill(index >= levels.count - 6 ? Ph.olive : Ph.ink)
                    .frame(width: 3, height: max(4, CGFloat(value) * 52))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)
        .phWell()
        .accessibilityHidden(true)
    }

    // MARK: Velden

    private var textField: some View {
        TextField("Wat moet er gebeuren? #klant", text: $text, axis: .vertical)
            .font(Ph.text(17))
            .foregroundStyle(Ph.ink)
            .lineLimit(3...8)
            .focused($textFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 96, alignment: .topLeading)
            .phCard()
    }

    private var fieldsGrid: some View {
        VStack(spacing: 6) {
            fieldBox("Titel") {
                Text(parsed.title.isEmpty ? "–" : parsed.title)
                    .font(Ph.text(15, .semibold))
                    .foregroundStyle(parsed.title.isEmpty ? Ph.ink3 : Ph.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            fieldBox("Klant") {
                TextField(parsed.label ?? "Geen klant", text: $client)
                    .font(Ph.text(15, .semibold))
                    .foregroundStyle(Ph.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
    }

    private func fieldBox<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PhCaps(text: label, size: 9.5, color: Ph.olive)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .phCard(border: Ph.ink)
    }

    private var columnChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: "Kolom", size: 11)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(columns) { column in
                        PhChip(title: column.title, isOn: column.id == columnID) {
                            withAnimation(.easeOut(duration: 0.15)) { columnID = column.id }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Knoppen

    private var buttons: some View {
        HStack(spacing: 8) {
            if canDictate { micButton }
            Button("ANNULEER") { dismiss() }
                .buttonStyle(PhSecondaryStyle(height: 52))
                .frame(width: 120)
            Button("MAAK TAAK", action: create)
                .buttonStyle(PhPrimaryStyle())
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }

    /// Inkt met limoen terwijl hij luistert (ingedrukt), anders wit.
    private var micButton: some View {
        let on = dictation.isRecording
        return Button {
            Task {
                if on { await stopRecording() } else { await startRecording() }
            }
        } label: {
            Image(systemName: on ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? Ph.lime : Ph.ink)
                .frame(width: 52, height: 52)
                .background {
                    if on {
                        Rectangle().fill(Ph.ink.shadow(.inner(color: .black.opacity(0.4), radius: 1.5, y: 2)))
                    } else {
                        Rectangle().fill(Ph.card).shadow(color: Ph.ink.opacity(0.08), radius: 0, y: 1)
                    }
                }
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(transcribing)
        .accessibilityLabel(on ? "Stop met inspreken" : "Inspreken")
    }

    // MARK: Inspreken

    private func startRecording() async {
        failure = nil
        textFocused = false
        if let message = await dictation.startRecording() {
            failure = message
            return
        }
        levels = []
        recordingSince = .now
    }

    /// Opname stoppen en omzetten; de tekst komt achter wat er al stond.
    private func stopRecording() async {
        let samples = dictation.stopRecording()
        recordingSince = nil
        levels = []
        transcribing = true
        let hint = WhisperModel.knownClients().prefix(20).joined(separator: ", ")
        let spoken = await dictation.transcribe(samples, hint: hint.isEmpty ? nil : hint)
        transcribing = false
        guard let spoken, !spoken.isEmpty else {
            failure = "Niets verstaan"
            return
        }
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = current.isEmpty ? spoken : "\(current) \(spoken)"
    }

    // MARK: Maken

    private func create() {
        let title = parsed.title
        guard !title.isEmpty else { return }
        if dictation.isRecording { _ = dictation.stopRecording() }
        let column = selectedColumn
        BoardService.addCard(title: title, column: column, label: label, in: context)
        appState.showToast("Toegevoegd aan \(column.title)")
        dismiss()
    }
}
