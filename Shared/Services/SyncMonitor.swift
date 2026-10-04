import CoreData
import Foundation
import Observation

/// Houdt bij wat de iCloud-synchronisatie (CloudKit) laatst deed, voor de diagnose in Voorkeuren › Overig.
/// SwiftData gebruikt onder de motorkap NSPersistentCloudKitContainer; die meldt elke setup, import en export.
@Observable
final class SyncMonitor: @unchecked Sendable {
    static let shared = SyncMonitor()

    struct Entry: Equatable {
        var date: Date
        var succeeded: Bool
        var error: String?
    }

    private(set) var setup: Entry?
    private(set) var imported: Entry?
    private(set) var exported: Entry?

    @ObservationIgnored private var observing = false

    /// Moet vóór het aanmaken van de container worden aangeroepen, anders mist de eerste melding.
    func start() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                               object: nil, queue: .main) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate else { return }   // alleen afgeronde gebeurtenissen
            let entry = Entry(date: end, succeeded: event.succeeded, error: event.error.map { String(describing: $0) })
            switch event.type {
            case .setup:  self?.setup = entry
            case .import: self?.imported = entry
            case .export: self?.exported = entry
            @unknown default: break
            }
        }
    }
}
