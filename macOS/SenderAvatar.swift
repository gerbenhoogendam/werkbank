import AppKit
import SwiftUI
import WerkbankCore

/// Rond avatar bij een mail: het logo van de afzender als dat er is, anders de eerste letter.
struct SenderAvatar: View {
    let name: String
    let address: String
    var isSent = false
    var size: CGFloat = 30

    @State private var logo: NSImage?

    private var key: String { "sender:" + address }

    var body: some View {
        ZStack {
            if let logo = logo ?? DecodedLogos.image(for: key) {
                Circle().fill(Color.white)
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                Circle().fill(isSent ? ThingsColor.accent : ThingsColor.textTertiary.opacity(0.5))
                Text(String(name.prefix(1)).uppercased())
                    .font(.werk(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ThingsColor.separator.opacity((logo ?? DecodedLogos.image(for: key)) == nil ? 0 : 1)))
        .task(id: address) {
            if let cached = DecodedLogos.image(for: key) {
                logo = cached
                return
            }
            logo = nil
            guard !address.isEmpty, let data = await SenderLogoService.shared.logo(forAddress: address) else { return }
            logo = DecodedLogos.image(from: data, for: key)
        }
        .accessibilityHidden(true)
    }
}
