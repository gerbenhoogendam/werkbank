import SwiftUI
import WerkbankCore

/// Tijd schrijven op de iPhone. Eerst de keuze tussen inspreken en typen (de snelle acties op het beginscherm kiezen
/// al). Inspreken: klant, case en uitgevoerd na elkaar, met één tik door naar het volgende veld; daarna duur kiezen en
/// loggen. Typen: meteen het invulformulier.
struct TimeEntrySheet: View {
    var onClose: () -> Void

    private enum Step: Int {
        case client, caseTitle, performed, review

        var title: String {
            switch self {
            case .client:    return "Klant"
            case .caseTitle: return "Case"
            case .performed: return "Uitgevoerd"
            case .review:    return "Klaar"
            }
        }

        var dictated: DictatedField? {
            switch self {
            case .client:    return .client
            case .caseTitle: return .caseTitle
            case .performed: return .performed
            case .review:    return nil
            }
        }

        var next: Step { Step(rawValue: rawValue + 1) ?? .review }
    }

    @State private var choosing: Bool
    @State private var step: Step
    /// Inspreken gekozen, maar het spraakmodel wordt eerst gedownload; daarna begint de opname.
    @State private var waiting = false
    @State private var values: [Step: String] = [:]
    @State private var minutes: Int?
    /// Velden die ingesproken zijn (microfoon in Tijd schrijven).
    @State private var spoken: Set<DictatedField> = []
    /// Velden die nog worden omgezet.
    @State private var pending: Set<Step> = []
    @State private var error: String?
    @State private var names: [String] = []
    /// Veer en stroming van de inspreekanimatie; loopt door van veld naar veld.
    @State private var voiceMotion = VoiceMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dictation: PhoneDictation { PhoneDictation.shared }

    init(start: TimeEntryStart, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _choosing = State(initialValue: start == .choose)
        _step = State(initialValue: start == .keyboard ? .review : .client)
    }

