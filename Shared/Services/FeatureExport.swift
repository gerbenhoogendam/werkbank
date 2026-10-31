import CoreGraphics
import Foundation
import SwiftUI
import WerkbankCore

/// Alle verzamelde verbeteringen in één PDF voor Claude: eerst de prompt (desktop en mobiel apart, met nummers), daarna
/// per verbetering een pagina met het nummer, de datum en tijd, het apparaat, de tekst en de screenshot van dat moment.
/// Op de Mac in iCloud Drive (Werkbank/Verbeteringen), op de iPhone tijdelijk, om te delen.
@MainActor
enum FeatureExport {
    enum ExportError: LocalizedError {
        case failed
        var errorDescription: String? { "De PDF kon niet worden gemaakt." }
    }

    /// A4 liggend: screenshots van een venster zijn breed.
    static let pageSize = CGSize(width: 842, height: 595)

    static func pdf(_ requests: [FeatureRequest]) throws -> URL {
        let items = requests.map(\.promptItem)
        let prompt = FeaturePrompt.build(items, screenshotsInDocument: true)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ExportError.failed }
        let promptPages = pages(prompt)
        for (index, lines) in promptPages.enumerated() {
            render(PromptPage(lines: lines, page: index + 1, of: promptPages.count), in: context)
        }
        for (reference, index) in FeaturePrompt.numbered(items) {
            render(RequestPage(reference: reference, request: requests[index]), in: context)
        }
        context.closePDF()

        let name = "Verbeteringen \(fileStamp(.now)).pdf"
        #if os(macOS)
        let folder = WerkbankFolder.url.appendingPathComponent("Verbeteringen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        guard CloudFile.write(data as Data, to: url) else { throw ExportError.failed }
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try (data as Data).write(to: url, options: .atomic)
        #endif
        return url
    }

    private static func render<V: View>(_ page: V, in context: CGContext) {
        let renderer = ImageRenderer(content: page
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
    }

    /// De prompt over pagina's verdeeld: een lange regel telt voor meer regels.
    private static func pages(_ prompt: String) -> [[String]] {
        let budget = 30
        var result: [[String]] = [[]]
        var used = 0
        for line in prompt.components(separatedBy: "\n") {
            let cost = max(1, Int((Double(line.count) / 125).rounded(.up)))
            if used + cost > budget, !(result.last?.isEmpty ?? true) {
                result.append([])
                used = 0
            }
            result[result.count - 1].append(line)
            used += cost
        }
        return result
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: date)
    }
}

/// Een pagina van de prompt. Een document voor Claude, geen scherm van de app: vaste letters en zwart op wit, in elk thema.
private struct PromptPage: View {
    let lines: [String]
    let page: Int
    let of: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Verbeteringen voor Werkbank")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Prompt \(page)/\(of)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
            }
            .padding(.bottom, 8)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("## ") {
                    Text(line.dropFirst(3))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 4)
                } else if line.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    Text(line)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.black)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Eén verbetering: nummer, datum en tijd, apparaat, de tekst en de screenshot.
private struct RequestPage: View {
    let reference: String
    let request: FeatureRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(reference)
                    .font(.system(size: 18, weight: .bold))
                Text("\(request.platform.title) · \(FeaturePrompt.stamp(request.moment, seconds: true)) · \(request.device)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
                Spacer()
            }
            Text(request.text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            if let data = request.screenshot, let image = ScreenshotEncoding.image(data) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        Text("Screenshot \(reference) · \(FeaturePrompt.stamp(request.moment, seconds: true))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .padding(6)
                    }
            } else {
                Text("Geen screenshot")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Color.black)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
