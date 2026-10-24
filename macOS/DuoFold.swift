import QuartzCore
import SwiftUI

/// De Duo-vouw: een vlak kantelt om zijn onderrand naar achteren weg, achter het beeldscherm alsof dat matglas is.
/// Hoe verder een deel achter het glas ligt, hoe waziger en donkerder; de onderrand blijft het scherpst. Bij openen
/// komt het vlak van plat naar voren tot het rechtop staat, en wordt het weer scherp. (Idee: DuoLikeAnimation.)
///
/// Vensters, en panelen die dichtgaan, vouwen als afbeelding in Core Animation (`DuoWindowFold`): met echte waas en
/// vloeiend, ook als de app het druk heeft. Een paneel dat opengaat is er nog niet als afbeelding; daar doet
/// `DuoFoldEffect` het op de levende inhoud, met een matte sluier in plaats van waas (waas op een WKWebView is te
/// zwaar).
enum DuoFold {
    /// Waasstraal (punten) per punt diepte achter het glas, en de grootste straal.
    static let frostSpread = 0.06
    static let maxFrost = 64.0
    /// Waaslagen: tot `mediumFrost` mengt de lichte waas in, daarboven tot `heavyFrost` de zware.
    static let mediumFrost = 12.0
    static let heavyFrost = 40.0
    /// Licht dat per punt waasstraal verloren gaat.
    static let darkening = 0.01
    static let perspective = 0.35

    static let openingCurve = (0.2, 0.75, 0.25, 1.0)
    static let closingCurve = (0.45, 0.0, 0.75, 0.55)

    static func opening(_ part: FoldSpeed) -> Animation {
        .timingCurve(openingCurve.0, openingCurve.1, openingCurve.2, openingCurve.3, duration: part.duration)
    }

    static func closing(_ part: FoldSpeed) -> Animation {
        .timingCurve(closingCurve.0, closingCurve.1, closingCurve.2, closingCurve.3, duration: part.duration)
    }

    static func timing(opening: Bool) -> CAMediaTimingFunction {
        let c = opening ? openingCurve : closingCurve
        return CAMediaTimingFunction(controlPoints: Float(c.0), Float(c.1), Float(c.2), Float(c.3))
    }

    // MARK: Stand bij `progress` (0 rechtop, 1 plat achterover)

    static func tilt(_ progress: Double) -> Double {
        min(max(progress, 0), 1) * Double.pi / 2
    }

    /// Waasstraal op `fraction` van de hoogte (0 onderrand, 1 bovenrand) van een vlak van `height` punten.
    static func frost(at fraction: Double, height: Double, progress: Double) -> Double {
        min(frostSpread * fraction * height * sin(tilt(progress)), maxFrost)
    }

    static func mediumWeight(_ frost: Double) -> Double {
        min(max(frost / mediumFrost, 0), 1)
    }

    static func heavyWeight(_ frost: Double) -> Double {
        min(max((frost - mediumFrost) / (heavyFrost - mediumFrost), 0), 1)
    }

    /// Donkerte bij een waasstraal, plus het donkere moment vlak voor plat.
    static func darkness(_ frost: Double, progress: Double) -> Double {
        1 - (1 - min(darkening * frost, 1)) * (1 - dim(progress))
    }

    static func dim(_ progress: Double) -> Double {
        smoothstep(0.55, 1, progress) * 0.7
    }

    static func opacity(_ progress: Double) -> Double {
        1 - smoothstep(0.9, 1, progress)
    }

    private static func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
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

/// De vouw op levende inhoud (een paneel dat opengaat): kantelen, een matte sluier en donkerte naar de bovenrand.
/// Geen waas en geen eigen schaduw, zodat het ook met mailtekst vloeiend blijft. Als overgang: `.duoFold`.
struct DuoFoldEffect: ViewModifier, Animatable {
    /// 0: rechtop, gewoon in beeld. 1: plat achterover, weg.
    var progress: Double
    /// Hoogte van het vlak in punten.
    var height: Double
    var cornerRadius: CGFloat = 12
    /// Van dit paneel vouwt al een afbeelding weg (`DuoWindowFold`): het paneel zelf verdwijnt meteen.
    var hidesInstantly = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let veilStops = stops { ThingsColor.backgroundContent.opacity(Self.veil($0)) }
        let shadeStops = stops { Color.black.opacity(DuoFold.darkness($0, progress: progress)) }
        content
            .overlay {
                if progress > 0.001 {
                    ZStack {
                        LinearGradient(stops: veilStops, startPoint: .bottom, endPoint: .top)
                        LinearGradient(stops: shadeStops, startPoint: .bottom, endPoint: .top)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.radians(DuoFold.tilt(progress)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, anchorZ: 0,
                              perspective: DuoFold.perspective)
            .opacity(hidesInstantly && progress > 0 ? 0 : DuoFold.opacity(progress))
            .allowsHitTesting(progress < 0.001)
    }

    /// Matte sluier in plaats van waas: licht, en dichter waar de zware waas zou zitten.
    private static func veil(_ frost: Double) -> Double {
        0.25 * DuoFold.mediumWeight(frost) + 0.5 * DuoFold.heavyWeight(frost)
    }

    /// Verloop van onder (0) naar boven (1), met de kleur bij de waasstraal op die hoogte.
    private func stops(_ color: (Double) -> Color) -> [Gradient.Stop] {
        (0...4).map { index in
            let fraction = Double(index) / 4
            return Gradient.Stop(color: color(DuoFold.frost(at: fraction, height: height, progress: progress)),
                                 location: fraction)
        }
    }
}

extension AnyTransition {
    /// Openen en sluiten met de Duo-vouw.
    static func duoFold(height: Double, hidesInstantly: Bool = false) -> AnyTransition {
        .modifier(active: DuoFoldEffect(progress: 1, height: height, hidesInstantly: hidesInstantly),
                  identity: DuoFoldEffect(progress: 0, height: height, hidesInstantly: hidesInstantly))
    }
}
