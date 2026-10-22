import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftData
import UniformTypeIdentifiers
import WerkbankCore

// MARK: - Fouten

enum GmailError: LocalizedError {
    case notConfigured
    case notSignedIn
    case signInCancelled
    case signInFailed(String)
    case sessionExpired
    case http(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Gmail is nog niet gekoppeld: GOOGLE_CLIENT_ID ontbreekt (zie README, \"Gmail koppelen\")."
        case .notSignedIn:
            return "Je bent niet ingelogd bij Gmail."
        case .signInCancelled:
            return "Inloggen is geannuleerd."
        case .signInFailed(let reason):
            return "Inloggen bij Google is mislukt: \(reason)"
        case .sessionExpired:
            return "Je Google-sessie is verlopen. Log opnieuw in."
        case let .http(status, message):
            return "Gmail antwoordde met fout \(status)" + (message.map { ": \($0)" } ?? ".")
        case .invalidResponse:
            return "Onverwacht antwoord van Google."
        }
    }
}

// MARK: - Sleeptype

extension UTType {
    /// Zie `UTExportedTypeDeclarations` in project.yml.
    static let gmailMessage = UTType(exportedAs: "nl.itgwerkbank.gmail-message")
}

// MARK: - Sleutelhanger

private enum Keychain {
    static let service = "Werkbank.Gmail"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Geeft het inlogvenster van Google een venster om aan te hangen.
private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Sessie

/// Inloggen bij Gmail (OAuth met PKCE), de inbox ophalen en mails archiveren.
/// De refresh-token staat in de sleutelhanger; er staat geen wachtwoord of client secret in de app.
@MainActor
@Observable
final class GmailSession {
    static let shared = GmailSession()

    enum State: Equatable { case signedOut, signingIn, signedIn }

    private(set) var state: State = .signedOut
    /// Gekoppelde mailboxen (e-mailadressen) en welke daarvan nu in het paneel staat.
    private(set) var accounts: [String] = []
    private(set) var activeAccount: String?
    var emailAddress: String? { activeAccount }
    /// Mailboxen die samen in één lijst staan (⌘-klik op de tabs, of ⌘0 voor alle). Minder dan twee: gewoon de actieve.
    private(set) var combinedAccounts: [String] = []
    var isCombined: Bool { combinedAccounts.count > 1 }
    var isAllCombined: Bool { isCombined && Set(combinedAccounts) == Set(accounts) }
    /// `true` terwijl het inlogvenster voor een (extra) account open staat.
    private(set) var isAddingAccount = false
    private(set) var messages: [GmailMessageSummary] = []
    private(set) var isLoading = false
    private(set) var busyMessageIDs: Set<String> = []
    private(set) var lastError: String?

    @ObservationIgnored private var bodyCache: [String: String] = [:]
    @ObservationIgnored private var rawCache: [String: Data] = [:]
    @ObservationIgnored private var rawCacheOrder: [String] = []
    private static let rawCacheLimit = 40
    /// Laatst opgehaalde inbox per mailbox, zodat schakelen direct iets toont.
    @ObservationIgnored private var messageCache: [String: [GmailMessageSummary]] = [:]
    @ObservationIgnored private var loadingKeys: Set<String> = []
    /// Access-token per mailbox (sleutel "" is de oude enkele token).
    @ObservationIgnored private var tokenCache: [String: (token: String, expiry: Date)] = [:]
    /// Bij welke mailbox een bericht of gesprek hoort, zodat acties de juiste token gebruiken (ook in de gecombineerde lijst).
    @ObservationIgnored private var messageAccount: [String: String] = [:]
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presenter = WebAuthPresenter()

    /// Vóór het schakelen tussen mailboxen stond hier één token; dat blijft werken tot het naar een adres is verhuisd.
    private static let legacyAccount = "refreshToken"
    private static let accountsKey = "gmail.accounts"
    private static let activeKey = "gmail.activeAccount"
    private static let combinedKey = "gmail.combined"          // oud: alles of niets
    private static let combinedAccountsKey = "gmail.combinedAccounts"
    private static let inboxPageSize = "40"

    private static func tokenAccount(_ email: String) -> String { "refreshToken:\(email)" }

