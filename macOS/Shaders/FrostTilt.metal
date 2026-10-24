// Matglas voor de Duo-vouw (zie DuoFold.swift): het vlak kantelt om zijn onderrand achter het beeldscherm weg. Hoe
// verder een punt achter het glas ligt, hoe groter de waas en hoe donkerder. De waas is een Vogel-schijf die per pixel
// een andere kant op draait (korrel in plaats van strepen), naar DuoLikeAnimation van Elijah Semyonov (MIT, zie
// THIRD-PARTY-NOTICES.md).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

constant int   kMaxTaps     = 32;
constant float kGoldenAngle = 2.39996322972865332;
constant float kTwoPi       = 6.28318530717958648;

static float grain(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// - bounds:    het vlak (x, y, breedte, hoogte) in punten, in dezelfde ruimte als `position`.
/// - tilt:      kanteling in radialen: 0 rechtop, π/2 plat achterover.
/// - spread:    waasstraal per punt diepte achter het glas.
/// - maxRadius: grootste waasstraal.
/// - darkening: lichtverlies per punt waasstraal.
[[ stitchable ]] half4 frostTilt(float2 position,
                                 SwiftUI::Layer layer,
                                 float4 bounds,
                                 float tilt,
                                 float spread,
                                 float maxRadius,
                                 float darkening)
{
    // Diepte achter het glas: hoogte boven de onderrand maal de sinus van de kanteling.
    const float rise   = max(bounds.y + bounds.w - position.y, 0.0);
    const float radius = min(spread * rise * sin(tilt), maxRadius);
    if (radius < 0.5) {
        return layer.sample(position);
    }

    const int   taps = clamp(int(radius * 2.0), 6, kMaxTaps);
    const float turn = grain(position) * kTwoPi;
    half4 sum = half4(0.0h);
    for (int i = 0; i < taps; ++i) {
        const float r = radius * sqrt((float(i) + 0.5) / float(taps));
        const float a = float(i) * kGoldenAngle + turn;
        sum += layer.sample(position + r * float2(cos(a), sin(a)));
    }
    sum /= half(taps);

    // Voorvermenigvuldigd: alleen de kleur donkerder, de dekking blijft.
    const half light = half(max(1.0 - darkening * radius, 0.0));
    return half4(sum.rgb * light, sum.a);
}
