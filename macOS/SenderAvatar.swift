import AppKit
import SwiftUI
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

/// Rond avatar bij een mail: het logo van de afzender als dat er is, anders de eerste letter.
struct SenderAvatar: View {
    let name: String
    let address: String
    var isSent = false
    var size: CGFloat = 30

    @State private var logo: NSImage?

    var body: some View {
        ZStack {
            if let logo {
                Circle().fill(Color.white)
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                Circle().fill(isSent ? ThingsColor.accent : ThingsColor.textTertiary.opacity(0.5))
                Text(String(name.prefix(1)).uppercased())
                    .font(.werk(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ThingsColor.separator.opacity(logo == nil ? 0 : 1)))
        .task(id: address) {
            logo = nil
            guard !address.isEmpty, let data = await SenderLogoService.shared.logo(forAddress: address) else { return }
            logo = NSImage(data: data)
        }
        .accessibilityHidden(true)
    }
}