    var body: some View {
        NavigationStack {
            Group {
                if choosing {
                    chooser
                } else if step == .review && pending.isEmpty {
                    form
                } else {
                    voiceSteps
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ThingsColor.backgroundContent)
            .navigationTitle("Tijd schrijven")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit", action: close) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .task { if !choosing { await begin() } }
        // Het model is binnen: nu opnemen.
        .onChange(of: dictation.phase) {
            guard waiting, WhisperModel.savedFolder() != nil else { return }
            waiting = false
            Task { await record() }
        }
        .onDisappear { _ = dictation.stopRecording() }
    }

    // MARK: Kiezen

    private var chooser: some View {
        HStack(spacing: 12) {
            choice("Inspreken", symbol: "mic.fill", filled: true) {
                choosing = false
                Task { await begin() }
            }
            choice("Typen", symbol: "keyboard", filled: false) {
                choosing = false
                step = .review
            }
        }
        .padding(20)
    }

    private func choice(_ title: String, symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.werk(size: 34, weight: .medium))
                Text(title)
                    .font(.werk(size: 17, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.white : ThingsColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(filled ? ThingsColor.accent : ThingsColor.tagBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: Inspreken

    private var voiceSteps: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                fieldCard(.client)
                fieldCard(.caseTitle)
                fieldCard(.performed)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let message = error ?? failure {
                Text(message)
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            Spacer(minLength: 16)

            if waiting {
                download
                    .frame(height: 44)
                    .padding(.bottom, 16)
            }

            HStack(spacing: 12) {
                Button(action: typeInstead) {
                    Image(systemName: "keyboard")
                        .font(.werk(size: 18, weight: .medium))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(ThingsColor.tagBackground))
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(step == .review)
                .accessibilityLabel("Typen")

                Button(action: next) {
                    Group {
                        if step == .review {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Text(step.next.title)
                                Image(systemName: step == .performed ? "checkmark" : "arrow.right")
                            }
                        }
                    }
                    .font(.werk(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(ThingsColor.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(step == .review || waiting)
                .opacity(waiting ? 0.4 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    /// Voortgang van de eerste download van het spraakmodel.
    @ViewBuilder private var download: some View {
        if case .downloading(let fraction) = dictation.phase {
            HStack(spacing: 10) {
                ProgressView(value: fraction)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
        } else {
            ProgressView()
        }
    }

    private var failure: String? {
        if case .failed(let message) = dictation.phase { return message }
        return nil
    }

    /// Een veld als ruim vlak. Waarin je nu inspreekt: de golfvorm in het veld en een gloeiende rand eromheen.
    private func fieldCard(_ field: Step) -> some View {
        let active = field == step
        let listening = active && dictation.isRecording
        let value = values[field] ?? ""
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let bodyHeight: CGFloat = field == .performed ? 76 : 32
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(field.title)
                    .font(.werk(size: 13, weight: .semibold))
                    .foregroundStyle(active ? Color.fieldLabel : ThingsColor.textSecondary)
                if !value.isEmpty, let dictated = field.dictated, spoken.contains(dictated) { DictatedMark() }
                Spacer(minLength: 0)
            }
            Group {
                if listening {
                    VoiceWave(level: dictation.level, motion: voiceMotion)
                        .frame(height: max(bodyHeight, 48))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                } else if pending.contains(field) {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if field == .client, !value.isEmpty { ClientLogo(name: value, size: 20) }
                        Text(value)
                            .font(.werk(size: 20, weight: .medium))
                            .foregroundStyle(ThingsColor.textPrimary)
                            .lineLimit(field == .performed ? 6 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .transition(ThingsMotion.materialize(reduceMotion: reduceMotion))
                }
            }
            .frame(minHeight: bodyHeight, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(ThingsColor.backgroundSidebar))
        .overlay {
            if listening {
                VoiceGlow(level: dictation.level, motion: voiceMotion, shape: shape)
                    .transition(.opacity)
            } else {
                shape.strokeBorder(active ? ThingsColor.accent.opacity(0.6) : ThingsColor.separator,
                                   lineWidth: active ? 1.5 : 1)
            }
        }
        .animation(ThingsMotion.enter, value: listening)
        .contentShape(shape)
        // Op een veld tikken: zelf typen.
        .onTapGesture(perform: typeInstead)
    }

    // MARK: Invullen

    /// Het formulier van de snelle invoer, met wat er is ingesproken al ingevuld.
    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let error {
                    Text(error)
                        .font(.werk(size: 13))
                        .foregroundStyle(ThingsColor.error)
                }
                SupportEntryView(autofocusClient: entry == nil, dictation: entry, spokenFields: spoken,
                                 onFinished: onClose)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var entry: DictatedTimeEntry? {
        let entry = DictatedTimeEntry(client: values[.client] ?? "", caseTitle: values[.caseTitle] ?? "",
                                      performed: values[.performed] ?? "", minutes: minutes)
        return entry == DictatedTimeEntry() ? nil : entry
    }

    // MARK: Stappen

    /// Inspreken: zo nodig aanzetten (de eerste keer downloadt het model), dan opnemen.
    private func begin() async {
        guard step != .review else { return }
        names = WhisperModel.knownClients()
        if !PhoneDictation.isEnabled {
            dictation.apply(enabled: true)
        } else if case .failed = dictation.phase {
            dictation.retry()
        } else {
            dictation.prepare()
        }
        guard WhisperModel.savedFolder() != nil else {
            waiting = true
            return
        }
        await record()
    }

    private func record() async {
        guard step != .review, !dictation.isRecording else { return }
        if let message = await dictation.startRecording() {
            error = message
            step = .review
        }
    }

    /// Eén tik: wat er voor dit veld is ingesproken gaat naar Whisper, het volgende veld neemt meteen op.
    private func next() {
        let current = step
        guard current != .review else { return }
        transcribe(current == .performed ? dictation.stopRecording() : dictation.nextSegment(), for: current)
        step = current.next
    }

    /// Stoppen met inspreken en het formulier invullen (wat al gezegd is, wordt nog omgezet).
    private func typeInstead() {
        guard step != .review else { return }
        waiting = false
        transcribe(dictation.stopRecording(), for: step)
        step = .review
    }

    private func close() {
        _ = dictation.stopRecording()
        onClose()
    }

    private func transcribe(_ samples: [Float], for field: Step) {
        guard !samples.isEmpty else { return }
        pending.insert(field)
        // Klantnamen als hint, zodat Whisper ze goed schrijft.
        let hint = field == .client && !names.isEmpty ? names.prefix(25).joined(separator: ", ") + "." : nil
        Task {
            let text = await dictation.transcribe(samples, hint: hint)
            // De tekst komt uit een lichte waas in plaats van de draaier ineens te vervangen.
            withAnimation(ThingsMotion.reveal) {
                if let text { apply(text, to: field) }
                pending.remove(field)
            }
        }
    }

    private func apply(_ text: String, to field: Step) {
        switch field {
        case .client:
            values[.client] = WhisperModel.matchClient(DictationParser.field(text).text, known: names)
        case .caseTitle:
            values[.caseTitle] = DictationParser.field(text).text
        case .performed:
            // "…, kwartier" aan het eind is de duur.
            let parsed = DictationParser.field(text, withDuration: true)
            values[.performed] = parsed.text
            minutes = parsed.minutes
        case .review:
            return
        }
        if let dictated = field.dictated { spoken.insert(dictated) }
    }
}
