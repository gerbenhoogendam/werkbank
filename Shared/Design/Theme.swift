import CoreText
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Kleur per weergave

/// Een kleur voor licht en voor donker, als hex. De dekking hoort bij het thema (schaduw), niet bij een eigen kleur.
struct ThemeColor: Equatable, Hashable {
    var light: UInt32
    var dark: UInt32
    var lightOpacity: CGFloat = 1
    var darkOpacity: CGFloat = 1

    init(_ light: UInt32, _ dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.light = light
        self.dark = dark
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
    }

    var color: Color { Color.dynamic(light: light, dark: dark, lightOpacity: lightOpacity, darkOpacity: darkOpacity) }

    /// sRGB-hex van een kleur uit een kleurkiezer.
    static func hex(of color: Color) -> UInt32? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        #endif
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

// MARK: - Rollen

/// Waar een kleur voor dient. De ruwe waarde is ook de sleutel van een eigen kleur in de voorkeuren.
enum ThemeRole: String, CaseIterable, Identifiable {
    case window, mail, mailHeader, board, column, card, agenda, timeList, surface, surfaceAlt
    case text, textSecondary, textTertiary, fieldLabel
    case separator, checkbox, accent, selection, running, today, deadline, tag, tagText, shadow

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case backgrounds, text, accents
        var id: String { rawValue }
        var title: String {
            switch self {
            case .backgrounds: "Achtergronden"
            case .text: "Tekst"
            case .accents: "Lijnen en accenten"
            }
        }
        var roles: [ThemeRole] { ThemeRole.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .window, .mail, .mailHeader, .board, .column, .card, .agenda, .timeList, .surface, .surfaceAlt: .backgrounds
        case .text, .textSecondary, .textTertiary, .fieldLabel: .text
        default: .accents
        }
    }

    var title: String {
        switch self {
        case .window: "Venster"
        case .mail: "Mail"
        case .mailHeader: "Kop van mail"
        case .board: "Bord"
        case .column: "Kolom"
        case .card: "Kaart"
        case .agenda: "Agenda"
        case .timeList: "Tijd schrijven"
        case .surface: "Panelen"
        case .surfaceAlt: "Vlakken"
        case .text: "Tekst"
        case .textSecondary: "Tekst 2"
        case .textTertiary: "Tekst 3"
        case .fieldLabel: "Veldlabel"
        case .separator: "Haarlijn"
        case .checkbox: "Rand van vinkjes"
        case .accent: "Accent"
        case .selection: "Selectie"
        case .running: "Loopt nu"
        case .today: "Vandaag"
        case .deadline: "Te laat"
        case .tag: "Label"
        case .tagText: "Labeltekst"
        case .shadow: "Schaduw"
        }
    }
}

// MARK: - Thema

/// De vormgeving naast de kleuren (kolomkoppen, kaarten, agenda, mail, tijdlijst, timerpil), zoals in de schetsen.
enum ThemeLook: String {
    case standaard, wandklok, tischsuper, principes, sneeuwwitje, rekenmachine, drukproef, spark

    /// Losse vlakken met tussenruimte op de vensterkleur (Drukproef).
    var panelGap: CGFloat { self == .drukproef ? 8 : 0 }
    var panelRadius: CGFloat { self == .drukproef ? 14 : 0 }
}

struct WerkbankTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let colors: [ThemeRole: ThemeColor]
    /// Familienaam van de letter; nil is de systeemletter.
    var fontFamily: String?
    /// Letter voor cijfers (timer, duur); nil is dezelfde als de tekst.
    var numberFamily: String?
    var cardRadius: CGFloat = 10
    /// Het hele mailpaneel donker, ook in de lichte weergave.
    var darkMail = false
    /// Alleen de kop van het mailpaneel (mailboxen) donker.
    var darkMailHeader = false

    func color(_ role: ThemeRole) -> ThemeColor { colors[role] ?? Self.standaard.colors[role] ?? ThemeColor(0, 0) }

    var look: ThemeLook { ThemeLook(rawValue: id) ?? .standaard }

    static let all: [WerkbankTheme] = [standaard, wandklok, tischsuper, principes, sneeuwwitje, rekenmachine, drukproef, spark]

    static func named(_ id: String) -> WerkbankTheme { all.first { $0.id == id } ?? standaard }
}

