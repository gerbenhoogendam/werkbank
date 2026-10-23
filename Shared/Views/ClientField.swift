import SwiftData
import SwiftUI
import WerkbankCore

/// Klantveld met suggesties uit de klantenlijst (.csv in iCloud Drive/Werkbank) en eerdere tijdregels.
/// Pijltjes kiezen, Return of Tab neemt de gemarkeerde over, Esc sluit de lijst.
struct ClientField: View {
    @Binding var text: String
    var autofocus = false

    @Query(sort: \TimeEntry.createdAt, order: .reverse) private var entries: [TimeEntry]
    @FocusState private var focused: Bool
    @State private var highlighted = 0
    /// Net gekozen (of met Esc weggeklikt): de lijst blijft dicht tot je weer typt.
    @State private var settled: String?
    private let directory = ClientDirectory.shared

    private var known: [String] {
        var seen = Set<String>()
        return entries.map(\.client).filter { $0 != TimerService.noClient && seen.insert($0.lowercased()).inserted }
    }

    private var matches: [ClientRecord] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard focused, !query.isEmpty, query != settled else { return [] }
        let found = directory.suggestions(for: query, known: known)
        if found.count == 1, found[0].name.caseInsensitiveCompare(query) == .orderedSame { return [] }
        return found
    }

    var body: some View {
        let matches = self.matches
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onKeyPress(.downArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    highlighted = min(highlighted + 1, matches.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard !matches.isEmpty else { return .ignored }
                    pick(matches[min(highlighted, matches.count - 1)])
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !matches.isEmpty else { return .ignored }
                    settled = text.trimmingCharacters(in: .whitespaces)
                    return .handled
                }
                .onSubmit {
                    guard !matches.isEmpty else { return }
                    pick(matches[min(highlighted, matches.count - 1)])
                }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { index, record in
                        row(record, isOn: index == min(highlighted, matches.count - 1))
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ThingsColor.separator))
            }
        }
        .onChange(of: text) { _, new in
            if new.trimmingCharacters(in: .whitespaces) != settled { settled = nil }
            highlighted = 0
        }
        .task {
            await directory.refresh()
            guard autofocus else { return }
            try? await Task.sleep(for: .milliseconds(80))   // het paneel wordt net key
            focused = true
        }
    }

    private func row(_ record: ClientRecord, isOn: Bool) -> some View {
        Button { pick(record) } label: {
            HStack(spacing: 8) {
                Text(record.name)
                    .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                if !record.details.isEmpty {
                    Text(record.details.joined(separator: " · "))
                        .foregroundStyle(isOn ? Color.white.opacity(0.75) : ThingsColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? ThingsColor.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ record: ClientRecord) {
        text = record.name
        settled = record.name
        highlighted = 0
    }
}