    private init() {
        let defaults = UserDefaults.standard
        accounts = (defaults.stringArray(forKey: Self.accountsKey) ?? []).filter {
            Keychain.read(Self.tokenAccount($0)) != nil
        }
        let saved = defaults.string(forKey: Self.activeKey)
        activeAccount = saved.flatMap { accounts.contains($0) ? $0 : nil } ?? accounts.first
        let savedCombination = defaults.stringArray(forKey: Self.combinedAccountsKey)
            ?? (defaults.bool(forKey: Self.combinedKey) ? accounts : [])
        let combination = accounts.filter(savedCombination.contains)
        combinedAccounts = combination.count > 1 ? combination : []
        if hasAnyAccount { state = .signedIn }
    }

    private var hasAnyAccount: Bool { !accounts.isEmpty || Keychain.read(Self.legacyAccount) != nil }

    private func refreshToken(for account: String?) -> String? {
        if let account, !account.isEmpty { return Keychain.read(Self.tokenAccount(account)) }
        return Keychain.read(Self.legacyAccount)
    }

    /// De mailbox waar een bericht (of gesprek) bij hoort; zonder bekend adres de actieve.
    func account(for id: String) -> String? { messageAccount[id] ?? activeAccount }

    /// Onthoudt de mailbox van een bericht dat niet uit de lijst komt (bijvoorbeeld een mailpaneel).
    func note(account: String?, forMessageID id: String) {
        if let account { messageAccount[id] = account }
    }

    /// Korte naam voor een tabblad of label: het deel voor de @.
    static func shortName(_ email: String) -> String { email.split(separator: "@").first.map(String.init) ?? email }

    /// Eigen namen voor de tabs (leeg: het deel voor de @).
    private(set) var displayNames: [String: String] =
        UserDefaults.standard.dictionary(forKey: "gmail.displayNames") as? [String: String] ?? [:]

    func displayName(_ email: String) -> String {
        let name = displayNames[email]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? Self.shortName(email) : name
    }

    func rename(_ email: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayNames[email] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(displayNames, forKey: "gmail.displayNames")
    }

    /// Wat het paneel toont: de mailbox zelf, of alle mailboxen op datum.
    private func refreshVisible() {
        if isCombined {
            messages = combinedAccounts.flatMap { messageCache[$0] ?? [] }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } else {
            messages = messageCache[activeAccount ?? ""] ?? []
        }
    }

    private func removeThreadFromLists(_ threadID: String) {
        for key in Array(messageCache.keys) { messageCache[key]?.removeAll { $0.threadID == threadID } }
        refreshVisible()
    }

    private func persistAccounts() {
        let defaults = UserDefaults.standard
        defaults.set(accounts, forKey: Self.accountsKey)
        defaults.set(activeAccount, forKey: Self.activeKey)
        defaults.set(combinedAccounts, forKey: Self.combinedAccountsKey)
        defaults.removeObject(forKey: Self.combinedKey)
    }

    // MARK: Configuratie

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool { GoogleOAuth.redirectScheme(forClientID: Self.clientID) != nil }

    // MARK: Inloggen

    /// Voegt een mailbox toe (en maakt hem actief). Google vraagt altijd welk account je wilt gebruiken.
    func signIn() async {
        guard isConfigured, let redirectURI = GoogleOAuth.redirectURI(forClientID: Self.clientID),
              let scheme = GoogleOAuth.redirectScheme(forClientID: Self.clientID) else {
            lastError = GmailError.notConfigured.localizedDescription
            return
        }
        if !hasAnyAccount { state = .signingIn }
        isAddingAccount = true
        lastError = nil
        defer { isAddingAccount = false }
        do {
            let verifier = Self.randomToken()
            let challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
            let expectedState = Self.randomToken()
            guard let url = GoogleOAuth.authorizationURL(clientID: Self.clientID, codeChallenge: challenge,
                                                          state: expectedState, selectAccount: true) else {
                throw GmailError.notConfigured
            }

            let callback = try await authenticate(url: url, callbackScheme: scheme)
            let redirect = GoogleOAuth.parseRedirect(callback)
            if let error = redirect.error {
                throw error == "access_denied" ? GmailError.signInCancelled : GmailError.signInFailed(error)
            }
            guard redirect.state == expectedState, let code = redirect.code else {
                throw GmailError.signInFailed("ongeldig antwoord van Google")
            }

            let tokens = try await tokenRequest(["grant_type": "authorization_code",
                                                 "code": code,
                                                 "code_verifier": verifier,
                                                 "redirect_uri": redirectURI,
                                                 "client_id": Self.clientID])
            guard let refresh = tokens.refreshToken else {
                throw GmailError.signInFailed("Google gaf geen refresh-token terug")
            }
            guard let email = try await profileEmail(accessToken: tokens.accessToken) else {
                throw GmailError.signInFailed("het e-mailadres van het account is onbekend")
            }
            // Zelfde account nogmaals toevoegen vervangt alleen de token.
            Keychain.write(refresh, account: Self.tokenAccount(email))
            if !accounts.contains(email) { accounts.append(email) }
            activeAccount = email
            combinedAccounts = []
            persistAccounts()
            tokenCache[email] = (tokens.accessToken, Date().addingTimeInterval(tokens.expiresIn))
            refreshVisible()
            state = .signedIn
            await reload()
        } catch GmailError.signInCancelled {
            state = hasAnyAccount ? .signedIn : .signedOut
        } catch {
            state = hasAnyAccount ? .signedIn : .signedOut
            lastError = error.localizedDescription
        }
    }

