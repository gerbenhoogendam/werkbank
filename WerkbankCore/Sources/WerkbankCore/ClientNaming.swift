import Foundation

public struct ClientResolution: Equatable {
    public var name: String
    /// Registreerbaar domein van de afzender, bijv. `studio-noord.nl`.
    public var registrableDomain: String
    /// Domein waarvoor een logo gezocht moet worden. `nil` bij freemail (geen logo).
    public var logoDomain: String?
    public var isFreemail: Bool
}

public enum ClientNaming {
    public static let freemailDomains: Set<String> = [
        "gmail.com", "outlook.com", "hotmail.com", "live.nl", "icloud.com", "me.com",
        "yahoo.com", "ziggo.nl", "kpnmail.nl", "hetnet.nl", "planet.nl", "xs4all.nl",
    ]

    /// Tweeledige extensies waarbij het registreerbare domein drie labels lang is (`bedrijf.co.uk`).
    static let twoLevelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "co.nz", "org.nz", "co.jp", "co.za",
        "com.br", "com.tr", "com.mx", "com.ar", "co.in", "co.kr", "com.cn", "com.hk", "com.sg",
    ]

    /// Domeinnaam uit een e-mailadres, in kleine letters.
    public static func domain(ofAddress address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let host = address[address.index(after: at)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " >.\t"))
            .lowercased()
        return host.isEmpty ? nil : host
    }

    /// `mail.studio-noord.nl` → `studio-noord.nl`; `shop.bedrijf.co.uk` → `bedrijf.co.uk`.
    public static func registrableDomain(of host: String) -> String {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoLevelSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// `studio-noord.nl` → `Studio Noord`: het label vóór de extensie, `-`/`_` als spatie,
    /// elk woord met hoofdletter.
    public static func name(fromRegistrableDomain domain: String) -> String {
        let label = domain.split(separator: ".").first.map(String.init) ?? domain
        let words = label
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
        return words.joined(separator: " ")
    }

    /// Bepaalt de klant bij een afzender.
    /// 1. Koppeltabel (domein → klant), eerst het volledige domein, dan het registreerbare domein.
    /// 2. Bij freemail de weergavenaam van de afzender, zonder logo.
    /// 3. Anders de naam afgeleid uit het registreerbare domein.
    ///
    /// - Parameter mapping: sleutels in kleine letters.
    public static func resolve(displayName: String?,
                               address: String?,
                               mapping: [String: String] = [:]) -> ClientResolution? {
        guard let address, let host = domain(ofAddress: address) else { return nil }
        let registrable = registrableDomain(of: host)
        let isFreemail = freemailDomains.contains(registrable)

        if let mapped = mapping[host] ?? mapping[registrable],
           !mapped.trimmingCharacters(in: .whitespaces).isEmpty {
            return ClientResolution(name: mapped, registrableDomain: registrable,
                                    logoDomain: isFreemail ? nil : registrable, isFreemail: isFreemail)
        }

        if isFreemail {
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmed.isEmpty ? (address.split(separator: "@").first.map(String.init) ?? address) : trimmed
            return ClientResolution(name: name, registrableDomain: registrable,
                                    logoDomain: nil, isFreemail: true)
        }

        return ClientResolution(name: name(fromRegistrableDomain: registrable),
                                registrableDomain: registrable, logoDomain: registrable, isFreemail: false)
    }
}
