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
