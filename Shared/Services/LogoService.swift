import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Zoekt een klantlogo op via Google Afbeeldingen (Custom Search JSON API) en valt terug op de
/// Google-favicondienst. Resultaten worden per domein op schijf gecached.
actor LogoService {
    static let shared = LogoService()

    private var memory: [String: Data] = [:]
    private var failed: Set<String> = []
    private var inflight: [String: Task<Data?, Never>] = [:]

    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func logo(for rawDomain: String) async -> Data? {
        let domain = rawDomain.lowercased()
        if let data = memory[domain] { return data }
        if failed.contains(domain) { return nil }
        if let data = try? Data(contentsOf: cacheURL(domain)), isImage(data) {
            memory[domain] = data
            return data
        }
        if let running = inflight[domain] { return await running.value }

        let task = Task<Data?, Never> { await self.fetch(domain: domain) }
        inflight[domain] = task
        let result = await task.value
        inflight[domain] = nil

        if let result {
            memory[domain] = result
            try? result.write(to: cacheURL(domain), options: .atomic)
        } else {
            failed.insert(domain)
        }
        return result
    }

    /// Alvast ophalen wat nog niet bewaard is, een paar tegelijk (klantenlijst). Zonder de zoekdienst (die heeft een
    /// dagquotum): van de website zelf, anders het favicon. Niets gevonden: een week niet opnieuw proberen; bij gebruik
    /// gaat het dan alsnog de gewone weg.
    func prefetch(_ domains: [String]) async {
        let pending = domains.map { $0.lowercased() }.filter { domain in
            memory[domain] == nil && !failed.contains(domain) && !isCached(domain) && !recentlyMissed(domain)
        }
        await withTaskGroup(of: Void.self) { group in
            var queue = pending.makeIterator()
            for _ in 0..<4 {
                guard let domain = queue.next() else { break }
                group.addTask { await self.prefetchOne(domain) }
            }
            while await group.next() != nil {
                guard let domain = queue.next() else { continue }
                group.addTask { await self.prefetchOne(domain) }
            }
        }
    }

    private func prefetchOne(_ domain: String) async {
        guard inflight[domain] == nil, !isCached(domain) else { return }
        if let data = await SiteIconFinder.find(domain: domain) {
            try? data.write(to: cacheURL(domain), options: .atomic)
        } else {
            try? Data().write(to: missURL(domain), options: .atomic)
        }
    }

    private func isCached(_ domain: String) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(domain).path)
    }

    private func recentlyMissed(_ domain: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: missURL(domain).path),
              let date = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(date) < 7 * 24 * 3600
    }

    private func missURL(_ domain: String) -> URL {
        cacheDirectory.appendingPathComponent("\(domain.replacingOccurrences(of: "/", with: "_")).none")
    }

    // MARK: - Ophalen

    private func fetch(domain: String) async -> Data? {
        if let viaSearch = await fetchViaGoogleSearch(domain: domain) { return viaSearch }
        return await fetchFavicon(domain: domain)
    }

    private func fetchViaGoogleSearch(domain: String) async -> Data? {
        let key = AppSettings.googleAPIKey
        let cx = AppSettings.googleCX
        guard !key.isEmpty, !cx.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "cx", value: cx),
            URLQueryItem(name: "q", value: "\(domain) logo"),
            URLQueryItem(name: "searchType", value: "image"),
            URLQueryItem(name: "num", value: "5"),
            URLQueryItem(name: "safe", value: "active"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }

        // Eerste bruikbare resultaat: het moet https zijn, laden en als afbeelding decoderen.
        for item in json.items ?? [] {
            guard let link = URL(string: item.link), link.scheme == "https",
                  let (imageData, imageResponse) = try? await URLSession.shared.data(from: link),
                  (imageResponse as? HTTPURLResponse)?.statusCode == 200,
                  imageData.count < 2_000_000,
                  isImage(imageData) else { continue }
            return imageData
        }
        return nil
    }

    private func fetchFavicon(domain: String) async -> Data? {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              isImage(data) else { return nil }
        return data
    }

    private func isImage(_ data: Data) -> Bool {
        PlatformImage(data: data) != nil
    }

    private func cacheURL(_ domain: String) -> URL {
        let safe = domain.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(safe).img")
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable { let link: String }
        let items: [Item]?
    }
}

/// Toont het logo van een domein; bij mislukken de eerste letter van de klantnaam in een klein vierkant.
struct LogoView: View {
    let domain: String
    let fallbackName: String
    var size: CGFloat = 16

    @State private var image: PlatformImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFail {
                Text(String(fallbackName.first.map { String($0) } ?? "?").uppercased())
                    .font(.werk(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(ThingsColor.tagText)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(ThingsColor.tagBackground))
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
        .task(id: domain) {
            image = nil
            didFail = false
            if let data = await LogoService.shared.logo(for: domain), let img = PlatformImage(data: data) {
                image = img
            } else {
                didFail = true
            }
        }
    }
}
