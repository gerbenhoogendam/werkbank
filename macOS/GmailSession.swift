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
    private(set) var emailAddress: String?
    private(set) var messages: [GmailMessageSummary] = []
    private(set) var isLoading = false
    private(set) var busyMessageIDs: Set<String> = []
    private(set) var lastError: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presenter = WebAuthPresenter()

    private static let refreshAccount = "refreshToken"
    private static let inboxPageSize = "40"

    private init() {
        if Keychain.read(Self.refreshAccount) != nil { state = .signedIn }
    }

    // MARK: Configuratie

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool { GoogleOAuth.redirectScheme(forClientID: Self.clientID) != nil }

    // MARK: Inloggen

    func signIn() async {
        guard isConfigured, let redirectURI = GoogleOAuth.redirectURI(forClientID: Self.clientID),
              let scheme = GoogleOAuth.redirectScheme(forClientID: Self.clientID) else {
            lastError = GmailError.notConfigured.localizedDescription
            return
        }
        state = .signingIn
        lastError = nil
        do {
            let verifier = Self.randomToken()
            let challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
            let expectedState = Self.randomToken()
            guard let url = GoogleOAuth.authorizationURL(clientID: Self.clientID, codeChallenge: challenge,
                                                          state: expectedState) else { throw GmailError.notConfigured }

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
            Keychain.write(refresh, account: Self.refreshAccount)
            accessToken = tokens.accessToken
            accessExpiry = Date().addingTimeInterval(tokens.expiresIn)
            state = .signedIn
            await loadProfile()
            await reload()
        } catch GmailError.signInCancelled {
            state = Keychain.read(Self.refreshAccount) == nil ? .signedOut : .signedIn
        } catch {
            state = Keychain.read(Self.refreshAccount) == nil ? .signedOut : .signedIn
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        if let refresh = Keychain.read(Self.refreshAccount) {
            // Best effort: trek de toegang bij Google ook in.
            Task.detached {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data("token=\(Self.formEncode(refresh))".utf8)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        clearLocalSession()
    }

    private func clearLocalSession() {
        Keychain.delete(Self.refreshAccount)
        accessToken = nil
        accessExpiry = .distantPast
        emailAddress = nil
        messages = []
        state = .signedOut
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

    private func validAccessToken() async throws -> String {
        if let token = accessToken, accessExpiry > Date().addingTimeInterval(60) { return token }
        guard let refresh = Keychain.read(Self.refreshAccount) else { throw GmailError.notSignedIn }
        do {
            let tokens = try await tokenRequest(["grant_type": "refresh_token",
                                                 "refresh_token": refresh,
                                                 "client_id": Self.clientID])
            accessToken = tokens.accessToken
            accessExpiry = Date().addingTimeInterval(tokens.expiresIn)
            return tokens.accessToken
        } catch GmailError.sessionExpired {
            clearLocalSession()
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
                     body: Data? = nil, isRetry: Bool = false) async throws -> Data {
        let token = try await validAccessToken()
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
            accessToken = nil   // verlopen of ingetrokken: één keer opnieuw met een verse token
            return try await api(path, query: query, method: method, body: body, isRetry: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw GmailError.http(http.statusCode, message)
        }
        return data
    }

    func loadProfile() async {
        guard let data = try? await api("profile"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        emailAddress = json["emailAddress"] as? String
    }

    /// Haalt de inbox (nieuwste eerst, één rij per gesprek) opnieuw op.
    func reload() async {
        guard state == .signedIn, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let listData = try await api("messages", query: [URLQueryItem(name: "labelIds", value: "INBOX"),
                                                              URLQueryItem(name: "maxResults", value: Self.inboxPageSize)])
            var seenThreads = Set<String>()
            let refs = GmailAPI.messageRefs(fromListJSON: listData).refs.filter { seenThreads.insert($0.threadID).inserted }

            let summaries = await withTaskGroup(of: (Int, GmailMessageSummary?).self) { group -> [GmailMessageSummary] in
                for (index, ref) in refs.enumerated() {
                    group.addTask { (index, await self.summary(forMessageID: ref.id)) }
                }
                var found: [(Int, GmailMessageSummary)] = []
                for await (index, summary) in group {
                    if let summary { found.append((index, summary)) }
                }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            messages = summaries
            lastError = nil
        } catch {
            if state == .signedIn { lastError = error.localizedDescription }
        }
    }

    private func summary(forMessageID id: String) async -> GmailMessageSummary? {
        let query = [URLQueryItem(name: "format", value: "metadata"),
                     URLQueryItem(name: "metadataHeaders", value: "From"),
                     URLQueryItem(name: "metadataHeaders", value: "Subject")]
        guard let data = try? await api("messages/\(id)", query: query) else { return nil }
        return GmailAPI.summary(fromMessageJSON: data)
    }

    private func rawMessage(id: String) async throws -> Data {
        let data = try await api("messages/\(id)", query: [URLQueryItem(name: "format", value: "raw")])
        guard let raw = GmailAPI.rawMessage(fromJSON: data) else { throw GmailError.invalidResponse }
        return raw
    }

    /// Archiveert het hele gesprek (haalt het label INBOX weg), zoals de knop "Archiveren" in Gmail.
    private func archive(threadID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["INBOX"]])
        _ = try await api("threads/\(threadID)/modify", method: "POST", body: body)
    }

    // MARK: Naar het board slepen

    /// Maakt van een gesleepte Gmail-mail een kaart in `column` en archiveert hem daarna in Gmail.
    /// Archiveren gebeurt pas als de kaart is opgeslagen; mislukt het, dan blijft de kaart staan en de mail in de inbox.
    func importDropped(_ payload: GmailDragPayload, column: BoardColumn,
                       context: ModelContext, appState: AppState) async {
        guard !busyMessageIDs.contains(payload.messageID) else { return }
        busyMessageIDs.insert(payload.messageID)
        defer { busyMessageIDs.remove(payload.messageID) }

        let raw: Data
        do {
            raw = try await rawMessage(id: payload.messageID)
        } catch {
            appState.showToast("Mail ophalen uit Gmail mislukt: \(error.localizedDescription)", seconds: 5)
            return
        }

        let card = BoardService.addMail(EMLParser.parse(raw), column: column, in: context)
        // De titel van een nieuwe mailkaart wil je altijd nakijken (zelfde gedrag als bij een gesleept .eml-bestand).
        InlineEditing.pendingEditID = card.id
        let sender = card.clientLabel ?? "onbekende afzender"
        let columnTitle = BoardService.title(of: BoardService.resolve(column, in: context), in: context)

        do {
            try await archive(threadID: payload.threadID)
            messages.removeAll { $0.threadID == payload.threadID }
            appState.showToast("Mail van \(sender) toegevoegd aan \(columnTitle) en gearchiveerd in Gmail", seconds: 3)
        } catch {
            appState.showToast("Kaart gemaakt, maar archiveren in Gmail mislukte: \(error.localizedDescription)", seconds: 6)
        }
    }

    /// De sleeplading van één rij in het paneel.
    func dragProvider(for message: GmailMessageSummary) -> NSItemProvider {
        let payload = GmailDragPayload(messageID: message.id, threadID: message.threadID)
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
    static func handle(providers: [NSItemProvider], column: BoardColumn,
                       context: ModelContext, appState: AppState) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
                Task { @MainActor in
                    await GmailSession.shared.importDropped(payload, column: column, context: context, appState: appState)
                }
            }
        }
        return true
    }
}
