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

/// Wat de inspreekanimatie per beeld bijhoudt: het stemniveau via een veer (`ThingsMotion.alive`), zodat het
/// vloeiend aanzwelt en wegzakt in plaats van twaalf keer per seconde te verspringen, en de stroming, die sneller
/// gaat naarmate je harder praat. Gedeeld door de rand en de golfvorm van één veld; gewone eigenschappen (geen
/// SwiftUI-state), dus bijwerken per beeld kost geen extra weergave.
final class VoiceMotion {
    private(set) var level = 0.0
    private var velocity = 0.0
    /// Afgelegde stroming; loopt op, zodat een andere snelheid geen sprong geeft.
    private(set) var flow = 0.0
    private var last: TimeInterval?

    /// Rand en golfvorm roepen dit allebei aan; het tweede keer in hetzelfde beeld verandert er niets.
    func advance(to target: Double, at time: TimeInterval, reduceMotion: Bool) {
        // Na een haperend of overgeslagen beeld niet in één keer inhalen.
        let step = min(max(time - (last ?? time), 0), 1.0 / 20)
        last = time
        ThingsMotion.alive.update(value: &level, velocity: &velocity, target: target, deltaTime: step)
        level = min(max(level, 0), 1.2)
        // Stil: een trage drift, zodat je ziet dat hij luistert; praten: duidelijk sneller.
        if !reduceMotion { flow += step * (0.35 + 2.4 * min(level, 1)) }
    }
}

/// Rand om het veld waarin je inspreekt: een kleurverloop dat langs de rand stroomt, met een gloed die opleeft als je
/// praat. Verminderde beweging: de rand staat stil, alleen de gloed volgt je stem.
struct VoiceGlow<S: InsettableShape>: View {
    let level: Double
    let motion: VoiceMotion
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let _ = motion.advance(to: level, at: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
            let energy = min(motion.level, 1)
            let gradient = AngularGradient(gradient: Gradient(stops: stops(flow: motion.flow)), center: .center,
                                           angle: .radians(motion.flow * 0.6))
            ZStack {
                // Wijde gloed (waas onder de 20 pt: zwaarder is duur en voegt niets toe).
                shape.strokeBorder(gradient, lineWidth: 8 + 14 * energy)
                    .blur(radius: 8 + 8 * energy)
                    .opacity(0.25 + 0.65 * energy)
                shape.strokeBorder(gradient, lineWidth: 3 + 3 * energy)
                    .blur(radius: 3)
                    .opacity(0.55 + 0.45 * energy)
                // Scherpe kern, met een licht randje als je praat.
                shape.strokeBorder(gradient, lineWidth: 1.5)
                shape.strokeBorder(Color.white.opacity(0.5 * energy), lineWidth: 0.75)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// De kleuren schuiven langzaam ten opzichte van elkaar, zodat de rand stroomt in plaats van alleen te draaien.
    private func stops(flow: Double) -> [Gradient.Stop] {
        let colors = SiriPalette.ring
        return colors.enumerated().map { index, color in
            let base = Double(index) / Double(colors.count - 1)
            let isEdge = index == 0 || index == colors.count - 1
            return Gradient.Stop(color: color, location: isEdge ? base : base + 0.05 * sin(flow * 1.3 + Double(index) * 1.7))
        }
    }
}

/// Golfvorm in het veld tijdens het inspreken: gekleurde lenzen die met je stem aanzwellen, elk in zijn eigen ritme
/// ademen en langs het veld stromen, met een zachte gloed eronder. Verminderde beweging: de golven staan stil en
/// worden alleen helderder als je praat.
struct VoiceWave: View {
    let level: Double
    let motion: VoiceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Wave {
        let color: Color
        /// Aantal bulten over de breedte.
        let frequency: Double
        /// Stroomrichting en -snelheid ten opzichte van de rest.
        let drift: Double
        let phase: Double
        let height: Double
        /// Tempo waarin deze golf zelf ademt.
        let breath: Double
    }

    private static let waves: [Wave] = [
        Wave(color: SiriPalette.periwinkle, frequency: 1.3, drift: 1.9, phase: 0.0, height: 1.0, breath: 1.1),
        Wave(color: SiriPalette.coral, frequency: 1.9, drift: -1.4, phase: 1.7, height: 0.8, breath: 1.7),
        Wave(color: SiriPalette.violet, frequency: 2.6, drift: 2.6, phase: 3.1, height: 0.65, breath: 0.8),
        Wave(color: SiriPalette.peach, frequency: 1.0, drift: -0.9, phase: 4.4, height: 0.55, breath: 1.4),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let _ = motion.advance(to: level, at: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
            let energy = min(motion.level, 1)
            let flow = motion.flow
            Canvas { canvas, size in
                let middle = size.height / 2
                let amplitude = (reduceMotion ? 0.45 : 0.1 + 0.9 * energy) * middle
                let lenses = Self.waves.map { lens($0, flow: flow, amplitude: amplitude, size: size) }
                canvas.blendMode = scheme == .dark ? .plusLighter : .normal

                // Gloed onder de golven.
                canvas.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    for (wave, path) in zip(Self.waves, lenses) {
                        layer.fill(path, with: .color(wave.color.opacity(0.5 * (0.3 + 0.7 * energy))))
                    }
                }
                for (wave, path) in zip(Self.waves, lenses) {
                    canvas.fill(path, with: .linearGradient(
                        Gradient(colors: [wave.color.opacity(0.15), wave.color.opacity(0.8), wave.color.opacity(0.15)]),
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
            .opacity(reduceMotion ? 0.4 + 0.6 * energy : 1)
        }
        .accessibilityHidden(true)
    }

    /// Een lens: boven en onder even dik, aan de randen van het veld naar nul.
    private func lens(_ wave: Wave, flow: Double, amplitude: Double, size: CGSize) -> Path {
        let middle = size.height / 2
        let steps = max(Int(size.width / 3), 8)
        let breathing = 0.75 + 0.25 * sin(flow * wave.breath + wave.phase)
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...steps {
            let x = Double(index) / Double(steps)
            let envelope = pow(sin(.pi * x), 1.6)
            let swell = abs(sin(2 * .pi * wave.frequency * x + wave.phase + flow * wave.drift))
            let thickness = amplitude * wave.height * envelope * breathing * (0.25 + 0.75 * swell)
            top.append(CGPoint(x: x * size.width, y: middle - thickness))
            bottom.append(CGPoint(x: x * size.width, y: middle + thickness))
        }
        var path = Path()
        path.move(to: top[0])
        for point in top.dropFirst() { path.addLine(to: point) }
        for point in bottom.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
