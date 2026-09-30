import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Uiterlijk van de app: automatisch (systeem), licht of donker.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Automatisch"
        case .light:  return "Licht"
        case .dark:   return "Donker"
        }
    }

    /// `nil` = het systeem bepaalt.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    init(stored raw: String?) {
        self = raw.flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    #if os(macOS)
    /// Zet het uiterlijk voor de hele app (alle vensters, het menubalkpaneel en de snelle invoer).
    @MainActor
    func applyToApp() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func applyStored() {
        AppearanceSetting(stored: UserDefaults.standard.string(forKey: SettingsKey.appearance)).applyToApp()
    }
    #endif
}

/// Grootte van het zwevende timerpaneel (macOS).
enum MiniTimerSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:  return "Klein"
        case .medium: return "Medium"
        case .large:  return "Groot"
        }
    }

    init(stored raw: String?) {
        self = raw.flatMap(MiniTimerSize.init(rawValue:)) ?? .small
    }

    var width: CGFloat { switch self { case .small: return 260; case .medium: return 340; case .large: return 450 } }
    var height: CGFloat { switch self { case .small: return 44; case .medium: return 62; case .large: return 88 } }
    var timeFont: CGFloat { switch self { case .small: return 20; case .medium: return 30; case .large: return 44 } }
    var titleFont: CGFloat { switch self { case .small: return 11; case .medium: return 13; case .large: return 17 } }
    var buttonSize: CGFloat { switch self { case .small: return 26; case .medium: return 36; case .large: return 52 } }
    var dot: CGFloat { switch self { case .small: return 8; case .medium: return 10; case .large: return 14 } }
    var gap: CGFloat { switch self { case .small: return 8; case .medium: return 10; case .large: return 14 } }
}