extension WerkbankTheme {
    /// De oorspronkelijke kleuren van Werkbank.
    static let standaard = WerkbankTheme(id: "standaard", name: "Standaard", colors: [
        .window: ThemeColor(0xFFFFFF, 0x1E1F22), .mail: ThemeColor(0xF4F5F7, 0x252629),
        .mailHeader: ThemeColor(0xF4F5F7, 0x252629), .board: ThemeColor(0xFFFFFF, 0x1E1F22),
        .column: ThemeColor(0xF4F5F7, 0x252629), .card: ThemeColor(0xFFFFFF, 0x1E1F22),
        .agenda: ThemeColor(0xFFFFFF, 0x1E1F22), .timeList: ThemeColor(0xFFFFFF, 0x1E1F22),
        .surface: ThemeColor(0xFFFFFF, 0x1E1F22), .surfaceAlt: ThemeColor(0xF4F5F7, 0x252629),
        .text: ThemeColor(0x1C1C1E, 0xF2F2F4), .textSecondary: ThemeColor(0x8A8A8F, 0x8E8E93),
        .textTertiary: ThemeColor(0xB8B8BD, 0x5C5C61), .fieldLabel: ThemeColor(0x1A8CFF, 0x1A8CFF),
        .separator: ThemeColor(0xE6E6EA, 0x34353A), .checkbox: ThemeColor(0xC4C4C9, 0x5E5F64),
        .accent: ThemeColor(0x1A7CF9, 0x3D8EFF), .selection: ThemeColor(0xD8E7FE, 0x27416B),
        .running: ThemeColor(0x30B550, 0x3CCB5F), .today: ThemeColor(0xFFD02B, 0xFFD02B),
        .deadline: ThemeColor(0xF2463C, 0xFF5A50), .tag: ThemeColor(0xEDEDF0, 0x38393E),
        .tagText: ThemeColor(0x6E6E73, 0xB0B0B5), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0.10, darkOpacity: 0.45),
    ])

    /// Braun-wandklok en BN0171: wit, steengrijs, grafiet; geel alleen voor wat nu loopt.
    static let wandklok = WerkbankTheme(id: "wandklok", name: "Wandklok", colors: [
        .window: ThemeColor(0xE9E9E9, 0x0F0F0F), .mail: ThemeColor(0xF2F4F5, 0x171717),
        .mailHeader: ThemeColor(0xF2F4F5, 0x171717), .board: ThemeColor(0xE9E9E9, 0x0F0F0F),
        .column: ThemeColor(0xF2F4F5, 0x1B1B1B), .card: ThemeColor(0xFFFFFF, 0x242424),
        .agenda: ThemeColor(0xFFFFFF, 0x171717), .timeList: ThemeColor(0xFFFFFF, 0x171717),
        .surface: ThemeColor(0xFFFFFF, 0x1B1B1B), .surfaceAlt: ThemeColor(0xF2F4F5, 0x242424),
        .text: ThemeColor(0x1C1C1C, 0xF2F2F2), .textSecondary: ThemeColor(0x636260, 0xA3A3A3),
        .textTertiary: ThemeColor(0x75706A, 0x8E8E8E), .fieldLabel: ThemeColor(0x3C3C3C, 0xD9D9D9),
        .separator: ThemeColor(0xE2E1E0, 0x2C2C2C), .checkbox: ThemeColor(0xC9C7C3, 0x4A4A4A),
        .accent: ThemeColor(0x3C3C3C, 0x7A7A7A), .selection: ThemeColor(0xE6E5E2, 0x2E2E2E),
        .running: ThemeColor(0xDEB442, 0xF0C030), .today: ThemeColor(0xF0C030, 0xF0C030),
        .deadline: ThemeColor(0xD42F14, 0xFF6A4D), .tag: ThemeColor(0xECECEB, 0x2C2C2C),
        .tagText: ThemeColor(0x636260, 0xA3A3A3), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0.07, darkOpacity: 0.45),
    ], fontFamily: "Helvetica Neue", cardRadius: 12)

    /// Braun RT 20 en de platenspeler, plat: warm grijs, antraciet mailpaneel, oranje en teak.
    static let tischsuper = WerkbankTheme(id: "tischsuper", name: "Tischsuper", colors: [
        .window: ThemeColor(0xE0E0E0, 0x161616), .mail: ThemeColor(0x1C1C1C, 0x1C1C1C),
        .mailHeader: ThemeColor(0x1C1C1C, 0x1C1C1C), .board: ThemeColor(0xE0E0E0, 0x161616),
        .column: ThemeColor(0xD6D5D2, 0x141414), .card: ThemeColor(0xF4F4F3, 0x2C2C2C),
        .agenda: ThemeColor(0xEEEEED, 0x1C1C1C), .timeList: ThemeColor(0xEEEEED, 0x1C1C1C),
        .surface: ThemeColor(0xEEEEED, 0x1C1C1C), .surfaceAlt: ThemeColor(0xE4E3E0, 0x262626),
        .text: ThemeColor(0x1C1C1C, 0xEEEEED), .textSecondary: ThemeColor(0x5E5C59, 0xA8A6A2),
        .textTertiary: ThemeColor(0x6B6966, 0x8F8C88), .fieldLabel: ThemeColor(0x9A5526, 0xC27A44),
        .separator: ThemeColor(0xC8C6C2, 0x333333), .checkbox: ThemeColor(0x8F8C88, 0x5A5856),
        .accent: ThemeColor(0xBA440B, 0xD9530E), .selection: ThemeColor(0xF3D9C9, 0x4A2E1E),
        .running: ThemeColor(0xFE6217, 0xFE6217), .today: ThemeColor(0xFE6217, 0xFE6217),
        .deadline: ThemeColor(0xB5301F, 0xFF6A55), .tag: ThemeColor(0xE4E3E0, 0x303030),
        .tagText: ThemeColor(0x5E5C59, 0xA8A6A2), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0, darkOpacity: 0),
    ], fontFamily: "Helvetica Neue", cardRadius: 8, darkMail: true)

    /// De tien principes: zwart, haarlijnen en drie kleuren met elk één betekenis.
    static let principes = WerkbankTheme(id: "principes", name: "Principes", colors: [
        .window: ThemeColor(0xEDEDED, 0x000000), .mail: ThemeColor(0xF7F7F7, 0x000000),
        .mailHeader: ThemeColor(0xF7F7F7, 0x000000), .board: ThemeColor(0xEDEDED, 0x000000),
        .column: ThemeColor(0xEDEDED, 0x000000), .card: ThemeColor(0xFFFFFF, 0x1E1E1E),
        .agenda: ThemeColor(0xEDEDED, 0x000000), .timeList: ThemeColor(0xEDEDED, 0x000000),
        .surface: ThemeColor(0xFFFFFF, 0x141414), .surfaceAlt: ThemeColor(0xF2F2F2, 0x1E1E1E),
        .text: ThemeColor(0x000000, 0xFFFFFF), .textSecondary: ThemeColor(0x555555, 0xA6A6A6),
        .textTertiary: ThemeColor(0x666666, 0x8C8C8C), .fieldLabel: ThemeColor(0x0C5296, 0x5B9BE0),
        .separator: ThemeColor(0xCFCFCF, 0x2E2E2E), .checkbox: ThemeColor(0x666666, 0x8C8C8C),
        .accent: ThemeColor(0x0C5296, 0x3A78C4), .selection: ThemeColor(0xD6E4F3, 0x0E2A4A),
        .running: ThemeColor(0xF7C001, 0xF7C001), .today: ThemeColor(0xF7C001, 0xF7C001),
        .deadline: ThemeColor(0xD7140F, 0xFF5A4F), .tag: ThemeColor(0xE4E4E4, 0x262626),
        .tagText: ThemeColor(0x555555, 0xA6A6A6), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0, darkOpacity: 0),
    ], fontFamily: "Helvetica Neue", cardRadius: 18)

    /// Braun SK 4: wit gelakt staal, lichthout en glas.
    static let sneeuwwitje = WerkbankTheme(id: "sneeuwwitje", name: "Sneeuwwitje", colors: [
        .window: ThemeColor(0xECE9E3, 0x1B1A18), .mail: ThemeColor(0xF4F2EE, 0x22201E),
        .mailHeader: ThemeColor(0xF4F2EE, 0x22201E), .board: ThemeColor(0xECE9E3, 0x1B1A18),
        .column: ThemeColor(0xF4F2EE, 0x23211F), .card: ThemeColor(0xFFFFFF, 0x262421),
        .agenda: ThemeColor(0xF7F5F1, 0x1F1D1B), .timeList: ThemeColor(0xF7F5F1, 0x1F1D1B),
        .surface: ThemeColor(0xFFFFFF, 0x262421), .surfaceAlt: ThemeColor(0xF1EEE9, 0x2B2926),
        .text: ThemeColor(0x222220, 0xF1EEE8), .textSecondary: ThemeColor(0x5E5C57, 0xA8A39A),
        .textTertiary: ThemeColor(0x6E6B65, 0x97928A), .fieldLabel: ThemeColor(0x8A6236, 0xC9A574),
        .separator: ThemeColor(0xDEDAD2, 0x34312D), .checkbox: ThemeColor(0xA9A49B, 0x5E5A54),
        .accent: ThemeColor(0x4A4A48, 0x85817A), .selection: ThemeColor(0xEFE4D3, 0x3A3128),
        .running: ThemeColor(0xD6B588, 0xC9A574), .today: ThemeColor(0xD6B588, 0xC9A574),
        .deadline: ThemeColor(0xC0392B, 0xE8705F), .tag: ThemeColor(0xE7E3DC, 0x2B2926),
        .tagText: ThemeColor(0x5E5C57, 0xA8A39A), .shadow: ThemeColor(0x3C2D14, 0x000000, lightOpacity: 0.07, darkOpacity: 0.4),
    ], fontFamily: "Avenir Next", cardRadius: 14)

    /// Braun ET 66: warm zwart, ronde toetsen, een grijsgroen schermpje en één gele toets.
    static let rekenmachine = WerkbankTheme(id: "rekenmachine", name: "Rekenmachine", colors: [
        .window: ThemeColor(0xE8E5E0, 0x1F1D1B), .mail: ThemeColor(0xE8E5E0, 0x1F1D1B),
        .mailHeader: ThemeColor(0xE8E5E0, 0x1F1D1B), .board: ThemeColor(0xE8E5E0, 0x1F1D1B),
        .column: ThemeColor(0xDEDAD4, 0x252220), .card: ThemeColor(0xF2EFEA, 0x2F2B28),
        .agenda: ThemeColor(0xE8E5E0, 0x1F1D1B), .timeList: ThemeColor(0xE8E5E0, 0x1F1D1B),
        .surface: ThemeColor(0xF2EFEA, 0x2A2724), .surfaceAlt: ThemeColor(0xDEDAD4, 0x252220),
        .text: ThemeColor(0x1F1D1B, 0xECE8E2), .textSecondary: ThemeColor(0x5F5A53, 0xA39C93),
        .textTertiary: ThemeColor(0x6A645C, 0x8F8880), .fieldLabel: ThemeColor(0x7A5C00, 0xF2B705),
        .separator: ThemeColor(0xD2CEC7, 0x34302C), .checkbox: ThemeColor(0x8F8880, 0x5F5A53),
        .accent: ThemeColor(0x3A3531, 0xB07F00), .selection: ThemeColor(0xEDE6D6, 0x4A4339),
        .running: ThemeColor(0xF2B705, 0xF2B705), .today: ThemeColor(0xF2B705, 0xF2B705),
        .deadline: ThemeColor(0xC4432B, 0xF0674C), .tag: ThemeColor(0xDEDAD4, 0x3A3531),
        .tagText: ThemeColor(0x5F5A53, 0xA39C93), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0.10, darkOpacity: 0.45),
    ], fontFamily: "Helvetica Neue", cardRadius: 14)

    /// Redactioneel: lichtgrijze vlakken op warm antraciet, haarlijnen en één rood.
    static let drukproef = WerkbankTheme(id: "drukproef", name: "Drukproef", colors: [
        .window: ThemeColor(0x2B2627, 0x0E0C0D), .mail: ThemeColor(0xF3F3F3, 0x1E1B1C),
        .mailHeader: ThemeColor(0xF3F3F3, 0x1E1B1C), .board: ThemeColor(0xF3F3F3, 0x1E1B1C),
        .column: ThemeColor(0xF3F3F3, 0x1E1B1C), .card: ThemeColor(0xFAFAFA, 0x262223),
        .agenda: ThemeColor(0xF3F3F3, 0x1E1B1C), .timeList: ThemeColor(0xF3F3F3, 0x1E1B1C),
        .surface: ThemeColor(0xF3F3F3, 0x1E1B1C), .surfaceAlt: ThemeColor(0xEAEAEA, 0x2A2627),
        .text: ThemeColor(0x1E1E1E, 0xF2F2F2), .textSecondary: ThemeColor(0x6B6B6B, 0x9E9999),
        .textTertiary: ThemeColor(0x6B6B6B, 0x8A8585), .fieldLabel: ThemeColor(0x1E1E1E, 0xF2F2F2),
        .separator: ThemeColor(0xDCDCDC, 0x34302F), .checkbox: ThemeColor(0xC7C7C7, 0x4A4545),
        .accent: ThemeColor(0xC92E1D, 0xE0402C), .selection: ThemeColor(0xFBE0DC, 0x3A2422),
        .running: ThemeColor(0xF4402C, 0xFF5A45), .today: ThemeColor(0xF4402C, 0xFF5A45),
        .deadline: ThemeColor(0xC92E1D, 0xFF5A45), .tag: ThemeColor(0xE6E6E6, 0x2A2627),
        .tagText: ThemeColor(0x6B6B6B, 0x9E9999), .shadow: ThemeColor(0x000000, 0x000000, lightOpacity: 0, darkOpacity: 0),
    ], fontFamily: "Helvetica Neue", numberFamily: "Michroma", cardRadius: 6)

    /// Zoals de mailapp Spark: donkerblauwe kop, witte lijsten en blauw.
    static let spark = WerkbankTheme(id: "spark", name: "Spark", colors: [
        .window: ThemeColor(0xF2F2F4, 0x18181A), .mail: ThemeColor(0xFFFFFF, 0x1F1F22),
        .mailHeader: ThemeColor(0x202A3A, 0x151B24), .board: ThemeColor(0xF2F2F4, 0x18181A),
        .column: ThemeColor(0xF2F2F4, 0x18181A), .card: ThemeColor(0xFFFFFF, 0x1F1F22),
        .agenda: ThemeColor(0xFFFFFF, 0x1F1F22), .timeList: ThemeColor(0xFFFFFF, 0x1F1F22),
        .surface: ThemeColor(0xFFFFFF, 0x1F1F22), .surfaceAlt: ThemeColor(0xF2F2F4, 0x2A2A2E),
        .text: ThemeColor(0x1C1C1E, 0xF2F2F4), .textSecondary: ThemeColor(0x6B6B70, 0x98989F),
        .textTertiary: ThemeColor(0x7C7C82, 0x8A8A90), .fieldLabel: ThemeColor(0x1F6FE0, 0x3B8BFF),
        .separator: ThemeColor(0xE5E5EA, 0x2E2E32), .checkbox: ThemeColor(0xB8B8BE, 0x5A5A60),
        .accent: ThemeColor(0x1F6FE0, 0x2F80F0), .selection: ThemeColor(0xDCE9FD, 0x1E3556),
        .running: ThemeColor(0x2F7CF6, 0x3B8BFF), .today: ThemeColor(0x2370E6, 0x2370E6),
        .deadline: ThemeColor(0xD70015, 0xFF453A), .tag: ThemeColor(0xEEEEF0, 0x2E2E32),
        .tagText: ThemeColor(0x6B6B70, 0x98989F), .shadow: ThemeColor(0x0F172A, 0x000000, lightOpacity: 0.06, darkOpacity: 0.4),
    ], cardRadius: 10, darkMailHeader: true)
}

