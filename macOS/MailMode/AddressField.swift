import SwiftUI
import WerkbankCore

/// Een adresveld in het opstelvenster (Aan, Cc, Bcc) dat aanvult uit wie je mailde, Contacten en de klantenlijst; de
/// naam van een klant geeft de mensen van die klant. Pijltjes kiezen, Return of Tab neemt het gemarkeerde adres over,
/// Esc sluit de lijst.
struct AddressField<Field: Hashable>: View {
    @Binding var text: String
    let focus: FocusState<Field?>.Binding
    let field: Field

    @State private var highlighted = 0
    /// Net gekozen of met Esc weggeklikt: de lijst blijft dicht tot je verder typt.
    @State private var settled: String?
    @State private var prepared = false

    private var isFocused: Bool { focus.wrappedValue == field }

    private var matches: [AddressCandidate] {
        let token = AddressSuggestions.currentToken(in: text)
        guard isFocused, !token.isEmpty, token != settled else { return [] }
        let present = Set(MailAddress.parse(text).valid.map { $0.address.lowercased() }).subtracting([token.lowercased()])
        let found = AddressSuggestions.search(token, in: AddressBook.shared.candidates(), excluding: present)
        if found.count == 1, found[0].address == token.lowercased() { return [] }
        return found
    }

    var body: some View {
        let matches = self.matches
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $text)
                .focused(focus, equals: field)
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
                    settled = AddressSuggestions.currentToken(in: text)
                    return .handled
                }
                .onSubmit {
                    guard !matches.isEmpty else { return }
                    pick(matches[min(highlighted, matches.count - 1)])
                }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.address) { index, candidate in
                        row(candidate, isOn: index == min(highlighted, matches.count - 1))
                    }
                }
                .padding(4)
                .frame(maxWidth: 460, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ThingsColor.separator))
                .padding(.bottom, 4)
            }
        }
        .onChange(of: text) { _, new in
            if AddressSuggestions.currentToken(in: new) != settled { settled = nil }
            highlighted = 0
        }
        .onChange(of: isFocused) { _, focused in
            guard focused, !prepared else { return }
            prepared = true
            Task { await AddressBook.shared.prepare() }
        }
    }

    private func row(_ candidate: AddressCandidate, isOn: Bool) -> some View {
        Button { pick(candidate) } label: {
            HStack(spacing: 8) {
                if let name = candidate.name {
                    Text(name)
                        .font(.werk(size: 13, weight: .medium))
                        .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                }
                Text(candidate.address)
                    .font(.werk(size: 12.5))
                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : ThingsColor.textSecondary)
                Spacer(minLength: 6)
                if let client = candidate.client {
                    HStack(spacing: 4) {
                        ClientLogo(name: client, size: 12)
                        Text(client)
                    }
                    .font(.werk(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.textSecondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? ThingsColor.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ candidate: AddressCandidate) {
        text = AddressSuggestions.replacingCurrentToken(in: text, with: candidate.mailAddress)
        settled = ""
        highlighted = 0
    }
}
