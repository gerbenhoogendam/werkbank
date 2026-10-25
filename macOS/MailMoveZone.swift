import SwiftUI
import UniformTypeIdentifiers

/// Bovenin het Mail-paneel tijdens het slepen van een mail: kom je bij de tabs, dan klapt "Verplaatsen naar" open met
/// elke andere mailbox als vlak om de mail op los te laten. Elk vlak is een eigen dropzone (zoals die van Claude); de
/// kaart blijft open zolang je boven de kop, de kaart of een vlak hangt.
struct MailMoveZone: View {
    /// Hoogte van kop en tabs: daar klapt de kaart open.
    let triggerHeight: CGFloat
    @Binding var isOpen: Bool
    let onMove: (String, [NSItemProvider]) -> Bool

    private let gmail = GmailSession.shared
    private let dragState = MailDragState.shared
    @State private var model = MoveZoneModel()
    private var hovered: String? { model.hovered }

    private var targets: [String] { gmail.accounts.filter { $0 != dragState.sourceAccount } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(height: triggerHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.gmailMessage], isTargeted: target(\.triggerTargeted)) { _ in false }
            if isOpen {
                card
                    .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onChange(of: model.isTargeted) { _, targeted in
            if targeted {
                isOpen = true
            } else {
                // Even wachten: van de kop naar een vlak gaan is eerst "weg" en dan pas "erboven".
                let open = $isOpen
                Task { @MainActor [model] in
                    try? await Task.sleep(for: .milliseconds(200))
                    if !model.isTargeted { open.wrappedValue = false }
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovered)
    }

    private func target(_ keyPath: ReferenceWritableKeyPath<MoveZoneModel, Bool>) -> Binding<Bool> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }

    private func tileTarget(_ email: String) -> Binding<Bool> {
        Binding(get: { model.hovered == email }, set: { on in
            if on {
                model.hovered = email
            } else if model.hovered == email {
                model.hovered = nil
            }
        })
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .foregroundStyle(ThingsColor.accent)
                Text("Verplaatsen naar")
                    .font(.werk(size: 14, weight: .semibold))
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [.gmailMessage], isTargeted: target(\.cardTargeted)) { _ in false }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func tile(_ email: String) -> some View {
        let isOn = hovered == email
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(isOn ? Color.white.opacity(0.22) : ThingsColor.accent.opacity(0.12))
                Image(systemName: isOn ? "tray.and.arrow.down.fill" : "tray.fill")
                    .font(.werk(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.accent)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(gmail.displayName(email))
                    .font(.werk(size: 13.5, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : ThingsColor.textPrimary)
                Text(email)
                    .font(.werk(size: 11))
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
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrop(of: [.gmailMessage], isTargeted: tileTarget(email)) { providers in onMove(email, providers) }
        .scaleEffect(isOn ? 1.04 : 1)
        .shadow(color: isOn ? ThingsColor.accent.opacity(0.4) : .clear, radius: 10, x: 0, y: 3)
        .opacity(hovered == nil || isOn ? 1 : 0.5)
    }
}

@Observable
private final class MoveZoneModel {
    var triggerTargeted = false
    var cardTargeted = false
    var hovered: String?

    var isTargeted: Bool { triggerTargeted || cardTargeted || hovered != nil }
}
