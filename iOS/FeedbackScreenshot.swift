import UIKit

/// De screenshot bij een verbetering op de iPhone: wat Werkbank op dat moment toont (geen toestemming nodig).
@MainActor
enum FeedbackScreenshot {
    static func capture() async -> CapturedScreen {
        let date = Date()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else {
            return CapturedScreen(data: nil, date: date)
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return CapturedScreen(data: image.cgImage.flatMap { ScreenshotEncoding.jpeg($0, maxWidth: 1290) }, date: date)
    }
}
