import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit
import WerkbankCore

/// Gmail op de iPhone: meer mailboxen (OAuth met PKCE, refresh-token per adres in de sleutelhanger), de inbox van elke
/// mailbox, gesprekken, zoeken, archiveren, prullenbak, gelezen/ongelezen en versturen. De Mac heeft zijn eigen
/// `GmailSession`; wat tussen de toestellen gelijk moet blijven (namen van mailboxen, sterren) gaat via iCloud.
@MainActor
@Observable
final class PhoneGmail {
    static let shared = PhoneGmail()
    static let accountsKey = "phone.gmail.accounts"
    /// Dezelfde sleutel als op de Mac: de korte namen van de mailboxen ("SUPPORT").
    static let displayNamesKey = "gmail.displayNames"

    private(set) var accounts: [String] = UserDefaults.standard.stringArray(forKey: PhoneGmail.accountsKey) ?? []
    private(set) var inbox: [String: [GmailMailItem]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var lastRefresh: Date?
    private(set) var isSigningIn = false
    var lastError: String?

    @ObservationIgnored private var tokens: [String: (token: String, expiry: Date)] = [:]
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presenter = PhoneWebAuthPresenter()
    @ObservationIgnored private var rawCache: [String: Data] = [:]

    private static let http: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool { GoogleOAuth.redirectScheme(forClientID: Self.clientID) != nil }

    // MARK: Namen

    /// De korte naam van een mailbox (zoals op de Mac ingesteld), anders het deel voor de @ in hoofdletters.
    func displayName(_ account: String) -> String {
        let names = UserDefaults.standard.dictionary(forKey: Self.displayNamesKey) as? [String: String] ?? [:]
        if let name = names[account], !name.isEmpty { return name.uppercased() }
        return String(account.split(separator: "@").first ?? Substring(account)).uppercased()
    }

    func setDisplayName(_ name: String, for account: String) {
        var names = UserDefaults.standard.dictionary(forKey: Self.displayNamesKey) as? [String: String] ?? [:]
        names[account] = name.trimmingCharacters(in: .whitespaces)
        PhonePreferencesSync.shared.set(names, forKey: Self.displayNamesKey)
    }

    func account(ofThread threadID: String) -> String? {
        inbox.first { $0.value.contains { $0.threadID == threadID } }?.key
    }

    // MARK: Inloggen

    func signIn() async {
        guard isConfigured, let redirectURI = GoogleOAuth.redirectURI(forClientID: Self.clientID),
              let scheme = GoogleOAuth.redirectScheme(forClientID: Self.clientID) else {
            lastError = "Gmail is op dit toestel niet ingesteld (geen client-id)."
            return
        }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let verifier = Self.randomToken()
            let challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
            let expectedState = Self.randomToken()
            guard let url = GoogleOAuth.authorizationURL(clientID: Self.clientID, codeChallenge: challenge,
                                                          state: expectedState, selectAccount: true) else { return }
            let callback = try await authenticate(url: url, callbackScheme: scheme)
            let redirect = GoogleOAuth.parseRedirect(callback)
            if let error = redirect.error {
                if error != "access_denied" { lastError = "Inloggen mislukt: \(error)" }
                return
            }
            guard redirect.state == expectedState, let code = redirect.code else {
                lastError = "Inloggen mislukt: ongeldig antwoord van Google"
                return
            }
            let response = try await tokenRequest(["grant_type": "authorization_code", "code": code,
                                                   "code_verifier": verifier, "redirect_uri": redirectURI,
                                                   "client_id": Self.clientID])
            guard let refresh = response.refreshToken else {
                lastError = "Inloggen mislukt: Google gaf geen refresh-token terug"
                return
            }
            guard let email = try await profileEmail(accessToken: response.accessToken) else {
                lastError = "Inloggen mislukt: het e-mailadres van het account is onbekend"
                return
            }
            PhoneKeychain.write(refresh, account: email)
            if !accounts.contains(email) { accounts.append(email) }
            UserDefaults.standard.set(accounts, forKey: Self.accountsKey)
            tokens[email] = (response.accessToken, Date().addingTimeInterval(response.expiresIn))
            await reload(email)
        } catch is CancellationError {
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            lastError = "Inloggen mislukt: \(error.localizedDescription)"
        }
    }

