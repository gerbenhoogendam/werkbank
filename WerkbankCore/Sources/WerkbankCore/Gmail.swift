import Foundation

// MARK: - Base64url

public enum Base64URL {
    /// Decodeert base64url (RFC 4648 §5, zoals de Gmail API het levert), met of zonder padding.
    public static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }

    /// Codeert zonder padding (nodig voor de PKCE-challenge).
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Berichten uit de Gmail API

/// Eén mail in de lijst van het Gmail-paneel.
public struct GmailMessageSummary: Equatable, Identifiable {
    public var id: String
    public var threadID: String
    public var fromName: String?
    public var fromAddress: String?
    public var subject: String
    public var snippet: String
    public var date: Date?
    public var isUnread: Bool

    public init(id: String, threadID: String, fromName: String? = nil, fromAddress: String? = nil,
                subject: String, snippet: String = "", date: Date? = nil, isUnread: Bool = false) {
        self.id = id
        self.threadID = threadID
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.subject = subject
        self.snippet = snippet
        self.date = date
        self.isUnread = isUnread
    }

    /// Naam van de afzender, anders het adres.
    public var senderDisplay: String {
        if let fromName, !fromName.isEmpty { return fromName }
        return fromAddress ?? "Onbekende afzender"
    }
}

/// Wat bij het slepen van het Gmail-paneel naar het board meegaat.
public struct GmailDragPayload: Codable, Equatable {
    public var messageID: String
    public var threadID: String

    public init(messageID: String, threadID: String) {
        self.messageID = messageID
        self.threadID = threadID
    }
}

public enum GmailAPI {
    public struct MessageRef: Equatable {
        public var id: String
        public var threadID: String
    }

    /// Antwoord van `users.messages.list`.
    public static func messageRefs(fromListJSON data: Data) -> (refs: [MessageRef], nextPageToken: String?) {
        struct List: Decodable {
            struct Item: Decodable { let id: String; let threadId: String }
            let messages: [Item]?
            let nextPageToken: String?
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return ([], nil) }
        return ((list.messages ?? []).map { MessageRef(id: $0.id, threadID: $0.threadId) }, list.nextPageToken)
    }

    /// Antwoord van `users.messages.get` met `format=metadata` (From, Subject).
    public static func summary(fromMessageJSON data: Data) -> GmailMessageSummary? {
        struct Header: Decodable { let name: String; let value: String }
        struct Message: Decodable {
            struct Payload: Decodable { let headers: [Header]? }
            let id: String
            let threadId: String
            let labelIds: [String]?
            let snippet: String?
            let internalDate: String?
            let payload: Payload?
        }
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return nil }

        // De headers gaan door dezelfde parser als een .eml-bestand: dat decodeert ook "=?UTF-8?...?=".
        let headerText = (message.payload?.headers ?? [])
            .filter { ["from", "subject"].contains($0.name.lowercased()) }
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\r\n")
        let parsed = EMLParser.parse(headerText)

        let date = message.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        return GmailMessageSummary(id: message.id,
                                   threadID: message.threadId,
                                   fromName: parsed.fromName,
                                   fromAddress: parsed.fromAddress,
                                   subject: parsed.subject,
                                   snippet: Self.decodeEntities(message.snippet ?? ""),
                                   date: date,
                                   isUnread: message.labelIds?.contains("UNREAD") ?? false)
    }

    /// Antwoord van `users.messages.get` met `format=raw`: de complete RFC 822-mail.
    public static func rawMessage(fromJSON data: Data) -> Data? {
        struct Raw: Decodable { let raw: String? }
        guard let raw = (try? JSONDecoder().decode(Raw.self, from: data))?.raw else { return nil }
        return Base64URL.decode(raw)
    }

    /// De Gmail-snippet bevat HTML-entiteiten (`&#39;`, `&amp;`, ...).
    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

// MARK: - Google OAuth (PKCE, zonder client secret)

public enum GoogleOAuth {
    public static let scope = "https://www.googleapis.com/auth/gmail.modify"
    public static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    /// Een iOS-type client-id ("123-abc.apps.googleusercontent.com") heeft als redirect-schema het omgekeerde
    /// ("com.googleusercontent.apps.123-abc").
    public static func redirectScheme(forClientID clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    public static func redirectURI(forClientID clientID: String) -> String? {
        redirectScheme(forClientID: clientID).map { "\($0):/oauth2redirect" }
    }

    public static func authorizationURL(clientID: String, codeChallenge: String, state: String) -> URL? {
        guard let redirect = redirectURI(forClientID: clientID) else { return nil }
        var components = URLComponents(string: authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // offline + consent: zonder dat geeft Google geen refresh-token.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    /// Haalt `code` en `state` uit de redirect-URL; geeft een fout terug als Google er een meestuurde.
    public static func parseRedirect(_ url: URL) -> (code: String?, state: String?, error: String?) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return (value("code"), value("state"), value("error"))
    }

    public struct TokenResponse: Equatable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresIn: TimeInterval
    }

    public struct OAuthError: Equatable {
        public var code: String
        public var description: String?

        /// De refresh-token is ingetrokken of verlopen (bijv. na 7 dagen in de testmodus van Google).
        public var requiresNewSignIn: Bool { code == "invalid_grant" }
    }

    public static func parseTokenResponse(_ data: Data) -> TokenResponse? {
        struct Body: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return TokenResponse(accessToken: body.access_token, refreshToken: body.refresh_token,
                             expiresIn: body.expires_in ?? 3600)
    }

    public static func parseError(_ data: Data) -> OAuthError? {
        struct Body: Decodable { let error: String; let error_description: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return OAuthError(code: body.error, description: body.error_description)
    }
}
