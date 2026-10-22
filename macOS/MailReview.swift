import Foundation
import Observation
import WerkbankCore

/// Eén opmerking van Claude over een concept: een fout in de taal of een inhoudelijk punt, met een voorstel.
struct ReviewIssue: Identifiable, Decodable, Equatable {
    var id = UUID()
    /// "taal" of "inhoud".
    let kind: String
    /// Letterlijk stuk uit het concept (om te kunnen vervangen).
    let quote: String
    /// Voorgestelde tekst in plaats van `quote`; leeg als er geen directe vervanging is.
    let replacement: String
    let explanation: String

    private enum CodingKeys: String, CodingKey { case kind, quote, replacement, explanation }

    var isLanguage: Bool { kind == "taal" }
}

/// Controle van een concept vóór het versturen: taal (alleen echte fouten) en inhoud (als IT-specialist).
@MainActor
@Observable
final class MailReviewer {
    enum Phase: Equatable { case idle, running, done, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var issues: [ReviewIssue] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func run(draft: String, subject: String, original: MailContent?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let key = ClaudeKeychain.read() else {
            phase = .failed("Er is nog geen API-sleutel ingesteld (Voorkeuren › Claude).")
            return
        }
        task?.cancel()
        issues = []
        phase = .running
        let model = ClaudeSettings.model
        let context = ClaudeSettings.context
        task = Task { [weak self] in
            do {
                let result = try await ClaudeStreamer.run(
                    key: key,
                    makeBody: { useFallbacks in
                        ClaudeRequest.reviewBody(draft: text, subject: subject, original: original, model: model,
                                                 context: context, useFallbacks: useFallbacks)
                    },
                    onText: { _ in })
                guard let self, !Task.isCancelled else { return }
                if result.stopReason == "refusal" {
                    self.phase = .failed(result.finalText)
                    return
                }
                struct Answer: Decodable { let issues: [ReviewIssue] }
                guard let data = result.text.data(using: .utf8),
                      let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
                    self.phase = .failed("Het antwoord van Claude was niet te lezen.")
                    return
                }
                // Alleen wat echt in het concept staat (anders valt er niets te vervangen of aan te wijzen).
                self.issues = answer.issues.filter { ($0.quote.isEmpty == false && text.contains($0.quote)) || !$0.isLanguage }
                self.phase = .done
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss(_ issue: ReviewIssue) {
        issues.removeAll { $0.id == issue.id }
    }

    func reset() {
        task?.cancel()
        issues = []
        phase = .idle
    }
}

extension ClaudeRequest {
    private static let reviewSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "issues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["taal", "inhoud"]],
                        "quote": ["type": "string"],
                        "replacement": ["type": "string"],
                        "explanation": ["type": "string"],
                    ],
                    "required": ["kind", "quote", "replacement", "explanation"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["issues"],
        "additionalProperties": false,
    ]

    nonisolated static func reviewBody(draft: String, subject: String, original: MailContent?, model: ClaudeModel,
                                       context: String, useFallbacks: Bool) -> Data {
        var text = "Onderwerp: \(subject)\n\n=== MIJN CONCEPT ===\n\(draft)\n=== EINDE CONCEPT ==="
        if let original {
            let quoted = String(original.quotableText.prefix(20_000))
            text += "\n\nTer context, de mail waarop ik antwoord (niet beoordelen, alleen gebruiken om de inhoud te toetsen):\n=== MAIL ===\n\(original.headerText)\n\n\(quoted)\n=== EINDE MAIL ==="
        }
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16_000,
            "stream": true,
            "system": reviewSystemPrompt(context: context),
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": reviewSchema],
            ],
            "messages": [["role": "user", "content": [["type": "text", "text": text]]]],
        ]
        if useFallbacks { body["fallbacks"] = "default" }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    nonisolated static func reviewSystemPrompt(context: String) -> String {
        """
        Je controleert een e-mail die een IT-specialist op het punt staat te versturen. Je geeft alleen opmerkingen \
        die hij echt nodig heeft; geen opmerking is een goed resultaat.

        Over de organisatie:
        \(context)

        Twee soorten opmerkingen:

        1. taal — alleen echte fouten: spelling, tikfouten, d/t-fouten, ontbrekende of dubbele woorden, verkeerde \
        woorden, en interpunctie die de betekenis verandert of duidelijk fout is. \
        Zeg NIETS over toon, formeel of informeel schrijven, humor, grapjes, woordkeuze, zinsbouw die grammaticaal klopt, \
        lengte, aanhef of afsluiting, emoji's, of bewust informele schrijfwijzen en afkortingen (zoals "ff", "ok", "idd"). \
        De schrijfstijl verschilt per klant en is bewust; die laat je volledig met rust.

        2. inhoud — kijk als ervaren IT-specialist naar wat er vakinhoudelijk wordt beweerd of beloofd, met een \
        bullshitfilter: onjuiste of achterhaalde technische beweringen, verkeerde instellingen, menupaden, commando's \
        of productnamen, beloftes of tijdsinschattingen die niet waar te maken zijn, risico's die de klant moet weten \
        maar die ontbreken (dataverlies, beveiliging, downtime, kosten), en tegenstrijdigheden met de mail van de klant. \
        Alleen als je er zeker van bent; geen algemene tips, geen "je zou ook nog kunnen". Weet je iets niet zeker, \
        laat het weg.

        Per opmerking:
        - quote: het stuk uit het concept waar het om gaat, letterlijk en exact zoals het er staat (zodat het te vervangen is), \
        zo kort als mogelijk maar uniek.
        - replacement: de verbeterde tekst die op de plek van quote komt, in dezelfde stijl en toon als de schrijver. \
        Leeg als er geen directe vervanging is (bijvoorbeeld bij een ontbrekend risico).
        - explanation: één korte zin, in het Nederlands.
        Geen opmerkingen dubbel, en niets over de geciteerde mail zelf.
        """
    }
}
