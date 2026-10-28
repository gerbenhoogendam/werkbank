import Foundation
import ImageIO
import WerkbankCore

/// Het icoon van een website: het apple-touch-icon of het grootste icoon uit de HTML, anders het favicon via Google.
/// Alleen echte afbeeldingen van minstens 48 px die niet via een omleiding op een standaardicoon uitkomen. Gebruikt
/// voor de afzenders in de maillijst en de logo's van klanten.
enum SiteIconFinder {
    /// Kleiner dan dit (in pixels) is een favicon te vaag.
    private static let minPixels = 48

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func find(domain: String) async -> Data? {
        for home in ["https://\(domain)/", "https://www.\(domain)/"] {
            guard let url = URL(string: home), let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data.prefix(1_500_000), encoding: .utf8)
                    ?? String(data: data.prefix(1_500_000), encoding: .isoLatin1) else { continue }
            let base = http.url ?? url
            var candidates = SiteIcons.candidates(html: html, baseURL: base)
            if let touch = URL(string: "/apple-touch-icon.png", relativeTo: base)?.absoluteURL { candidates.append(touch) }
            for candidate in candidates.prefix(5) {
                if let icon = await usableImage(at: candidate) { return icon }
            }
            break   // de homepage laadde: niet ook nog www. proberen
        }
        // Laatste kans: de favicondienst van Google (404 = niets bekend).
        if let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") {
            return await usableImage(at: url)
        }
        return nil
    }

    private static func usableImage(at url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count < 1_000_000,
              !SiteIcons.isGeneric(http.url ?? url),
              pixels(of: data) >= minPixels else { return nil }
        return data
    }

    /// Grootste breedte of hoogte over alle beelden in het bestand (een .ico heeft er vaak meer).
    private static func pixels(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        var largest = 0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            largest = max(largest, width, height)
        }
        return largest
    }
}
