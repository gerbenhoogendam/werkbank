import SwiftData
import SwiftUI

/// Snelle support-invoer: klant, omschrijving, duur. Wordt gebruikt in de menubalk (macOS),
/// het "+"-popover van Tijd schrijven en het invoerblad op iOS.
struct SupportEntryView: View {
    var onFinished: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TimeEntry.createdAt, order: .reverse) private var entries: [TimeEntry]

    @State private var client = ""
    @State private var workDescription = ""
    @State private var customMinutes = ""
    @State private var quickMinutes = 15
    @State private var showError = false
    @FocusState private var clientFocused: Bool

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
                label("Klant (optioneel)")
                TextField("Geen klant", text: $client)
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
                label("Omschrijving")
                TextField("Wat doe je?", text: $workDescription)
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(showError ? ThingsColor.error : .clear, lineWidth: 1.5)
                    )
                if showError {
                    Text("Vul een omschrijving in.")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.error)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                label("Duur")
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        TextField("min", text: $customMinutes)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 34)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("min").thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(chipBackground(selected: usesCustom))

                    ForEach(Self.quickChoices, id: \.self) { value in
                        Button("\(value)m") { customMinutes = ""; quickMinutes = value }
                            .buttonStyle(.plain)
                            .thingsFont(.tag)
                            .foregroundStyle(!usesCustom && quickMinutes == value ? Color.white : ThingsColor.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(chipBackground(selected: !usesCustom && quickMinutes == value, filled: true))
                    }
                }
            }

            HStack {
                Button("Start timer") { submit(startTimer: true) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Log \(minutes) min") { submit(startTimer: false) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(2)
        .onChange(of: customMinutes) { _, new in
            let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(3))
            if digits != new { customMinutes = digits }
        }
        .onChange(of: workDescription) { _, _ in
            if showError && TimerService.validDescription(workDescription) { showError = false }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
    }

    private func chipBackground(selected: Bool, filled: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius + 2, style: .continuous)
            .fill(selected ? (filled ? ThingsColor.accent : ThingsColor.selection) : ThingsColor.tagBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius + 2, style: .continuous)
                    .strokeBorder(selected && !filled ? ThingsColor.accent : .clear, lineWidth: 1.5)
            )
    }

    private func submit(startTimer: Bool) {
        guard TimerService.validDescription(workDescription) else {
            showError = true
            return
        }
        let text = workDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if startTimer {
            TimerService.startSupport(client: client, description: text, in: context)
            appState.showToast("Timer gestart: \(text)")
        } else {
            TimerService.logSupport(client: client, description: text, minutes: minutes, in: context)
            appState.showToast("\(minutes) min support gelogd")
        }
        client = ""
        workDescription = ""
        customMinutes = ""
        quickMinutes = 15
        showError = false
        onFinished()
    }
}
