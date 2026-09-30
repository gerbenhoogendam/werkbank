//
//  ThingsTheme.swift
//  Design tokens afgeleid van Things-Design.md
//
//  Doelplatformen: iOS 17+ / macOS 14+ (SwiftUI)
//  Let op: alle kleur-, maat- en animatiewaarden zijn BENADERINGEN (zie Things-Design.md §4–§6, §10).
//  Meet ze na met Digital Color Meter en pas ze hier op één plek aan.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

// MARK: - Kleurhulpmiddelen

extension PlatformColor {
    /// Maakt een sRGB-kleur uit een hexwaarde, bijv. 0x1A7CF9.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        #if canImport(UIKit)
        self.init(red: r, green: g, blue: b, alpha: alpha)
        #else
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
        #endif
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Kleur die automatisch meeschakelt met licht/donker.
    static func dynamic(light: UInt32, dark: UInt32,
                        lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkOpacity)
                : NSColor(hex: light, alpha: lightOpacity)
        })
        #endif
    }
}

// MARK: - Kleurtokens (Things-Design.md §5)

enum ThingsColor {
    // Achtergronden
    static let backgroundContent = Color.dynamic(light: 0xFFFFFF, dark: 0x1E1F22)
    static let backgroundSidebar = Color.dynamic(light: 0xF4F5F7, dark: 0x252629)
    static let cardShadow        = Color.dynamic(light: 0x000000, dark: 0x000000,
                                                 lightOpacity: 0.10, darkOpacity: 0.45)

    // Tekst
    static let textPrimary   = Color.dynamic(light: 0x1C1C1E, dark: 0xF2F2F4)
    static let textSecondary = Color.dynamic(light: 0x8A8A8F, dark: 0x8E8E93)
    static let textTertiary  = Color.dynamic(light: 0xB8B8BD, dark: 0x5C5C61)

    // Structuur en interactie
    static let separator      = Color.dynamic(light: 0xE6E6EA, dark: 0x34353A)
    static let accent         = Color.dynamic(light: 0x1A7CF9, dark: 0x3D8EFF)
    static let selection      = Color.dynamic(light: 0xD8E7FE, dark: 0x27416B)
    static let checkboxStroke = Color.dynamic(light: 0xC4C4C9, dark: 0x5E5F64)

    // Betekeniskleuren
    static let deadline = Color.dynamic(light: 0xF2463C, dark: 0xFF5A50)
    static let today    = Color(hex: 0xFFD02B)
    static let evening  = Color.dynamic(light: 0x5B6CD9, dark: 0x7E8CF0)

    // Tags
    static let tagBackground = Color.dynamic(light: 0xEDEDF0, dark: 0x38393E)
    static let tagText       = Color.dynamic(light: 0x6E6E73, dark: 0xB0B0B5)

    // Lijstkleuren (§2.1)
    static let inbox    = Color(hex: 0x1A8CFF)
    static let upcoming = Color(hex: 0xF2463C)
    static let anytime  = Color(hex: 0x39B0A6)
    static let someday  = Color(hex: 0xD9BD7A)
    static let logbook  = Color(hex: 0x5BBF5A)
    static let trash    = Color(hex: 0x8E8E93)
}

// MARK: - Maatvoering (Things-Design.md §4.4)

enum ThingsMetrics {
    static let grid: CGFloat = 4

    #if os(macOS)
    static let contentPadding: CGFloat   = 36
    static let rowHeight: CGFloat        = 34
    static let contentMaxWidth: CGFloat  = 700
    static let sidebarWidth: CGFloat     = 250
    #else
    static let contentPadding: CGFloat   = 20
    static let rowHeight: CGFloat        = 44
    static let contentMaxWidth: CGFloat  = .infinity
    static let sidebarWidth: CGFloat     = 320   // iPad
    #endif

    static let checkboxSize: CGFloat      = 16
    static let checkboxRadius: CGFloat    = 4
    static let checkboxTitleGap: CGFloat  = 12
    static let minTapTarget: CGFloat      = 44

    static let cardRadius: CGFloat        = 10
    static let tagRadius: CGFloat         = 4
    static let selectionRadius: CGFloat   = 6

    static let magicPlusSize: CGFloat     = 56
    static let magicPlusInset: CGFloat    = 20

    static let headingTopSpacing: CGFloat    = 24
    static let headingBottomSpacing: CGFloat = 8
}

// MARK: - Typografie (Things-Design.md §6)

/// Tekststijlen met Dynamic Type op iOS (via @ScaledMetric). Op macOS zijn de maten vast.
enum ThingsTextStyle {
    case listTitle, heading, todoTitle, todoTitleOpen, notes, metadata,
         tag, sidebarItem, sidebarArea, upcomingDay, upcomingWeekday

    var size: CGFloat {
        #if os(macOS)
        switch self {
        case .listTitle:       return 24
        case .heading:         return 13
        case .todoTitle:       return 14
        case .todoTitleOpen:   return 15
        case .notes:           return 13
        case .metadata:        return 11.5
        case .tag:             return 11
        case .sidebarItem:     return 13.5
        case .sidebarArea:     return 13.5
        case .upcomingDay:     return 22
        case .upcomingWeekday: return 13
        }
        #else
        switch self {
        case .listTitle:       return 28
        case .heading:         return 15
        case .todoTitle:       return 17
        case .todoTitleOpen:   return 17
        case .notes:           return 15
        case .metadata:        return 13
        case .tag:             return 12
        case .sidebarItem:     return 17
        case .sidebarArea:     return 17
        case .upcomingDay:     return 28
        case .upcomingWeekday: return 15
        }
        #endif
    }

    var weight: Font.Weight {
        switch self {
        case .listTitle, .upcomingDay:     return .bold
        case .heading, .sidebarArea:       return .semibold
        case .todoTitleOpen, .tag:         return .medium
        default:                           return .regular
        }
    }

    /// Bepaalt hoe de stijl meeschaalt met Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .listTitle, .upcomingDay:          return .title
        case .heading, .notes, .upcomingWeekday: return .subheadline
        case .metadata:                          return .footnote
        case .tag:                               return .caption
        default:                                 return .body
        }
    }
}

private struct ThingsFontModifier: ViewModifier {
    let style: ThingsTextStyle
    @ScaledMetric private var size: CGFloat

    init(_ style: ThingsTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: style.weight))
    }
}

extension View {
    /// Past een Things-tekststijl toe, inclusief Dynamic Type.
    func thingsFont(_ style: ThingsTextStyle) -> some View {
        modifier(ThingsFontModifier(style))
    }
}

// MARK: - Beweging (Things-Design.md §10)

/// Alle animaties respecteren Reduce Motion: dan crossfade in plaats van beweging.
enum ThingsMotion {
    /// To-do uit- en inklappen.
    static func expand(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85)
    }

    /// Checkbox afvinken.
    static func check(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.15, dampingFraction: 0.6)
    }

    /// Herordenen van rijen.
    static let reorder: Animation = .easeOut(duration: 0.2)

    /// Overgang voor inline uitklappende inhoud.
    static func expandTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }
}

// MARK: - Kaartstijl (geopende to-do, "wit vel papier")

private struct ThingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                    .fill(ThingsColor.backgroundContent)
                    .shadow(color: ThingsColor.cardShadow, radius: 10, x: 0, y: 3)
            )
    }
}

extension View {
    func thingsCard() -> some View { modifier(ThingsCardModifier()) }
}
