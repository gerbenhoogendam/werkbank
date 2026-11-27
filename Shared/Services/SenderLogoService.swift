import Foundation
import WerkbankCore

/// Logo van de afzender, uit de website achter het domein van het mailadres: eerst de iconen die de site zelf
/// opgeeft (apple-touch-icon, groot icoon), daarna de Google-favicondienst. Te kleine en standaardicoontjes
/// (WordPress en dergelijke) en freemail-domeinen leveren niets op; dan blijft de letter staan.
actor SenderLogoService {
    static let shared = SenderLogoService()

    private var memory: [String: Data] = [:]
    private var inflight: [String: Task<Data?, Never>] = [:]
    /// Niets gevonden: een week niet opnieuw proberen.
    private static let retryAfter: TimeInterval = 7 * 24 * 3600

    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SenderLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func logo(forAddress address: String) async -> Data? {
        guard let host = ClientNaming.domain(ofAddress: address) else { return nil }
        let domain = ClientNaming.registrableDomain(of: host)
        guard !ClientNaming.freemailDomains.contains(domain) else { return nil }
        if let data = memory[domain] { return data }

        let file = directory.appendingPathComponent(domain.replacingOccurrences(of: "/", with: "_"))
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           let data = try? Data(contentsOf: file) {
            if !data.isEmpty {
                memory[domain] = data
                return data
            }
            // Leeg bestand = eerder niets gevonden.
            if let date = attributes[.modificationDate] as? Date, Date().timeIntervalSince(date) < Self.retryAfter { return nil }
        }
        if let running = inflight[domain] { return await running.value }

        let task = Task<Data?, Never> { await self.find(domain: domain) }
        inflight[domain] = task
        let result = await task.value
        inflight[domain] = nil
        try? (result ?? Data()).write(to: file, options: .atomic)
        if let result { memory[domain] = result }
        return result
    }

    // MARK: Zoeken

    private func find(domain: String) async -> Data? {
        await SiteIconFinder.find(domain: domain)
    }
}
