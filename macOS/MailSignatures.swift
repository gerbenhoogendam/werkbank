import Foundation
import WerkbankCore

/// Handtekening, logo en afzendernaam per mailbox (sleutel "" geldt voor alle mailboxen zonder eigen instelling).
/// Staat in UserDefaults: er zit niets geheims in.
enum MailSignatures {
    private static let htmlKey = "mail.signatureHTML"
    private static let logoKey = "mail.signatureLogo"
    private static let nameKey = "mail.senderName"
    static let defaultKey = ""

    private static func strings(_ key: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func write(_ value: String?, _ key: String, forAccount account: String, to storeKey: String) {
        var all = strings(storeKey)
        if let value, !value.isEmpty { all[account] = value } else { all[account] = nil }
        UserDefaults.standard.set(all, forKey: storeKey)
    }

    // MARK: Waarden voor het versturen (met terugval op de standaard)

    static func html(for account: String?) -> String? {
        let all = strings(htmlKey)
        let value = account.flatMap { all[$0] } ?? all[defaultKey]
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }

    static func senderName(for account: String?) -> String? {
        let all = strings(nameKey)
        return account.flatMap { all[$0] } ?? all[defaultKey]
    }

    static func logo(for account: String?) -> MailAttachment? {
        let all = UserDefaults.standard.dictionary(forKey: logoKey) as? [String: Data] ?? [:]
        guard let data = account.flatMap({ all[$0] }) ?? all[defaultKey] else { return nil }
        let (type, ext) = imageType(of: data)
        return MailAttachment(name: "logo.\(ext)", mediaType: type, data: data)
    }

    // MARK: Waarden per instelling (zonder terugval, voor Voorkeuren)

    static func ownHTML(_ key: String) -> String { strings(htmlKey)[key] ?? "" }
    static func setHTML(_ value: String, for key: String) { write(value, htmlKey, forAccount: key, to: htmlKey) }

    static func ownSenderName(_ key: String) -> String { strings(nameKey)[key] ?? "" }
    static func setSenderName(_ value: String, for key: String) { write(value, nameKey, forAccount: key, to: nameKey) }

    static func ownLogo(_ key: String) -> Data? {
        (UserDefaults.standard.dictionary(forKey: logoKey) as? [String: Data])?[key]
    }

    static func setLogo(_ data: Data?, for key: String) {
        var all = UserDefaults.standard.dictionary(forKey: logoKey) as? [String: Data] ?? [:]
        all[key] = data
        UserDefaults.standard.set(all, forKey: logoKey)
    }

    /// De handtekening zoals de ontvanger hem ziet: `cid:` wijst naar het logo als data-URL (alleen voor de weergave).
    static func previewHTML(_ html: String, logo: Data?) -> String {
        guard let logo else { return html }
        let type = imageType(of: logo).mediaType
        return html.replacingOccurrences(of: #"cid:[^"'\s>)]+"#,
                                         with: "data:\(type);base64,\(logo.base64EncodedString())",
                                         options: .regularExpression)
    }

    /// Voorbeeld voor het opstelvenster van een mailbox (met terugval op de standaard).
    static func preview(for account: String?) -> String? {
        guard let html = html(for: account) else { return nil }
        return previewHTML(html, logo: logo(for: account)?.data)
    }

    static func imageType(of data: Data) -> (mediaType: String, ext: String) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("image/png", "png") }
        if data.starts(with: [0x47, 0x49, 0x46]) { return ("image/gif", "gif") }
        return ("image/jpeg", "jpg")
    }
}
