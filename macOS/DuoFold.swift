import SwiftUI

/// De vouw van de iPhone Duo: het glas kantelt om een scharnier in het midden, de inhoud blijft liggen. Door het glas
/// gezien rekt het deel bij het scharnier uit over de breedte, worden de randen korter (perspectief) en nemen waas en
/// donkerte toe met de afstand tot het scharnier; vlak voor dicht is het een donkere strook.
///
/// Model en waarden komen uit DuoLikeAnimation van Elijah Semyonov (MIT). Dat rekent het per pixel uit in een
/// Metal-shader; hier is het nagebootst met gewone SwiftUI-effecten, omdat een shader geen AppKit-inhoud kan lezen
/// (mailtekst in een WKWebView, tekstvelden) en er zo geen Metal-toolchain nodig is om te bouwen.
enum DuoFold {
    /// Kanteling bij dicht: net geen 90°, zodat het eerst donker wordt en dan pas verdwijnt.
    static let maxAngle = 88.0 * Double.pi / 180
    /// Afstand van het oog tot het scherm: 320 mm bij 6 punten per mm.
    static let eyeDistance = 1920.0
    /// Straal van de waas per punt afstand tussen glas en inhoud.
    static let blurSpread = 0.12
    /// Licht dat per punt waas verloren gaat.
    static let darkening = 0.015

    static let opening = Animation.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.5)
    static let closing = Animation.timingCurve(0.45, 0, 0.75, 0.55, duration: 0.42)
    static let windowOpening = Animation.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.55)
    static let windowClosing = Animation.timingCurve(0.45, 0, 0.75, 0.55, duration: 0.45)
}

/// Stand van de vouw voor een vlak van `width` punten breed: hoe breder, hoe sterker het perspectief, zoals bij echt glas.
struct DuoFoldPose {
    let progress: Double
    let width: Double

    private var angle: Double { min(max(progress, 0), 1) * DuoFold.maxAngle }

    /// Hoeveel verder het oog door de buitenrand kijkt dan door het scharnier (1 als het plat ligt).
    var edgeStretch: Double { DuoFold.eyeDistance / max(DuoFold.eyeDistance - width / 2 * sin(angle), 1) }

    /// Horizontale vergroting: het deel bij het scharnier vult het vlak.
    var zoom: Double { min(1 / max(cos(angle) * (1 + edgeStretch) / 2, 0.0001), 4.5) }

    /// Waas over het vlak; vooral in de tweede helft van de beweging, zodat het begin scherp blijft.
    var blur: Double { DuoFold.blurSpread * width / 4 * pow(sin(angle), 3) }

    /// Donkerte op `fraction` van het scharnier (0) naar de rand (1).
    func darkness(at fraction: Double) -> Double {
        min(1, DuoFold.darkening * DuoFold.blurSpread * fraction * width / 2 * sin(angle))
    }

    /// Het donkere moment vlak voor dicht, over het hele vlak.
    var dim: Double { smoothstep(0.6, 1, progress) * 0.85 }

    var opacity: Double { 1 - smoothstep(0.85, 1, progress) }

    private func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// 0: plat, gewoon in beeld. 1: dichtgevouwen. Als overgang (`.duoFold`) speelt het bij openen en sluiten.
struct DuoFoldEffect: ViewModifier, Animatable {
    var progress: Double
    /// Breedte van het vlak in punten.
    var width: Double
    var cornerRadius: CGFloat = 12
    /// Schaduw rond het vlak; verdwijnt in het begin van de vouw.
    var shadow: Color = .clear
    var shadowRadius: CGFloat = 18
    /// Inhoud met eigen doorzichtige delen (afbeelding van een venster met ronde hoeken): de donkerte valt alleen op
    /// de inhoud. Alleen voor afbeeldingen; een compositing group om AppKit-inhoud kan die niet tekenen.
    var keepsTransparency = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let pose = DuoFoldPose(progress: progress, width: width)
        Group {
            if keepsTransparency {
                content
                    .scaleEffect(x: pose.zoom, y: 1)
                    .blur(radius: pose.blur)
                    .overlay(DuoFoldShade(pose: pose).blendMode(.sourceAtop))
                    .compositingGroup()
            } else {
                content
                    .scaleEffect(x: pose.zoom, y: 1)
                    .blur(radius: pose.blur)
                    .overlay(DuoFoldShade(pose: pose).allowsHitTesting(false))
            }
        }
        .clipShape(DuoFoldShape(pose: pose, cornerRadius: cornerRadius))
        .shadow(color: shadow.opacity(1 - min(progress * 2.5, 1)), radius: shadowRadius, x: 0, y: shadowRadius / 3)
        .opacity(pose.opacity)
        .allowsHitTesting(progress < 0.001)
    }
}

extension AnyTransition {
    /// Openen en sluiten met de Duo-vouw.
    static func duoFold(width: Double, shadow: Color) -> AnyTransition {
        .modifier(active: DuoFoldEffect(progress: 1, width: width, shadow: shadow),
                  identity: DuoFoldEffect(progress: 0, width: width, shadow: shadow))
    }
}

/// Wat van het vlak zichtbaar is: de randen worden korter naarmate ze verder kantelen, met de vouwlijn in het midden.
private struct DuoFoldShape: Shape {
    let pose: DuoFoldPose
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let rounded = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        guard pose.progress > 0.0001 else { return rounded }
        let inset = rect.height / 2 * (1 - 1 / pose.edgeStretch)
        var bowtie = Path()
        bowtie.move(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        bowtie.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        bowtie.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        bowtie.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        bowtie.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        bowtie.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
        bowtie.closeSubpath()
        return rounded.intersection(bowtie)
    }
}

/// Donkerte die toeneemt met de afstand tot het scharnier, plus het donkere moment vlak voor dicht.
private struct DuoFoldShade: View {
    let pose: DuoFoldPose

    var body: some View {
        let fractions: [Double] = [1, 0.5, 0, 0.5, 1]
        let stops = fractions.enumerated().map { index, fraction in
            Gradient.Stop(color: .black.opacity(pose.darkness(at: fraction)),
                          location: Double(index) / Double(fractions.count - 1))
        }
        ZStack {
            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
            Color.black.opacity(pose.dim)
        }
    }
}
