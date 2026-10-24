import Observation
import SwiftUI

/// Een paneel dat boven op het hoofdvenster ligt (mail of Claude-analyse), in plaats van een los venster.
enum PanelKind: Hashable, Identifiable {
    case mail(MailRef)
    case claude
    case event(AgendaEvent)
    case compose(ComposeRef)

    var isEvent: Bool {
        if case .event = self { return true }
        return false
    }

    /// Mail en opstellen openen en sluiten met de Duo-vouw (`DuoFold`); de rest vervaagt.
    var foldsLikeDuo: Bool {
        switch self {
        case .mail, .compose: true
        case .claude, .event: false
        }
    }

    var id: String {
        switch self {
        case .compose(let ref): "compose-\(ref.id)"
        case .event(let event): "event-\(event.id)"
        case .mail(let ref): "mail-\(ref.messageID)"
        case .claude: "claude"
        }
    }
}

/// Welke panelen open staan. Maximaal twee; opent er een derde, dan verdwijnt de oudste.
@MainActor
@Observable
final class PanelStore {
    static let shared = PanelStore()

    private(set) var panels: [PanelKind] = []
    /// Panelen waarin je iets doet (antwoord, analyse, invoer). Die sluiten niet bij een klik ernaast.
    @ObservationIgnored private var engagedIDs: Set<String> = []

    /// Mail- en Claude-panelen: daarvoor gaat de rest van de app in de blur.
    var hasFocusPanels: Bool { panels.contains { !$0.isEvent } }

    func markEngaged(_ id: String) { engagedIDs.insert(id) }

    /// Klik naast de panelen: sluit wat alleen gelezen werd. Afspraken regelen dat zelf (wijzigingen gaan voor).
    func closeUnengaged() {
        let closing = panels.filter { !$0.isEvent && !engagedIDs.contains($0.id) }
        withAnimation(Self.animation(for: closing, opening: false)) {
            panels.removeAll { !$0.isEvent && !engagedIDs.contains($0.id) }
        }
        engagedIDs.formIntersection(Set(panels.map(\.id)))
    }

    private static func animation(for panels: [PanelKind], opening: Bool) -> Animation {
        guard panels.contains(where: \.foldsLikeDuo) else { return .easeOut(duration: 0.18) }
        return opening ? DuoFold.opening : DuoFold.closing
    }

    func open(_ panel: PanelKind) {
        withAnimation(Self.animation(for: [panel], opening: true)) {
            panels.removeAll { $0.id == panel.id }
            panels.append(panel)
            if panels.count > 2 { panels.removeFirst(panels.count - 2) }
        }
        engagedIDs.formIntersection(Set(panels.map(\.id)))
    }

    func close(_ panel: PanelKind) {
        withAnimation(Self.animation(for: [panel], opening: false)) { panels.removeAll { $0.id == panel.id } }
        engagedIDs.remove(panel.id)
    }

    func closeMail(messageID: String) {
        close(id: "mail-\(messageID)")
    }

    /// Sluit een paneel op id (na versturen: het gesprek of opstelblok vouwt dicht).
    func close(id: String) {
        guard let panel = panels.first(where: { $0.id == id }) else { return }
        close(panel)
    }
}

/// Legt de open panelen in het midden van het venster: één paneel met ±20% ruimte links en rechts,
/// twee panelen elk de helft. Tijdens het slepen van een mail worden ze onzichtbaar, zodat de doelen vrij liggen.
struct PanelOverlay: View {
    private let store = PanelStore.shared
    private let dragState = MailDragState.shared

    var body: some View {
        GeometryReader { geo in
            let single = store.panels.count < 2
            let width = single ? geo.size.width * 0.6 : (geo.size.width - 36) / 2
            HStack(spacing: 12) {
                ForEach(store.panels) { panel in
                    PanelChrome(panel: panel)
                        .transition(panel.foldsLikeDuo
                                    ? AnyTransition.duoFold(width: width, shadow: ThingsColor.cardShadow)
                                    : AnyTransition.opacity.combined(with: .scale(scale: 0.97)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, single ? geo.size.width * 0.2 : 12)
            .padding(.vertical, 20)
            .opacity(dragState.isDragging ? 0 : 1)
            .allowsHitTesting(!dragState.isDragging)
            .animation(.easeOut(duration: 0.15), value: dragState.isDragging)
        }
    }
}

private struct PanelChrome: View {
    let panel: PanelKind

    var body: some View {
        Group {
            switch panel {
            case .mail(let ref):
                MailWindowView(ref: ref)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            PanelStore.shared.close(panel)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(ThingsColor.textTertiary)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .help("Sluiten")
                    }
            case .claude:
                ClaudeAnalysisView()
            case .compose(let ref):
                ComposeView(ref: ref)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            PanelStore.shared.close(panel)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(ThingsColor.textTertiary)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .help("Sluiten zonder te versturen")
                    }
            case .event(let event):
                EventDetailView(target: .existing(event)) { PanelStore.shared.close(panel) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ThingsColor.separator))
        // Binnen de Duo-vouw valt deze schaduw weg (afgesneden door de vouwvorm); het effect tekent er dan zelf een.
        .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
    }
}
