import Security
import SwiftUI
import WerkbankCore

/// Claude op de iPhone: een analyse van het gesprek met een conceptantwoord, en doorvragen. De sleutel staat in de
/// sleutelhanger van dit toestel; het model is dat van de Mac (via iCloud).
@MainActor
enum PhoneClaude {
    static let modelKey = "claude.model"
    static let keyAccount = "anthropic-api-key"
    static let keyService = "Werkbank.Claude.iPhone"

    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? "claude-sonnet-5-5" }

    static var apiKey: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService,
                                    kSecAttrAccount as String: keyAccount, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    static func setAPIKey(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService,
                                   kSecAttrAccount as String: keyAccount]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    struct Turn {
        let role: String
        let text: String
    }

    /// Eén vraag aan Claude; geeft de tekst van het antwoord terug.
    static func ask(system: String, turns: [Turn]) async throws -> String {
        guard let key = apiKey else { throw PhoneClaudeError.noKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": 1600, "system": system,
            "messages": turns.map { ["role": $0.role, "content": $0.text] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw PhoneClaudeError.failed
        }
        return content.compactMap { $0["text"] as? String }.joined()
    }
}

enum PhoneClaudeError: Error, LocalizedError {
    case noKey, failed

    var errorDescription: String? {
        switch self {
        case .noKey: "Geen sleutel voor Claude op deze iPhone (Voorkeuren › Claude)"
        case .failed: "Claude gaf geen antwoord"
        }
    }
}

/// De analyse van een gesprek: samenvatting, wat je moet doen, en een concept. Daarna doorvragen.
struct PhoneClaudeSheet: View {
    let mail: PhoneMail
    @Environment(\.dismiss) private var dismiss
    private let gmail = PhoneGmail.shared

    @State private var turns: [PhoneClaude.Turn] = []
    @State private var working = false
    @State private var error: String?
    @State private var question = ""
    @State private var compose: PhoneComposeRequest?
    @State private var source: GmailThreadMessage?
    @State private var sourceContent: MailContent?

    private static let system = """
    Je helpt bij het afhandelen van zakelijke mail. Antwoord in het Nederlands, kort en zakelijk. Geef bij een analyse \
    eerst een samenvatting in hooguit drie punten, dan wat er van de ontvanger verwacht wordt, en sluit af met een \
    conceptantwoord tussen de regels "CONCEPT:" en "EINDE". Geen begroeting van jezelf, geen uitleg over wat je doet.
    """

    private var draft: String? {
        guard let last = turns.last(where: { $0.role == "assistant" })?.text,
              let start = last.range(of: "CONCEPT:") else { return nil }
        let rest = last[start.upperBound...]
        let end = rest.range(of: "EINDE")?.lowerBound ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PhSpark(size: 20)
                Text("CLAUDE").font(Ph.poster(32)).foregroundStyle(Ph.ink)
                Spacer()
                PhCaps(text: PhoneClaude.model.replacingOccurrences(of: "claude-", with: ""), size: 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        if index > 0 {
                            if turn.role == "assistant" {
                                Text(turn.text).font(Ph.text(14.5)).foregroundStyle(Ph.ink)
                                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).phCard()
                            } else {
                                Text(turn.text).font(Ph.text(14, .semibold)).foregroundStyle(Ph.ink)
                                    .padding(12).frame(maxWidth: .infinity, alignment: .trailing)
                                    .phWell(Ph.band)
                            }
                        }
                    }
                    if working { ProgressView().tint(Ph.claude).frame(maxWidth: .infinity, minHeight: 60) }
                    if let error { Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger) }
                    if let draft {
                        Button("GEBRUIK CONCEPT") {
                            compose = PhoneComposeRequest(mode: .reply, account: mail.account, threadID: mail.item.threadID,
                                                          source: source, content: sourceContent, body: draft)
                        }
                        .buttonStyle(PhPrimaryStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            HStack(spacing: 8) {
                TextField("Vraag", text: $question)
                    .font(Ph.text(15))
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .phWell(Ph.card)
                    .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit { Task { await follow() } }
                Button { Task { await follow() } } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(PhIconButtonStyle(size: 46))
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    .accessibilityLabel("Verstuur vraag")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
        }
        .phScreen()
        .task { await analyze() }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request).presentationBackground(Ph.paper)
        }
    }

    private func analyze() async {
        guard turns.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            let messages = try await gmail.thread(mail.item.threadID, account: mail.account)
            var text = "Onderwerp: \(mail.item.subject)\n\n"
            for message in messages.suffix(8) {
                let content = try? await gmail.content(message.id, account: mail.account)
                if message.id == messages.last?.id {
                    source = message
                    sourceContent = content
                }
                text += "Van: \(message.from)\nDatum: \(message.date.formatted())\n"
                text += String((content?.quotableText ?? message.snippet).prefix(6000)) + "\n\n---\n\n"
            }
            turns = [PhoneClaude.Turn(role: "user", text: "Analyseer dit gesprek:\n\n" + text)]
            let answer = try await PhoneClaude.ask(system: Self.system, turns: turns)
            turns.append(PhoneClaude.Turn(role: "assistant", text: answer))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func follow() async {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !turns.isEmpty else { return }
        question = ""
        turns.append(PhoneClaude.Turn(role: "user", text: text))
        working = true
        defer { working = false }
        do {
            let answer = try await PhoneClaude.ask(system: Self.system, turns: turns)
            turns.append(PhoneClaude.Turn(role: "assistant", text: answer))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
