import SwiftUI

/// Kleuren van de inspreekanimatie, naar de gloed van Siri (Apple Intelligence).
private enum SiriPalette {
    static let lavender = Color(hex: 0xBC82F3)
    static let pink = Color(hex: 0xF5B9EA)
    static let periwinkle = Color(hex: 0x8D9FFF)
    static let coral = Color(hex: 0xFF6778)
    static let peach = Color(hex: 0xFFBA71)
    static let violet = Color(hex: 0xC686FF)

    static let ring: [Color] = [lavender, pink, periwinkle, coral, peach, violet, lavender]
}

/// Rand om het veld waarin je inspreekt: een kleurverloop dat rondloopt, met een gloed die opleeft als je praat.
struct VoiceGlow<S: InsettableShape>: View {
    let level: Double
    let shape: S

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(colors: SiriPalette.ring, center: .center,
                                           angle: .degrees((time * 72).truncatingRemainder(dividingBy: 360)))
            // Ook stil een zachte ademhaling, zodat je ziet dat hij luistert.
            let breath = 0.5 + 0.5 * sin(time * 2.4)
            let glow = min(1, 0.3 + 0.12 * breath + 0.7 * level)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 10 + 14 * level)
                    .blur(radius: 10 + 14 * level)
                    .opacity(glow)
                shape.strokeBorder(gradient, lineWidth: 3 + 3 * level)
                    .blur(radius: 2)
                    .opacity(0.6 + 0.4 * glow)
                shape.strokeBorder(gradient, lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Golfvorm in het veld tijdens het inspreken: gekleurde, in elkaar overlopende golven die met je stem aanzwellen en
/// langs het veld stromen.
struct VoiceWave: View {
    let level: Double
    @Environment(\.colorScheme) private var scheme

    private struct Wave {
        let color: Color
        /// Aantal bulten over de breedte.
        let frequency: Double
        /// Snelheid en richting van de stroming.
        let speed: Double
        let phase: Double
        let height: Double
    }

    private static let waves: [Wave] = [
        Wave(color: SiriPalette.periwinkle, frequency: 1.3, speed: 1.9, phase: 0.0, height: 1.0),
        Wave(color: SiriPalette.coral, frequency: 1.9, speed: -1.4, phase: 1.7, height: 0.8),
        Wave(color: SiriPalette.violet, frequency: 2.6, speed: 2.6, phase: 3.1, height: 0.65),
        Wave(color: SiriPalette.peach, frequency: 1.0, speed: -0.9, phase: 4.4, height: 0.55),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            Canvas { canvas, size in
                let middle = size.height / 2
                // Stil: een rustige golf; praten: tot de volle hoogte.
                let amplitude = (0.14 + 0.86 * level) * middle
                let steps = max(Int(size.width / 3), 8)
                canvas.blendMode = scheme == .dark ? .plusLighter : .multiply

                for wave in Self.waves {
                    // Een lens per golf: boven en onder even dik, aan de randen van het veld naar nul.
                    var top: [CGPoint] = []
                    var bottom: [CGPoint] = []
                    for index in 0...steps {
                        let x = Double(index) / Double(steps)
                        let envelope = pow(sin(.pi * x), 1.6)
                        let swell = abs(sin(2 * .pi * wave.frequency * x + wave.phase + time * wave.speed))
                        let thickness = amplitude * wave.height * envelope * (0.25 + 0.75 * swell)
                        top.append(CGPoint(x: x * size.width, y: middle - thickness))
                        bottom.append(CGPoint(x: x * size.width, y: middle + thickness))
                    }
                    var path = Path()
                    path.move(to: top[0])
                    for point in top.dropFirst() { path.addLine(to: point) }
                    for point in bottom.reversed() { path.addLine(to: point) }
                    path.closeSubpath()
                    canvas.fill(path, with: .linearGradient(
                        Gradient(colors: [wave.color.opacity(0.15), wave.color.opacity(0.75), wave.color.opacity(0.15)]),
                        startPoint: CGPoint(x: 0, y: middle), endPoint: CGPoint(x: size.width, y: middle)))
                }

                // Een dunne lijn door het midden, zodat er ook in stilte iets staat.
                var line = Path()
                line.move(to: CGPoint(x: 0, y: middle))
                line.addLine(to: CGPoint(x: size.width, y: middle))
                canvas.blendMode = .normal
                canvas.stroke(line, with: .linearGradient(
                    Gradient(colors: [.clear, SiriPalette.lavender.opacity(0.7), .clear]),
                    startPoint: CGPoint(x: 0, y: middle), endPoint: CGPoint(x: size.width, y: middle)),
                    lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
