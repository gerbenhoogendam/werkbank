import Foundation
import WebKit
import WerkbankCore

/// Afbeeldingen van het web in een mail lopen via de app (`werkbank-img:https://…`) in plaats van rechtstreeks via
/// WebKit, zodat een bewegende GIF (vaak een logo in een handtekening) maar één keer afspeelt (`GIFLoop`).
final class MailImageLoader: NSObject, WKURLSchemeHandler {
    static let scheme = "werkbank-img"

    /// Lopende verzoeken; WebKit roept start en stop aan op de hoofdthread.
    private var active = Set<ObjectIdentifier>()

    private static let remoteSource = try! NSRegularExpression(pattern: #"(<img\b[^>]*?\ssrc\s*=\s*["']?)(https?://)"#,
                                                               options: [.caseInsensitive])

    /// `<img src="https://…">` wordt `<img src="werkbank-img:https://…">`.
    static func route(_ html: String) -> String {
        let ns = NSString(string: html)
        return remoteSource.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length),
                                                     withTemplate: "$1\(scheme):$2")
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let original = URL(string: String(url.absoluteString.dropFirst(Self.scheme.count + 1))) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let id = ObjectIdentifier(task)
        active.insert(id)
        URLSession.shared.dataTask(with: original) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // Intussen gestopt (mail dicht): dan niets meer melden aan WebKit.
                guard let self, self.active.remove(id) != nil else { return }
                guard let data, let response else {
                    task.didFailWithError(error ?? URLError(.badServerResponse))
                    return
                }
                let body = GIFLoop.playOnce(data)
                task.didReceive(URLResponse(url: url, mimeType: response.mimeType, expectedContentLength: body.count,
                                            textEncodingName: nil))
                task.didReceive(body)
                task.didFinish()
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task))
    }
}
