import SwiftUI
import UniformTypeIdentifiers

/// Bovenin het Mail-paneel tijdens het slepen van een mail: kom je bij de tabs, dan klapt "Verplaatsen naar" open met
/// elke andere mailbox als vlak om de mail op los te laten. Eén drop-bestemming voor de hele kaart (de vlakken worden op
/// positie bepaald), zodat hij niet dichtklapt zodra je van de kop naar een vlak gaat.
struct MailMoveZone: View {
    /// Hoogte van kop en tabs: daar klapt de kaart open.
    let triggerHeight: CGFloat
    @Binding var isOpen: Bool
    let onMove: (String, [NSItemProvider]) -> Bool

    private let gmail = GmailSession.shared
    private let dragState = MailDragState.shared
    /// Een object en geen losse waarden: SwiftUI houdt tijdens één sleepactie dezelfde delegate vast, die moet dus
    /// steeds de actuele posities van de vlakken zien.
    @State private var model = MoveZoneModel()
    private var hovered: String? { model.hovered }
    private static let space = "mailMoveZone"

    private var targets: [String] { gmail.accounts.filter { $0 != dragState.sourceAccount } }

    var body: some View {
        ZStack(alignment: .top) {
            if isOpen {
                card
                    .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                Color.clear.frame(height: triggerHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(TileFrames.self) { [model] in model.frames = $0 }
        .onDrop(of: [.gmailMessage], delegate: MoveDelegate(isOpen: $isOpen, model: model, onMove: onMove))
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovered)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .foregroundStyle(ThingsColor.accent)
                Text("Verplaatsen naar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ThingsColor.textPrimary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            ForEach(targets, id: \.self) { email in tile(email) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func tile(_ email: String) -> some View {
        let isOn = hovered == email
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(isOn ? Color.white.opacity(0.22) : ThingsColor.accent.opacity(0.12))
                Image(systemName: isOn ? "tray.and.arrow.down.fill" : "tray.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.accent)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(gmail.displayName(email))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                Text(email)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : ThingsColor.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? ThingsColor.accent : ThingsColor.backgroundSidebar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? ThingsColor.accent : ThingsColor.separator,
                              style: StrokeStyle(lineWidth: isOn ? 2 : 1.5, dash: isOn ? [] : [5, 4]))
        )
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TileFrames.self, value: [email: proxy.frame(in: .named(Self.space))])
        })
        .scaleEffect(isOn ? 1.04 : 1)
        .shadow(color: isOn ? ThingsColor.accent.opacity(0.4) : .clear, radius: 10, x: 0, y: 3)
        .opacity(hovered == nil || isOn ? 1 : 0.5)
    }
}

@Observable
private final class MoveZoneModel {
    var hovered: String?
    @ObservationIgnored var frames: [String: CGRect] = [:]
}

private struct TileFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct MoveDelegate: DropDelegate {
    @Binding var isOpen: Bool
    let model: MoveZoneModel
    let onMove: (String, [NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.gmailMessage]) }

    func dropEntered(info: DropInfo) {
        isOpen = true
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: model.hovered == nil ? .cancel : .move)
    }

    func dropExited(info: DropInfo) {
        isOpen = false
        model.hovered = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        update(info)
        let target = model.hovered
        isOpen = false
        model.hovered = nil
        guard let target else { return false }
        return onMove(target, info.itemProviders(for: [.gmailMessage]))
    }

    private func update(_ info: DropInfo) {
        let target = model.frames.first { $0.value.contains(info.location) }?.key
        if target != model.hovered { model.hovered = target }
    }
}