    /// Schakelt het paneel naar een andere gekoppelde mailbox.
    func switchAccount(to email: String) async {
        guard accounts.contains(email), email != activeAccount || isCombined else { return }
        activeAccount = email
        combinedAccounts = []
        persistAccounts()
        refreshVisible()
        lastError = nil
        await reload()
    }

    /// Alle mailboxen samen in één lijst.
    func showCombined() async {
        guard accounts.count > 1, !isAllCombined else { return }
        combinedAccounts = accounts
        persistAccounts()
        refreshVisible()
        lastError = nil
        await reload()
    }

    /// ⌘-klik op een tab: zet de mailbox erbij in de gecombineerde lijst, of haalt hem eruit.
    /// Blijft er één over, dan is dat gewoon weer de actieve mailbox.
    func toggleInCombination(_ email: String) async {
        guard accounts.contains(email) else { return }
        var selection = isCombined ? combinedAccounts : [activeAccount].compactMap { $0 }
        if selection.contains(email) {
            selection.removeAll { $0 == email }
        } else {
            selection.append(email)
        }
        selection = accounts.filter(selection.contains)   // vaste volgorde, zoals de tabs
        if selection.count > 1 {
            combinedAccounts = selection
        } else {
            combinedAccounts = []
            if let only = selection.first { activeAccount = only }
        }
        persistAccounts()
        refreshVisible()
        lastError = nil
        await reload()
    }

    /// Koppelt een mailbox los (en trekt de toegang bij Google in).
    func removeAccount(_ email: String) {
        if let refresh = Keychain.read(Self.tokenAccount(email)) {
            // Best effort: trek de toegang bij Google ook in.
            Task.detached {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data("token=\(Self.formEncode(refresh))".utf8)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        Keychain.delete(Self.tokenAccount(email))
        accounts.removeAll { $0 == email }
        messageCache[email] = nil
        tokenCache[email] = nil
        if activeAccount == email { activeAccount = accounts.first }
        combinedAccounts.removeAll { $0 == email }
        if combinedAccounts.count < 2 { combinedAccounts = [] }
        state = hasAnyAccount ? .signedIn : .signedOut
        persistAccounts()
        refreshVisible()
        if activeAccount != nil { Task { await reload() } }
    }

    func signOut() {
        if let account = activeAccount {
            removeAccount(account)
        } else {
            Keychain.delete(Self.legacyAccount)
            tokenCache[""] = nil
            messageCache[""] = nil
            refreshVisible()
            state = .signedOut
        }
    }

    /// Verhuist de enkele token van vóór het schakelen naar een token per e-mailadres.
    func migrateLegacyIfNeeded() async {
        guard accounts.isEmpty, let legacy = Keychain.read(Self.legacyAccount) else { return }
        do {
            let tokens = try await tokenRequest(["grant_type": "refresh_token",
                                                 "refresh_token": legacy,
                                                 "client_id": Self.clientID])
            guard let email = try await profileEmail(accessToken: tokens.accessToken) else { return }
            Keychain.write(legacy, account: Self.tokenAccount(email))
            Keychain.delete(Self.legacyAccount)
            accounts = [email]
            activeAccount = email
            persistAccounts()
            tokenCache[email] = (tokens.accessToken, Date().addingTimeInterval(tokens.expiresIn))
        } catch GmailError.sessionExpired {
            Keychain.delete(Self.legacyAccount)
            state = .signedOut
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: GmailError.signInCancelled)
                } else {
                    continuation.resume(throwing: error ?? GmailError.invalidResponse)
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: GmailError.signInFailed("het inlogvenster kon niet worden geopend"))
            }
        }
    }