    func remove(_ account: String) {
        PhoneKeychain.delete(account)
        accounts.removeAll { $0 == account }
        UserDefaults.standard.set(accounts, forKey: Self.accountsKey)
        inbox[account] = nil
        tokens[account] = nil
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(accounts, forKey: Self.accountsKey)
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
        }
    }

    private func tokenRequest(_ parameters: [String: String]) async throws -> GoogleOAuth.TokenResponse {
        var request = URLRequest(url: URL(string: GoogleOAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await Self.http.data(for: request)
        if let tokens = GoogleOAuth.parseTokenResponse(data) { return tokens }
        if let error = GoogleOAuth.parseError(data) {
            throw PhoneGmailError.oauth(error.requiresNewSignIn, error.description ?? error.code)
        }
        throw URLError(.badServerResponse)
    }

    private func profileEmail(accessToken: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await Self.http.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["emailAddress"] as? String
    }

    private func accessToken(_ account: String) async throws -> String {
        if let cached = tokens[account], cached.expiry > Date().addingTimeInterval(60) { return cached.token }
        guard let refresh = PhoneKeychain.read(account) else { throw PhoneGmailError.notSignedIn }
        do {
            let response = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh,
                                                   "client_id": Self.clientID])
            tokens[account] = (response.accessToken, Date().addingTimeInterval(response.expiresIn))
            return response.accessToken
        } catch PhoneGmailError.oauth(true, _) {
            lastError = "\(displayName(account)): opnieuw inloggen nodig"
            throw PhoneGmailError.notSignedIn
        }
    }

    // MARK: API

    private func api(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil,
                     account: String, isRetry: Bool = false, attempt: Int = 0) async throws -> Data {
        let token = try await accessToken(account)
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await Self.http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !isRetry {
            tokens[account] = nil
            return try await api(path, query: query, method: method, body: body, account: account, isRetry: true)
        }
        if attempt < 3, status == 429 || status == 403 && String(decoding: data, as: UTF8.self).contains("ateLimit") {
            try await Task.sleep(for: .seconds(0.6 * Double(1 << attempt) + Double.random(in: 0...0.3)))
            return try await api(path, query: query, method: method, body: body, account: account, isRetry: isRetry,
                                 attempt: attempt + 1)
        }
        guard (200..<300).contains(status) else { throw PhoneGmailError.http(status) }
        return data
    }

    /// Koppen van mails, acht tegelijk onderweg, in de volgorde van `ids`.
    private func items(ids: [String], account: String) async -> [GmailMailItem] {
        let query = [URLQueryItem(name: "format", value: "metadata")]
            + GmailAPI.mailItemHeaders.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        var found: [String: GmailMailItem] = [:]
        var pending = ids.makeIterator()
        await withTaskGroup(of: GmailMailItem?.self) { group in
            for _ in 0..<8 {
                guard let id = pending.next() else { break }
                group.addTask { await self.item(id: id, query: query, account: account) }
            }
            for await item in group {
                if let item { found[item.id] = item }
                if let id = pending.next() { group.addTask { await self.item(id: id, query: query, account: account) } }
            }
        }
        return ids.compactMap { found[$0] }
    }

    private func item(id: String, query: [URLQueryItem], account: String) async -> GmailMailItem? {
        guard let data = try? await api("messages/\(id)", query: query, account: account) else { return nil }
        return GmailAPI.mailItem(fromMessageJSON: data)
    }

    /// Mails volgens een zoekopdracht, één per gesprek.
    func list(query text: String, labels: [String] = [], account: String, max: Int = 50) async throws -> [GmailMailItem] {
        var query = [URLQueryItem(name: "maxResults", value: String(max))]
        if !text.isEmpty { query.append(URLQueryItem(name: "q", value: text)) }
        query += labels.map { URLQueryItem(name: "labelIds", value: $0) }
        let list = try await api("messages", query: query, account: account)
        var seen = Set<String>()
        let refs = GmailAPI.messageRefs(fromListJSON: list).refs.filter { seen.insert($0.threadID).inserted }
        return await items(ids: refs.map(\.id), account: account)
    }

    func reloadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for account in accounts { group.addTask { await self.reload(account) } }
        }
        lastRefresh = Date()
    }

    func reload(_ account: String) async {
        loading.insert(account)
        defer { loading.remove(account) }
        do {
            let items = try await list(query: "", labels: ["INBOX"], account: account)
            inbox[account] = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } catch PhoneGmailError.notSignedIn {
        } catch {
            lastError = "\(displayName(account)): ophalen mislukt"
        }
    }

    /// Zoeken in meer mailboxen tegelijk; nieuwste eerst.
    func search(_ text: String, accounts chosen: [String]) async -> [(account: String, item: GmailMailItem)] {
        var results: [(account: String, item: GmailMailItem)] = []
        await withTaskGroup(of: [(account: String, item: GmailMailItem)].self) { group in
            for account in chosen {
                group.addTask {
                    let items = (try? await self.list(query: text, account: account, max: 40)) ?? []
                    return items.map { (account: account, item: $0) }
                }
            }
            for await part in group { results += part }
        }
        return results.sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
    }

    func thread(_ threadID: String, account: String) async throws -> [GmailThreadMessage] {
        let query = [URLQueryItem(name: "format", value: "metadata")]
            + ["From", "To", "Cc", "Bcc", "Subject"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
        let data = try await api("threads/\(threadID)", query: query, account: account)
        guard let messages = GmailAPI.threadMessages(fromJSON: data) else { throw PhoneGmailError.http(0) }
        return messages
    }

    func content(_ messageID: String, account: String) async throws -> MailContent {
        let raw: Data
        if let cached = rawCache[messageID] {
            raw = cached
        } else {
            let data = try await api("messages/\(messageID)", query: [URLQueryItem(name: "format", value: "raw")],
                                     account: account)
            guard let decoded = GmailAPI.rawMessage(fromJSON: data) else { throw PhoneGmailError.http(0) }
            rawCache[messageID] = decoded
            raw = decoded
        }
        return await Task.detached(priority: .userInitiated) { MailContentParser.parse(raw) }.value
    }

    // MARK: Handelingen

    private func modify(_ threadID: String, account: String, add: [String] = [], remove: [String] = []) async -> Bool {
        var change: [String: [String]] = [:]
        if !add.isEmpty { change["addLabelIds"] = add }
        if !remove.isEmpty { change["removeLabelIds"] = remove }
        guard let body = try? JSONSerialization.data(withJSONObject: change) else { return false }
        return (try? await api("threads/\(threadID)/modify", method: "POST", body: body, account: account)) != nil
    }

    private func dropFromInbox(_ threadID: String) {
        for key in Array(inbox.keys) { inbox[key]?.removeAll { $0.threadID == threadID } }
        PhoneStars.shared.remove(threadID)
    }

    func archive(_ threads: [(threadID: String, account: String)]) async -> Int {
        threads.forEach { dropFromInbox($0.threadID) }
        var done = 0
        for thread in threads where await modify(thread.threadID, account: thread.account, remove: ["INBOX"]) { done += 1 }
        return done
    }

    func trash(_ threads: [(threadID: String, account: String)]) async -> Int {
        threads.forEach { dropFromInbox($0.threadID) }
        var done = 0
        for thread in threads where (try? await api("threads/\(thread.threadID)/trash", method: "POST",
                                                    account: thread.account)) != nil { done += 1 }
        return done
    }

    func setUnread(_ unread: Bool, _ threads: [(threadID: String, account: String)]) async {
        for thread in threads {
            for key in Array(inbox.keys) {
                guard let indices = inbox[key]?.indices.filter({ inbox[key]?[$0].threadID == thread.threadID }) else { continue }
                for index in indices {
                    var labels = inbox[key]?[index].labels.filter { $0 != "UNREAD" } ?? []
                    if unread { labels.append("UNREAD") }
                    inbox[key]?[index].labels = labels
                }
            }
            _ = await modify(thread.threadID, account: thread.account, add: unread ? ["UNREAD"] : [],
                             remove: unread ? [] : ["UNREAD"])
        }
    }

    /// Een gesprek naar een andere mailbox: de mails worden in de doelmailbox gezet (`messages.import`) en het gesprek
    /// gaat in de bron naar de prullenbak.
    func move(threadID: String, from source: String, to target: String) async -> Bool {
        guard let messages = try? await thread(threadID, account: source) else { return false }
        for message in messages where !message.labels.contains("DRAFT") {
            guard let data = try? await api("messages/\(message.id)", query: [URLQueryItem(name: "format", value: "raw")],
                                            account: source),
                  let raw = GmailAPI.rawMessage(fromJSON: data) else { return false }
            let labels = message.labels.filter { ["UNREAD", "STARRED", "IMPORTANT"].contains($0) } + ["INBOX"]
            let body = try? JSONSerialization.data(withJSONObject: ["raw": Base64URL.encode(raw), "labelIds": labels])
            guard (try? await api("messages/import", method: "POST", body: body, account: target)) != nil else { return false }
        }
        _ = try? await api("threads/\(threadID)/trash", method: "POST", account: source)
        dropFromInbox(threadID)
        await reload(target)
        return true
    }

    @discardableResult
    func send(_ raw: Data, threadID: String?, account: String) async throws -> String? {
        var payload: [String: Any] = ["raw": Base64URL.encode(raw)]
        if let threadID { payload["threadId"] = threadID }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let response = try await api("messages/send", method: "POST", body: body, account: account)
        return (try? JSONSerialization.jsonObject(with: response) as? [String: Any])?["threadId"] as? String
    }

    // MARK: Hulp

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
}

