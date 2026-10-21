import AppKit
import SwiftUI

/// Kleur en tekstkleur van afspraken in de agenda. De dekking stel je in bij Voorkeuren › Agenda's; de tekst
/// wordt wit zodra de afspraak (gemengd met de achtergrond) te donker wordt voor donkere tekst, en andersom.
enum EventStyle {
    static let defaultOpacity = 0.18

    /// `nil`: de gewone tekstkleuren van de app volstaan (licht genoeg, of de kleur is niet te lezen).
    static func textColors(on color: Color, opacity: Double, dark: Bool) -> (primary: Color, secondary: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else {
            return (ThingsColor.textPrimary, ThingsColor.textSecondary)
        }
        // Achtergrond van de agenda: wit (licht) of #1E1F22 (donker).
        let background = dark ? 30.0 / 255.0 : 1.0
        func mix(_ component: CGFloat) -> Double { Double(component) * opacity + background * (1 - opacity) }
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(mix(c.redComponent)) + 0.7152 * linear(mix(c.greenComponent))
            + 0.0722 * linear(mix(c.blueComponent))
        // Omslagpunt waar wit en zwart even veel contrast geven (WCAG): ongeveer 0,18.
        if luminance < 0.18 {
            return (.white, .white.opacity(0.78))
        }
        return (Color(white: 0.11), Color(white: 0.11).opacity(0.7))
    }
}

/// Een hele-dag-afspraak boven de agenda.
struct AllDayChip: View {
    let title: String
    let color: Color
    var horizontalPadding: CGFloat = 5

    @AppStorage(SettingsKey.eventOpacity) private var opacity = EventStyle.defaultOpacity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fill = min(1, opacity + 0.07)
        Text(title)
            .thingsFont(.tag)
            .foregroundStyle(EventStyle.textColors(on: color, opacity: fill, dark: colorScheme == .dark).primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(fill)))
    }
}
