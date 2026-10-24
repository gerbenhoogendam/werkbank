import SwiftUI

/// De Duo-vouw: een vlak kantelt om zijn onderrand naar achteren weg, achter het beeldscherm alsof dat matglas is. Hoe
/// verder een deel achter het glas ligt, hoe waziger en donkerder; de onderrand blijft het scherpst. Bij openen komt het
/// vlak van plat naar voren tot het rechtop staat, en wordt het weer scherp.
///
/// Het matglas per pixel is een Metal-shader (`Shaders/FrostTilt.metal`) en werkt alleen op een afbeelding: vensters, en
/// panelen die dichtgaan (daarvan maakt `DuoWindowFold` eerst een afbeelding). Een paneel dat opengaat is er nog niet als
/// afbeelding, en een shader kan de AppKit-inhoud (mailtekst, tekstvelden) niet lezen; daar is het matglas benaderd met
/// één waas en een verloop van donker naar licht.
enum DuoFold {
    /// Waasstraal per punt diepte achter het glas, en de grootste straal.
    static let frostSpread = 0.06
    static let maxFrost = 64.0
    /// Licht dat per punt waasstraal verloren gaat.
    static let darkening = 0.01
    static let perspective = 0.35

    static func opening(_ part: FoldSpeed) -> Animation {
        .timingCurve(0.2, 0.75, 0.25, 1, duration: part.duration)
    }

    static func closing(_ part: FoldSpeed) -> Animation {
        .timingCurve(0.45, 0, 0.75, 0.55, duration: part.duration)
    }
}

/// Duur van de vouw per onderdeel, in Voorkeuren › Weergave.
enum FoldSpeed: String, CaseIterable, Identifiable {
    case windowOpen, windowClose, mailOpen, mailClose, send

    static let range = 0.15...1.5

    var id: String { rawValue }
    var key: String { "animation.\(rawValue)" }

    var title: String {
        switch self {
        case .windowOpen: "Venster openen"
        case .windowClose: "Venster sluiten"
        case .mailOpen: "Mail openen"
        case .mailClose: "Mail sluiten"
        case .send: "Versturen"
        }
    }

    var defaultDuration: Double {
        switch self {
        case .windowOpen: 0.55
        case .windowClose: 0.45
        case .mailOpen: 0.5
        case .mailClose, .send: 0.42
        }
    }

    /// In seconden.
    var duration: Double {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? min(max(stored, Self.range.lowerBound), Self.range.upperBound) : defaultDuration
    }
}

/// 0: rechtop, gewoon in beeld. 1: plat achterover, weg. Als overgang (`.duoFold`) speelt het bij openen en sluiten.
struct DuoFoldEffect: ViewModifier, Animatable {
    var progress: Double
    /// Hoogte van het vlak in punten (voor de benaderde waas; de shader meet zelf).
    var height: Double
    var cornerRadius: CGFloat = 12
    /// Schaduw rond het vlak; verdwijnt in het begin van de beweging.
    var shadow: Color = .clear
    var shadowRadius: CGFloat = 18
    /// Afbeelding: matglas per pixel met de shader. Alleen voor afbeeldingen; AppKit-inhoud tekent een shader niet.
    var usesShader = false
    /// Van dit paneel vouwt al een afbeelding weg (`DuoWindowFold`): het paneel zelf verdwijnt meteen.
    var hidesInstantly = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let tilt = min(max(progress, 0), 1) * Double.pi / 2
        let topFrost = min(DuoFold.frostSpread * height * sin(tilt), DuoFold.maxFrost)
        // Het laatste stuk, bijna plat: alles wordt donker.
        let dim = smoothstep(0.55, 1, progress) * 0.7
        Group {
            if usesShader {
                content
                    .overlay(Color.black.opacity(dim).blendMode(.sourceAtop))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .compositingGroup()
                    .layerEffect(ShaderLibrary.frostTilt(.boundingRect, .float(tilt), .float(DuoFold.frostSpread),
                                                         .float(DuoFold.maxFrost), .float(DuoFold.darkening)),
                                 maxSampleOffset: .zero, isEnabled: progress > 0.001)
            } else {
                content
                    .blur(radius: topFrost / 3)
                    .overlay {
                        ZStack {
                            LinearGradient(colors: [.black.opacity(min(DuoFold.darkening * topFrost, 1)), .clear],
                                           startPoint: .top, endPoint: .bottom)
                            Color.black.opacity(dim)
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .rotation3DEffect(.radians(tilt), axis: (x: 1, y: 0, z: 0), anchor: .bottom, anchorZ: 0,
                          perspective: DuoFold.perspective)
        .shadow(color: shadow.opacity(1 - min(progress * 2.5, 1)), radius: shadowRadius, x: 0, y: shadowRadius / 3)
        .opacity(hidesInstantly && progress > 0 ? 0 : 1 - smoothstep(0.9, 1, progress))
        .allowsHitTesting(progress < 0.001)
    }

    private func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

extension AnyTransition {
    /// Openen en sluiten met de Duo-vouw.
    static func duoFold(height: Double, shadow: Color, hidesInstantly: Bool = false) -> AnyTransition {
        .modifier(active: DuoFoldEffect(progress: 1, height: height, shadow: shadow, hidesInstantly: hidesInstantly),
                  identity: DuoFoldEffect(progress: 0, height: height, shadow: shadow, hidesInstantly: hidesInstantly))
    }
}
