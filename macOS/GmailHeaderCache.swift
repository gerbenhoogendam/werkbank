import Foundation
import WerkbankCore

/// De koppen van mails die al eens zijn opgehaald, per mailbox. Een lijst verversen kost zo één aanvraag voor de lijst
/// en één voor wat er in de mailbox veranderde, plus alleen de koppen van mails die nieuw zijn; eerder elke keer de
/// koppen van alle vijftig mails.
///
/// Een kop verandert niet, de labels van een mail wel (gelezen, inbox, map). Die werkt `sync` bij met de wijzigingen
/// die Gmail sinds de vorige keer meldt (`GmailHistory`). Kan Gmail die niet geven (te lang geleden, niet bereikbaar,
/// te veel tegelijk), dan vervalt wat hier staat en worden de koppen gewoon opnieuw opgehaald: liever een keer te
/// veel ophalen dan een lijst met oude labels.
///
/// Alleen in het geheugen: na opnieuw starten haalt elke lijst zijn koppen één keer volledig op.
@MainActor
final class GmailHeaderCache {
    typealias Fetch = @MainActor (_ path: String, _ query: [URLQueryItem]) async throws -> Data

    private static let limit = 1500
    private static let maxPages = 4

    private var items: [String: [String: GmailMailItem]] = [:]
    /// Per mailbox de volgorde van binnenkomst, oudste eerst (wat te veel is gaat er aan die kant af).
    private var order: [String: [String]] = [:]
    /// Per mailbox tot waar de labels zijn bijgewerkt. Zonder dit punt wordt er niets bewaard.
    private var historyID: [String: String] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var lastSync: [String: Date] = [:]
    /// Per mailbox hoe vaak de wijzigingen achter elkaar niet op te halen waren.
    private var failures: [String: Int] = [:]

    func item(_ id: String, account: String) -> GmailMailItem? { items[account]?[id] }

    /// Net opgehaalde koppen. Zonder beginpunt (`sync` lukte niet) worden ze niet bewaard: hun labels zouden daarna
    /// niet meer bij te werken zijn.
    func store(_ fetched: [GmailMailItem], account: String) {
        guard historyID[account] != nil, !fetched.isEmpty else { return }
        var known = items[account] ?? [:]
        var sequence = order[account] ?? []
        for item in fetched {
            if known[item.id] == nil { sequence.append(item.id) }
            known[item.id] = item
        }
        while sequence.count > Self.limit { known[sequence.removeFirst()] = nil }
        items[account] = known
        order[account] = sequence
    }

    /// De app heeft zelf de labels van een gesprek veranderd (gelezen, gearchiveerd): meteen bijwerken, zonder op de
    /// volgende ronde te wachten.
    func patch(threadID: String, adding: [String] = [], removing: [String] = []) {
        for account in Array(items.keys) {
            guard var known = items[account] else { continue }
            var changed = false
            for (id, item) in known where item.threadID == threadID {
                var labels = item.labels.filter { !removing.contains($0) }
                for label in adding where !labels.contains(label) { labels.append(label) }
                guard labels != item.labels else { continue }
                known[id]?.labels = labels
                changed = true
            }
            if changed { items[account] = known }
        }
    }

    func forget(account: String) {
        items[account] = nil
        order[account] = nil
        historyID[account] = nil
        lastSync[account] = nil
        failures[account] = nil
    }

    /// Werkt de labels van de bekende mails van een mailbox bij. Lijsten die tegelijk laden wachten op dezelfde ronde,
    /// en kort na een ronde komt er geen nieuwe.
    func sync(account: String, fetch: @escaping Fetch) async {
        if let task = running[account] {
            await task.value
            return
        }
        if let last = lastSync[account], Date().timeIntervalSince(last) < 3 { return }
        let task = Task { await self.run(account: account, fetch: fetch) }
        running[account] = task
        await task.value
        running[account] = nil
        lastSync[account] = Date()
    }

    private func run(account: String, fetch: Fetch) async {
        guard let start = historyID[account] else {
            await restart(account: account, fetch: fetch)
            return
        }
        var changes: [GmailHistory.Change] = []
        var latest: String?
        var pageToken: String?
        var pages = 0
        repeat {
            var query = [URLQueryItem(name: "startHistoryId", value: start),
                         URLQueryItem(name: "maxResults", value: "500")]
            query += GmailHistory.types.map { URLQueryItem(name: "historyTypes", value: $0) }
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GmailHistory.Page
            do {
                let data = try await fetch("history", query)
                guard let parsed = GmailHistory.page(fromJSON: data) else { throw GmailError.invalidResponse }
                page = parsed
            } catch {
                // 404: het beginpunt is verlopen (Gmail bewaart dit ongeveer een week), dus opnieuw beginnen. Iets
                // anders (geen verbinding, even te druk): deze ronde overslaan en pas opnieuw beginnen als het blijft
                // mislukken; meteen alles opnieuw ophalen maakt het dan alleen drukker.
                failures[account, default: 0] += 1
                var expired = false
                if let known = error as? GmailError, case .http(404, _) = known { expired = true }
                if expired || failures[account, default: 0] >= 3 { await restart(account: account, fetch: fetch) }
                return
            }
            changes += page.changes
            latest = page.historyID ?? latest
            pageToken = page.nextPageToken
            pages += 1
        } while pageToken != nil && pages < Self.maxPages
        guard pageToken == nil, let latest else {
            // Meer veranderd dan het loont om na te lopen.
            await restart(account: account, fetch: fetch)
            return
        }
        if var known = items[account] {
            GmailHistory.apply(changes, to: &known)
            items[account] = known
        }
        historyID[account] = latest
        failures[account] = 0
    }

    /// Opnieuw beginnen: niets bekend, en het punt van nu als begin. Dat punt ligt vóór de koppen die hierna worden
    /// opgehaald, dus een wijziging daartussen komt bij de volgende ronde alsnog langs.
    private func restart(account: String, fetch: Fetch) async {
        items[account] = nil
        order[account] = nil
        historyID[account] = nil
        failures[account] = 0
        guard let data = try? await fetch("profile", []) else { return }
        historyID[account] = GmailHistory.historyID(fromProfileJSON: data)
    }
}