enum PhoneGmailError: Error, LocalizedError {
    case notSignedIn
    case http(Int)
    case oauth(Bool, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Niet ingelogd"
        case .http(let status): "Gmail gaf fout \(status)"
        case .oauth(_, let text): text
        }
    }
}

/// Het inlogvenster van Google hangt aan het venster van de app.
final class PhoneWebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first.map { UIWindow(windowScene: $0) }
                ?? ASPresentationAnchor()
        }
    }
}

/// Refresh-tokens per mailbox in de sleutelhanger (alleen op dit toestel).
enum PhoneKeychain {
    static let service = "Werkbank.Gmail.iPhone"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Sterren van Werkbank (niet die van Gmail): per gesprek, dezelfde lijst als de kolommen op de Mac, via iCloud.
@MainActor
@Observable
final class PhoneStars {
    static let shared = PhoneStars()
    static let key = "mailColumns.starred"

    private(set) var threads: Set<String> = Set(UserDefaults.standard.stringArray(forKey: PhoneStars.key) ?? [])

    func contains(_ threadID: String) -> Bool { threads.contains(threadID) }

    func toggle(_ threadIDs: [String]) {
        let on = !threadIDs.allSatisfy(contains)
        if on { threads.formUnion(threadIDs) } else { threads.subtract(threadIDs) }
        save()
    }

    func remove(_ threadID: String) {
        guard threads.contains(threadID) else { return }
        threads.remove(threadID)
        save()
    }

    /// Na het overnemen van iCloud.
    func reload() {
        threads = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    private func save() {
        PhonePreferencesSync.shared.set(threads.sorted(), forKey: Self.key)
    }
}
