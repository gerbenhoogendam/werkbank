import AppKit

/// Het icoon in het Dock: Papier, Limoen of Oranje. macOS laat een app alleen het Dock-icoon wisselen terwijl hij
/// draait; Finder, Launchpad en de app-wisselaar tonen het app-icoon (Papier). Ook Papier wordt hier gezet: het Dock
/// houdt anders soms een oud icoon uit de cache van macOS vast.
enum DockIcon: String, CaseIterable, Identifiable {
    case papier, limoen, oranje, blauw

    static let key = "dockIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .papier: "Papier"
        case .limoen: "Limoen"
        case .oranje: "Oranje"
        case .blauw: "Blauw"
        }
    }

    private var imageName: String {
        switch self {
        case .papier: "DockIconPapier"
        case .limoen: "DockIconLimoen"
        case .oranje: "DockIconOranje"
        case .blauw: "DockIconBlauw"
        }
    }

    @MainActor
    static func applyStored() {
        let stored = DockIcon(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .papier
        stored.apply()
    }

    /// De teller met ongelezen mail blijft staan.
    @MainActor
    func apply() {
        NSApp.applicationIconImage = NSImage(named: imageName)
    }
}
