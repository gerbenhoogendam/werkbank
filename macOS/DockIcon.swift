import AppKit

/// Het icoon in het Dock: Papier (het app-icoon) of Limoen/Oranje. macOS laat een app alleen het Dock-icoon
/// wisselen terwijl hij draait; Finder, Launchpad en de app-wisselaar houden Papier.
enum DockIcon: String, CaseIterable, Identifiable {
    case papier, limoen, oranje

    static let key = "dockIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .papier: "Papier"
        case .limoen: "Limoen"
        case .oranje: "Oranje"
        }
    }

    private var imageName: String? {
        switch self {
        case .papier: nil
        case .limoen: "DockIconLimoen"
        case .oranje: "DockIconOranje"
        }
    }

    @MainActor
    static func applyStored() {
        let stored = DockIcon(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .papier
        stored.apply()
    }

    /// Nil zet het gewone app-icoon terug; de teller met ongelezen mail blijft staan.
    @MainActor
    func apply() {
        NSApp.applicationIconImage = imageName.flatMap { NSImage(named: $0) }
    }
}