// MARK: - Opslag en de kleuren die de app gebruikt

/// Het gekozen thema met je eigen aanpassingen. Views lezen de kleuren en letters via `ThingsColor` en
/// `Font.werk`; omdat dit object waarneembaar is, tekent alles opnieuw zodra je in Voorkeuren iets wijzigt.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    enum Key {
        static let theme = "theme.id"
        static let font = "theme.font"
        static let numberFont = "theme.numberFont"
        static let size = "theme.size"
        static let colors = "theme.colors"
        static var all: [String] { [theme, font, numberFont, size, colors] }
    }

    static let defaultSize: Double = 13
    static let sizeRange: ClosedRange<Double> = 11...17

    private(set) var theme: WerkbankTheme = .standaard
    /// Eigen kleuren, per thema: thema-id → rol → kleur.
    private(set) var overrides: [String: [ThemeRole: ThemeColor]] = [:]
    /// "" = de letter van het thema, "system" = systeemletter, anders een familienaam.
    private(set) var fontChoice = ""
    private(set) var numberFontChoice = ""
    private(set) var baseSize = ThemeStore.defaultSize
    private(set) var palette: [ThemeRole: Color] = [:]
    /// De letters zoals ze nu gelden (alleen als ze op deze computer staan); bijgewerkt in `reload()`.
    private(set) var fontFamily: String?
    private(set) var numberFamily: String?

    private init() {
        Self.registerBundledFonts()
        reload()
    }

    /// Letters die met de app meekomen (Michroma voor de cijfers van Drukproef).
    private static func registerBundledFonts() {
        for name in ["Michroma-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: Lezen

    func color(_ role: ThemeRole) -> Color { palette[role] ?? theme.color(role).color }

    /// De kleur zoals hij nu geldt: je eigen kleur, anders die van het thema.
    func themeColor(_ role: ThemeRole) -> ThemeColor {
        overrides[theme.id]?[role] ?? theme.color(role)
    }

    var look: ThemeLook { theme.look }

    func isOverridden(_ role: ThemeRole) -> Bool { overrides[theme.id]?[role] != nil }
    var hasOverrides: Bool { !(overrides[theme.id] ?? [:]).isEmpty }

    var scale: CGFloat { CGFloat(baseSize / Self.defaultSize) }

    /// Letter op `size` (de maat bij grootte 13), in de letter van het thema en geschaald met de basisgrootte.
    /// Een afwijkend ontwerp (monospaced, rounded) blijft de systeemletter.
    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, numbers: Bool = false) -> Font {
        let scaled = size * scale
        guard design == .default, let family = numbers ? numberFamily : fontFamily else {
            return .system(size: scaled, weight: weight, design: design)
        }
        return Font.custom(family, size: scaled).weight(weight)
    }

    // MARK: Wijzigen

    func select(_ id: String) {
        UserDefaults.standard.set(id, forKey: Key.theme)
        reload()
    }

    func setColor(_ role: ThemeRole, light: UInt32? = nil, dark: UInt32? = nil) {
        var color = themeColor(role)
        if let light { color.light = light }
        if let dark { color.dark = dark }
        var forTheme = overrides[theme.id] ?? [:]
        forTheme[role] = color
        overrides[theme.id] = forTheme
        saveOverrides()
    }

    func reset(_ role: ThemeRole) {
        overrides[theme.id]?[role] = nil
        saveOverrides()
    }

    func resetAll() {
        overrides[theme.id] = nil
        saveOverrides()
    }

    func setFont(_ choice: String) {
        UserDefaults.standard.set(choice, forKey: Key.font)
        reload()
    }

    func setNumberFont(_ choice: String) {
        UserDefaults.standard.set(choice, forKey: Key.numberFont)
        reload()
    }

    func setBaseSize(_ size: Double) {
        UserDefaults.standard.set(min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound), forKey: Key.size)
        reload()
    }

    /// Opnieuw lezen uit de voorkeuren (bij het starten en na synchroniseren met een andere Mac).
    func reload() {
        let defaults = UserDefaults.standard
        theme = WerkbankTheme.named(defaults.string(forKey: Key.theme) ?? WerkbankTheme.standaard.id)
        fontChoice = defaults.string(forKey: Key.font) ?? ""
        numberFontChoice = defaults.string(forKey: Key.numberFont) ?? ""
        let size = defaults.double(forKey: Key.size)
        baseSize = size == 0 ? Self.defaultSize : min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        overrides = Self.decode(defaults.dictionary(forKey: Key.colors))
        let installed = Set(Self.installedFamilies)
        fontFamily = Self.resolve(fontChoice, themeDefault: theme.fontFamily, installed: installed)
        numberFamily = Self.resolve(numberFontChoice, themeDefault: theme.numberFamily, installed: installed) ?? fontFamily
        rebuild()
    }

    private func saveOverrides() {
        UserDefaults.standard.set(Self.encode(overrides), forKey: Key.colors)
        rebuild()
    }

    private func rebuild() {
        var colors: [ThemeRole: Color] = [:]
        for role in ThemeRole.allCases { colors[role] = themeColor(role).color }
        palette = colors
    }

    // MARK: Hulp

    /// Alle letterfamilies op deze computer, op naam.
    static var installedFamilies: [String] {
        #if canImport(UIKit)
        UIFont.familyNames.sorted()
        #else
        ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        #endif
    }

    private static func resolve(_ choice: String, themeDefault: String?, installed: Set<String>) -> String? {
        let name: String?
        switch choice {
        case "": name = themeDefault
        case "system": name = nil
        default: name = choice
        }
        guard let name, installed.contains(name) else { return nil }
        return name
    }

    /// Plist-vriendelijk: thema-id → rol → [licht, donker].
    private static func encode(_ overrides: [String: [ThemeRole: ThemeColor]]) -> [String: [String: [Int]]] {
        overrides.mapValues { roles in
            Dictionary(uniqueKeysWithValues: roles.map { ($0.key.rawValue, [Int($0.value.light), Int($0.value.dark)]) })
        }
    }

    private static func decode(_ stored: [String: Any]?) -> [String: [ThemeRole: ThemeColor]] {
        var result: [String: [ThemeRole: ThemeColor]] = [:]
        for (themeID, value) in stored ?? [:] {
            guard let roles = value as? [String: [Int]] else { continue }
            let base = WerkbankTheme.named(themeID)
            var decoded: [ThemeRole: ThemeColor] = [:]
            for (key, pair) in roles {
                guard let role = ThemeRole(rawValue: key), pair.count == 2 else { continue }
                var color = base.color(role)
                color.light = UInt32(truncatingIfNeeded: pair[0])
                color.dark = UInt32(truncatingIfNeeded: pair[1])
                decoded[role] = color
            }
            if !decoded.isEmpty { result[themeID] = decoded }
        }
        return result
    }
}

// MARK: - Gebruik in views

extension Font {
    /// Zoals `.system(size:weight:design:)`, maar in de letter en grootte van het thema.
    static func werk(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        ThemeStore.shared.font(size: size, weight: weight, design: design)
    }

    /// Voor cijfers (timer, duur): de cijferletter van het thema, als die er is.
    static func werkNumbers(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        ThemeStore.shared.font(size: size, weight: weight, numbers: true)
    }
}

private struct ForcedDarkScheme: ViewModifier {
    let isOn: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, isOn ? .dark : scheme)
    }
}

private struct ForcedLightScheme: ViewModifier {
    let isOn: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, isOn ? .light : scheme)
    }
}

extension View {
    /// Dit deel altijd donker tekenen (bijvoorbeeld het mailpaneel van Tischsuper), ook in de lichte weergave.
    func darkScheme(_ isOn: Bool) -> some View {
        modifier(ForcedDarkScheme(isOn: isOn))
    }

    /// Dit deel altijd licht tekenen (een geel vlak met zwarte tekst), ook in de donkere weergave.
    func lightScheme(_ isOn: Bool) -> some View {
        modifier(ForcedLightScheme(isOn: isOn))
    }
}