    // MARK: Tokens

    private func tokenRequest(_ parameters: [String: String]) async throws -> GoogleOAuth.TokenResponse {
        var request = URLRequest(url: URL(string: GoogleOAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(parameters.map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let tokens = GoogleOAuth.parseTokenResponse(data) { return tokens }
        if let error = GoogleOAuth.parseError(data) {
            throw error.requiresNewSignIn ? GmailError.sessionExpired
                                          : GmailError.signInFailed(error.description ?? error.code)
        }
        throw GmailError.invalidResponse
    }

    private func validAccessToken(account: String?) async throws -> String {
        let key = account ?? ""
        if let cached = tokenCache[key], cached.expiry > Date().addingTimeInterval(60) { return cached.token }
        guard let refresh = refreshToken(for: account) else { throw GmailError.notSignedIn }
        do {
            let tokens = try await tokenRequest(["grant_type": "refresh_token",
                                                 "refresh_token": refresh,
                                                 "client_id": Self.clientID])
            tokenCache[key] = (tokens.accessToken, Date().addingTimeInterval(tokens.expiresIn))
            return tokens.accessToken
        } catch GmailError.sessionExpired {
            // De toegang is ingetrokken of verlopen: dit account moet opnieuw worden toegevoegd.
            if let account { removeAccount(account) } else { signOut() }
            throw GmailError.sessionExpired
        }
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Base64URL.encode(Data(bytes))
    }

    private nonisolated static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: Gmail API

    private func api(_ path: String, query: [URLQueryItem] = [], method: String = "GET",
                     body: Data? = nil, account: String? = nil, isRetry: Bool = false) async throws -> Data {
        let account = account ?? activeAccount
        let token = try await validAccessToken(account: account)
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GmailError.invalidResponse }
        if http.statusCode == 401, !isRetry {
            tokenCache[account ?? ""] = nil   // verlopen of ingetrokken: één keer opnieuw met een verse token
            return try await api(path, query: query, method: method, body: body, account: account, isRetry: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw GmailError.http(http.statusCode, message)
        }
        return data
    }

    /// Het e-mailadres bij een access-token (rechtstreeks, los van het actieve account).
    private func profileEmail(accessToken: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GmailError.invalidResponse }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["emailAddress"] as? String
    }

    /// Haalt de inbox (nieuwste eerst, één rij per gesprek) opnieuw op; in de gecombineerde weergave van alle mailboxen.
    func reload() async {
        guard state == .signedIn else { return }
        let keys = isCombined ? combinedAccounts : [activeAccount ?? ""]
        await withTaskGroup(of: Void.self) { group in
            for key in keys { group.addTask { await self.reload(key: key) } }
        }
    }

    private func reload(key: String) async {
        guard !loadingKeys.contains(key) else { return }
        let account: String? = key.isEmpty ? nil : key
        loadingKeys.insert(key)
        isLoading = true
        defer {
            loadingKeys.remove(key)
            isLoading = !loadingKeys.isEmpty
        }
        do {
            let listData = try await api("messages", query: [URLQueryItem(name: "labelIds", value: "INBOX"),
                                                              URLQueryItem(name: "maxResults", value: Self.inboxPageSize)],
                                         account: account)
            var seenThreads = Set<String>()
            let refs = GmailAPI.messageRefs(fromListJSON: listData).refs.filter { seenThreads.insert($0.threadID).inserted }

            let summaries = await withTaskGroup(of: (Int, GmailMessageSummary?).self) { group -> [GmailMessageSummary] in
                for (index, ref) in refs.enumerated() {
                    group.addTask { (index, await self.summary(forMessageID: ref.id, account: account)) }
                }
                var found: [(Int, GmailMessageSummary)] = []
                for await (index, summary) in group {
                    if let summary { found.append((index, summary)) }
                }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            guard key.isEmpty || accounts.contains(key) else { return }   // intussen losgekoppeld
            messageCache[key] = summaries
            for summary in summaries {
                messageAccount[summary.id] = key
                messageAccount[summary.threadID] = key
            }
            refreshVisible()
            lastError = nil
        } catch {
            if state == .signedIn, isCombined || key == (activeAccount ?? "") { lastError = error.localizedDescription }
        }
    }

    private func summary(forMessageID id: String, account: String?) async -> GmailMessageSummary? {
        let query = [URLQueryItem(name: "format", value: "metadata"),
                     URLQueryItem(name: "metadataHeaders", value: "From"),
                     URLQueryItem(name: "metadataHeaders", value: "Subject")]
        guard let data = try? await api("messages/\(id)", query: query, account: account) else { return nil }
        return GmailAPI.summary(fromMessageJSON: data)
    }

    // MARK: Verzonden mails (dagafsluiting)

    /// Verzonden mails tussen `start` en `end` uit alle gekoppelde mailboxen, oudste eerst.
    func sentMails(from start: Date, to end: Date) async -> [(account: String?, mail: GmailThreadMessage)] {
        let keys: [String?] = accounts.isEmpty ? [activeAccount] : accounts.map { $0 }
        let q = "in:sent after:\(Int(start.timeIntervalSince1970)) before:\(Int(end.timeIntervalSince1970))"
        let headers = ["To", "Cc", "Subject"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
        var found: [(account: String?, mail: GmailThreadMessage)] = []
        for account in keys {
            guard let list = try? await api("messages", query: [URLQueryItem(name: "q", value: q),
                                                                 URLQueryItem(name: "maxResults", value: "40")],
                                            account: account) else { continue }
            for ref in GmailAPI.messageRefs(fromListJSON: list).refs {
                guard let data = try? await api("messages/\(ref.id)",
                                                query: [URLQueryItem(name: "format", value: "metadata")] + headers,
                                                account: account),
                      let mail = GmailAPI.threadMessage(fromMessageJSON: data) else { continue }
                found.append((account, mail))
            }
        }
        return found.sorted { $0.mail.date < $1.mail.date }
    }

    // MARK: Verplaatsen naar een andere mailbox

    /// Verplaatst een heel gesprek naar een andere gekoppelde mailbox: elke mail wordt daar ingevoegd alsof hij daar
    /// binnenkwam (geen doorsturen, er gaat niets de deur uit), daarna gaat het gesprek in de oude mailbox naar de
    /// prullenbak. Met ⌘Z terug.
    func moveThread(threadID: String, messageID: String? = nil, from source: String?, to target: String,
                    appState: AppState) async {
        let source = source ?? messageAccount[threadID] ?? activeAccount
        guard accounts.contains(target), source != target else { return }
        let busyKey = messageID ?? threadID
        guard !busyMessageIDs.contains(busyKey) else { return }
        busyMessageIDs.insert(busyKey)
        defer { busyMessageIDs.remove(busyKey) }

        do {
            // Concepten en wat al in de prullenbak of spam ligt gaan niet mee.
            let items = try await threadMessages(threadID: threadID, account: source)
                .filter { Set($0.labels).isDisjoint(with: ["DRAFT", "TRASH", "SPAM"]) }
            guard let newest = items.last else { return }
            let keep: Set<String> = ["INBOX", "UNREAD", "STARRED", "IMPORTANT"]
            let inInbox = items.contains { $0.labels.contains("INBOX") }
            var inserted: [String] = []
            var targetThread: String?
            for item in items {
                let raw = try await rawMessage(id: item.id)
                var labels = item.labels.filter(keep.contains)
                // Een gearchiveerd gesprek komt in de andere mailbox gewoon in de inbox terecht.
                if !inInbox, item.id == newest.id { labels.append("INBOX") }
                let result = try await insert(raw: raw, labels: labels, threadID: targetThread, account: target)
                inserted.append(result.id)
                targetThread = targetThread ?? result.threadID
            }
            try await trash(threadID: threadID, account: source)
            removeThreadFromLists(threadID)
            if let targetThread { WaitingWatcher.shared.relink(threadID: threadID, to: targetThread, account: target) }
            for id in inserted { note(account: target, forMessageID: id) }
            if let targetThread { note(account: target, forMessageID: targetThread) }
            if isCombined || activeAccount == target { await reload() }
            appState.announce("Verplaatst naar \(displayName(target))")

            UndoCenter.shared.record("Mail verplaatsen", undo: { [weak self] in
                if let targetThread { WaitingWatcher.shared.relink(threadID: targetThread, to: threadID, account: source) }
                Task { await self?.undoMove(threadID: threadID, source: source, inserted: inserted, target: target) }
            })
        } catch {
            appState.showToast("Verplaatsen mislukt: \(error.localizedDescription)", seconds: 5)
        }
    }

    private func undoMove(threadID: String, source: String?, inserted: [String], target: String) async {
        do {
            _ = try await api("threads/\(threadID)/untrash", method: "POST", account: source)
            for id in inserted {
                _ = try? await api("messages/\(id)/trash", method: "POST", account: target)
            }
            await reload()
        } catch {
            AppState.shared.announce("Terugzetten mislukt")
        }
    }

    private func trash(threadID: String, account: String?) async throws {
        _ = try await api("threads/\(threadID)/trash", method: "POST", account: account)
    }

    /// `messages.insert` via de upload-route (multipart: labels en gesprek als JSON, de mail als message/rfc822),
    /// zodat ook grote mails met bijlagen passen. De datum komt uit de mail zelf.
    private func insert(raw: Data, labels: [String], threadID: String?, account: String,
                        isRetry: Bool = false) async throws -> (id: String, threadID: String) {
        var metadata: [String: Any] = ["labelIds": labels]
        if let threadID { metadata["threadId"] = threadID }
        let boundary = "werkbank-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: message/rfc822\r\n\r\n".utf8))
        body.append(raw)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let token = try await validAccessToken(account: account)
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/upload/gmail/v1/users/me/messages?uploadType=multipart&internalDateSource=dateHeader")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GmailError.invalidResponse }
        if http.statusCode == 401, !isRetry {
            tokenCache[account] = nil
            return try await insert(raw: raw, labels: labels, threadID: threadID, account: account, isRetry: true)
        }
        // Wil Gmail hem niet bij het gesprek zetten, dan gewoon los.
        if http.statusCode == 400, threadID != nil {
            return try await insert(raw: raw, labels: labels, threadID: nil, account: account, isRetry: isRetry)
        }
        guard (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw GmailError.http(http.statusCode, message)
        }
        return (id, json["threadId"] as? String ?? id)
    }

    /// Verstuurt een kant-en-klare mail (RFC 822) vanuit `account`; `threadID` houdt een antwoord in hetzelfde gesprek.
    func send(raw: Data, threadID: String?, account: String) async throws {
        var json: [String: Any] = ["raw": Base64URL.encode(raw)]
        if let threadID { json["threadId"] = threadID }
        let body = try JSONSerialization.data(withJSONObject: json)
        _ = try await api("messages/send", method: "POST", body: body, account: account)
    }

    /// De mails van een gesprek (oudste eerst, zonder concepten): koppen en snippet, nog zonder inhoud.
    /// Eén lichte aanvraag; de inhoud per mail volgt pas als hij open wordt geklapt.
    func threadMessages(threadID: String, account: String?) async throws -> [GmailThreadMessage] {
        note(account: account, forMessageID: threadID)
        let owner = account ?? messageAccount[threadID]
        let query = [URLQueryItem(name: "format", value: "metadata")]
            + ["From", "To", "Cc", "Subject"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
        let data = try await api("threads/\(threadID)", query: query, account: owner)
        guard let messages = GmailAPI.threadMessages(fromJSON: data) else { throw GmailError.invalidResponse }
        for message in messages { note(account: owner, forMessageID: message.id) }
        return messages
    }

    /// De ruwe mail (RFC 822), bijvoorbeeld voor de analyse met Claude.
    func rawMessageData(id: String) async throws -> Data { try await rawMessage(id: id) }

    private func rawMessage(id: String) async throws -> Data {
        if let cached = rawCache[id] { return cached }
        let data = try await api("messages/\(id)", query: [URLQueryItem(name: "format", value: "raw")],
                                 account: messageAccount[id])
        guard let raw = GmailAPI.rawMessage(fromJSON: data) else { throw GmailError.invalidResponse }
        // Een mail verandert niet meer: bewaren, zodat opnieuw openen, antwoorden en analyseren niet opnieuw downloaden.
        rawCache[id] = raw
        rawCacheOrder.removeAll { $0 == id }
        rawCacheOrder.append(id)
        while rawCacheOrder.count > Self.rawCacheLimit {
            rawCache[rawCacheOrder.removeFirst()] = nil
        }
        return raw
    }

    /// Archiveert het hele gesprek (haalt het label INBOX weg), zoals de knop "Archiveren" in Gmail.
    private func archive(threadID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["INBOX"]])
        _ = try await api("threads/\(threadID)/modify", method: "POST", body: body, account: messageAccount[threadID])
    }

    /// Zet een gesprek terug in de inbox (⌘Z na archiveren).
    private func restoreToInbox(threadID: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["addLabelIds": ["INBOX"]])
            _ = try await api("threads/\(threadID)/modify", method: "POST", body: body, account: messageAccount[threadID])
            await reload()
        } catch {
            AppState.shared.announce("Terugzetten in de inbox mislukt")
        }
    }

    private func recordArchive(threadID: String) {
        UndoCenter.shared.record("Mail archiveren", undo: { [weak self] in
            Task { await self?.restoreToInbox(threadID: threadID) }
        }, redo: { [weak self] in
            Task {
                try? await self?.archive(threadID: threadID)
                self?.removeThreadFromLists(threadID)
            }
        })
    }

    /// ⌘Z na een taak uit een mail: de kaart weg en (als hij gearchiveerd was) de mail terug in de inbox.
    /// Onthoudt bij de kaart uit welk gesprek (en welke mailbox) hij komt, voor Wacht op klant.
    private func link(_ card: TodoCard, threadID: String, messageID: String, context: ModelContext) {
        card.mailThreadID = threadID
        card.mailAccount = account(for: messageID)
        try? context.save()
    }

    private func recordCardFromMail(cardID: UUID, threadID: String, archived: Bool, context: ModelContext) {
        UndoCenter.shared.record(archived ? "Taak van mail maken" : "Mail naar taak", undo: { [weak self] in
            if let card = BoardService.card(withID: cardID, in: context) {
                BoardService.delete(card, undoable: false, in: context)
            }
            if archived { Task { await self?.restoreToInbox(threadID: threadID) } }
        })
    }

    // MARK: Openklappen en archiveren vanuit de lijst

    /// De tekst van een mail (alleen text, geen opmaak of bijlagen), voor het openklappen in het paneel.
    func body(forMessageID id: String) async throws -> String {
        if let cached = bodyCache[id] { return cached }
        let text = EMLParser.parse(try await rawMessage(id: id)).bodyText ?? ""
        bodyCache[id] = text
        return text
    }

    /// Archiveert het gesprek zonder er een kaart van te maken (de knop in de lijst).
    func archiveMessage(_ message: GmailMessageSummary, appState: AppState) async {
        guard !busyMessageIDs.contains(message.id) else { return }
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }
        do {
            try await archive(threadID: message.threadID)
            removeThreadFromLists(message.threadID)
            bodyCache[message.id] = nil
            recordArchive(threadID: message.threadID)
            appState.showToast("Mail gearchiveerd in Gmail")
        } catch {
            appState.showToast("Archiveren mislukt: \(error.localizedDescription)", seconds: 5)
        }
    }

    /// Maakt van een geopende mail een taak (met eigen titel en eventueel al bestede tijd) en archiveert hem daarna.
    /// Zelfde volgorde als bij slepen: eerst de kaart, dan archiveren; mislukt dat, dan blijft de kaart staan.
    func createTask(from message: GmailMessageSummary, title: String, minutes: Int, column: BoardColumn,
                    context: ModelContext, appState: AppState) async {
        guard !busyMessageIDs.contains(message.id) else { return }
        busyMessageIDs.insert(message.id)
        defer { busyMessageIDs.remove(message.id) }

        let text: String
        do {
            text = try await body(forMessageID: message.id)
        } catch {
            appState.showToast("Mail ophalen uit Gmail mislukt: \(error.localizedDescription)", seconds: 5)
            return
        }

        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = ParsedMail(subject: name.isEmpty ? message.subject : name,
                              fromName: message.fromName, fromAddress: message.fromAddress,
                              bodyText: text.isEmpty ? nil : text)
        let card = BoardService.addMail(mail, column: column, in: context)
        link(card, threadID: message.threadID, messageID: message.id, context: context)
        let logged = max(0, min(minutes, 24 * 60))
        if logged > 0 { TimerService.logPriorTime(for: card, minutes: logged, in: context) }

        let columnTitle = BoardService.title(of: BoardService.resolve(column, in: context), in: context)
        let timeNote = logged > 0 ? ", \(logged) min gelogd" : ""
        do {
            try await archive(threadID: message.threadID)
            removeThreadFromLists(message.threadID)
            bodyCache[message.id] = nil
            recordCardFromMail(cardID: card.id, threadID: message.threadID, archived: true, context: context)
            appState.showToast("Taak gemaakt in \(columnTitle)\(timeNote); mail gearchiveerd in Gmail", seconds: 3)
        } catch {
            appState.showToast("Taak gemaakt\(timeNote), maar archiveren in Gmail mislukte: \(error.localizedDescription)", seconds: 6)
        }
    }

    // MARK: Naar het board slepen

    /// Maakt van een gesleepte Gmail-mail een kaart in `column` en archiveert hem daarna in Gmail (tenzij `archive` uit staat).
    /// Archiveren gebeurt pas als de kaart is opgeslagen; mislukt het, dan blijft de kaart staan en de mail in de inbox.
    @discardableResult
    func importDropped(_ payload: GmailDragPayload, column: BoardColumn, archive shouldArchive: Bool = true,
                       context: ModelContext, appState: AppState) async -> TodoCard? {
        guard !busyMessageIDs.contains(payload.messageID) else { return nil }
        busyMessageIDs.insert(payload.messageID)
        defer { busyMessageIDs.remove(payload.messageID) }

        let raw: Data
        do {
            raw = try await rawMessage(id: payload.messageID)
        } catch {
            appState.showToast("Mail ophalen uit Gmail mislukt: \(error.localizedDescription)", seconds: 5)
            return nil
        }

        let card = BoardService.addMail(EMLParser.parse(raw), column: column, in: context)
        link(card, threadID: payload.threadID, messageID: payload.messageID, context: context)
        // De titel van een nieuwe mailkaart wil je altijd nakijken (zelfde gedrag als bij een gesleept .eml-bestand).
        InlineEditing.pendingEditID = card.id
        let sender = card.clientLabel ?? "onbekende afzender"
        let columnTitle = BoardService.title(of: BoardService.resolve(column, in: context), in: context)

        guard shouldArchive else {
            recordCardFromMail(cardID: card.id, threadID: payload.threadID, archived: false, context: context)
            appState.showToast("Mail van \(sender) toegevoegd aan \(columnTitle)", seconds: 3)
            return card
        }

        do {
            try await archive(threadID: payload.threadID)
            removeThreadFromLists(payload.threadID)
            recordCardFromMail(cardID: card.id, threadID: payload.threadID, archived: true, context: context)
            appState.showToast("Mail van \(sender) toegevoegd aan \(columnTitle) en gearchiveerd in Gmail", seconds: 3)
        } catch {
            appState.showToast("Kaart gemaakt, maar archiveren in Gmail mislukte: \(error.localizedDescription)", seconds: 6)
        }
        return card
    }

    /// De sleeplading van één rij in het paneel.
    func dragProvider(for message: GmailMessageSummary) -> NSItemProvider {
        let payload = GmailDragPayload(messageID: message.id, threadID: message.threadID, subject: message.subject)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier,
                                            visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

// MARK: - Drop

enum GmailDrop {
    static func accepts(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) }
    }

    /// - Returns: `true` als er een Gmail-mail in de sleeplading zit.
    @MainActor
    static func handle(providers: [NSItemProvider], column: BoardColumn, archive: Bool = true,
                       context: ModelContext, appState: AppState) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
                Task { @MainActor in
                    await GmailSession.shared.importDropped(payload, column: column, archive: archive, context: context, appState: appState)
                }
            }
        }
        return true
    }
}
