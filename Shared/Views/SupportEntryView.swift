import SwiftData
import SwiftUI

/// Snelle support-invoer: klant, case, uitgevoerd en duur (zoals de regel in het boekhoudpakket komt). Wordt gebruikt in de menubalk (macOS),
/// het "+"-popover van Tijd schrijven en het invoerblad op iOS.
struct SupportEntryView: View {
    /// Snelle invoer (⌥⌘T): meteen in het klantveld beginnen.
    var autofocusClient = false
    var onFinished: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TimeEntry.createdAt, order: .reverse) private var entries: [TimeEntry]

    @State private var client = ""
    @State private var caseTitle = ""
    @State private var performed = ""
    @State private var customMinutes = ""
    @State private var quickMinutes = 15
    @State private var caseError = false
    @State private var performedError = false
    @FocusState private var clientFocused: Bool
    @FocusState private var minutesFocused: Bool

    private static let quickChoices = [10, 15, 30, 60]

    /// Eigen invoer heeft voorrang op de snelkeuzes.
    private var minutes: Int {
        if let custom = Int(customMinutes), custom > 0 { return custom }
        return quickMinutes
    }
    private var usesCustom: Bool { (Int(customMinutes) ?? 0) > 0 }

    private var suggestions: [String] {
        var seen = Set<String>()
        let typed = client.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.map(\.client)
            .filter { $0 != TimerService.noClient && seen.insert($0).inserted }
            .filter { typed.isEmpty || ($0.lowercased().contains(typed) && $0.lowercased() != typed) }
            .prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                label("Klant")
                TextField("", text: $client)
                    .textFieldStyle(.roundedBorder)
                    .focused($clientFocused)
                if !suggestions.isEmpty && (clientFocused || !client.isEmpty) {
                    HStack(spacing: 4) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { client = name } label: { TagPill(name: name) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                label("Case")
                TextField("", text: $caseTitle)
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(caseError ? ThingsColor.error : .clear, lineWidth: 1.5)
                    )
                if caseError {
                    Text("Vul een case in.")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.error)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                label("Uitgevoerd")
                TextField("", text: $performed, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(performedError ? ThingsColor.error : .clear, lineWidth: 1.5)
                    )
                if performedError {
                    Text("Vul in wat er is uitgevoerd (minimaal 3 tekens).")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.error)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                label("Duur")
                // Past alles op één regel, dan zo; anders het eigen veld boven de snelkeuzes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        customMinutesField
                        quickChoiceChips
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        customMinutesField
                        HStack(spacing: 6) { quickChoiceChips }
                    }
                }
            }

            HStack {
                Button("Start timer") { submit(startTimer: true) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Log \(minutes) min") { submit(startTimer: false) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Loggen (⌘↩)")
            }
        }
        .padding(2)
        .task {
            guard autofocusClient else { return }
            try? await Task.sleep(for: .milliseconds(80))   // het paneel wordt net key
            clientFocused = true
        }
        .onChange(of: customMinutes) { _, new in
            let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(3))
            if digits != new { customMinutes = digits }
        }
        .onChange(of: caseTitle) { _, new in
            if caseError && !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { caseError = false }
        }
        .onChange(of: performed) { _, new in
            if performedError && TimerService.validDescription(new) { performedError = false }
        }
    }

    /// Eigen aantal minuten: alleen cijfers, max. 3. Krijgt een eigen focusmarkering in plaats van de systeemring.
    private var customMinutesField: some View {
        HStack(spacing: 4) {
            TextField("", text: $customMinutes)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 38)
                .monospacedDigit()
                .focused($minutesFocused)
                .focusEffectDisabled()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text("min")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(chipBackground(selected: usesCustom || minutesFocused))
        .fixedSize()
        .accessibilityLabel("Eigen aantal minuten")
    }

    @ViewBuilder private var quickChoiceChips: some View {
        ForEach(Self.quickChoices, id: \.self) { value in
            Button("\(value)m") { customMinutes = ""; quickMinutes = value }
                .buttonStyle(.plain)
                .thingsFont(.tag)
                .foregroundStyle(!usesCustom && quickMinutes == value ? Color.white : ThingsColor.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(chipBackground(selected: !usesCustom && quickMinutes == value, filled: true))
                .fixedSize()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.fieldLabel)
    }

    private func chipBackground(selected: Bool, filled: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius + 2, style: .continuous)
            .fill(selected ? (filled ? ThingsColor.accent : ThingsColor.selection) : ThingsColor.tagBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius + 2, style: .continuous)
                    .strokeBorder(selected && !filled ? ThingsColor.accent : .clear, lineWidth: 1.5)
            )
    }

    /// Case is altijd nodig. Uitgevoerd alleen bij direct loggen; bij een timer vul je het bij het stoppen aan.
    private func submit(startTimer: Bool) {
        let title = caseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = performed.trimmingCharacters(in: .whitespacesAndNewlines)
        caseError = title.isEmpty
        performedError = !startTimer && !TimerService.validDescription(done)
        guard !caseError, !performedError else { return }
        if startTimer {
            TimerService.startSupport(client: client, caseTitle: title, performed: done, in: context)
            appState.announce("Timer gestart: \(title)")
        } else {
            TimerService.logSupport(client: client, caseTitle: title, performed: done, minutes: minutes, in: context)
            appState.announce("\(minutes) min gelogd: \(title)")
        }
        client = ""
        caseTitle = ""
        performed = ""
        customMinutes = ""
        quickMinutes = 15
        caseError = false
        performedError = false
        onFinished()
    }
}

extension Color {
    /// Labels van invoervelden (Klant, Case, Uitgevoerd, …): helder blauw, goed leesbaar in licht en donker.
    static let fieldLabel = Color(red: 0x1A / 255, green: 0x8C / 255, blue: 0xFF / 255)
}
