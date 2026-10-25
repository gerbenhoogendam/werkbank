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
    /// Panelen waarvan nu een afbeelding boven het venster wegvouwt (`DuoWindowFold`); het paneel zelf verdwijnt meteen.
    private(set) var ghostedIDs: Set<String> = []
    /// Panelen waarin je iets doet (antwoord, analyse, invoer). Die sluiten niet bij een klik ernaast.
    @ObservationIgnored private var engagedIDs: Set<String> = []

    /// Mail- en Claude-panelen: daarvoor gaat de rest van de app in de blur.
    var hasFocusPanels: Bool { panels.contains { !$0.isEvent } }

    func markEngaged(_ id: String) { engagedIDs.insert(id) }

    /// Klik naast de panelen: sluit wat alleen gelezen werd. Afspraken regelen dat zelf (wijzigingen gaan voor).
    func closeUnengaged() {
        remove(panels.filter { !$0.isEvent && !engagedIDs.contains($0.id) }, part: .mailClose)
    }

    func open(_ panel: PanelKind) {
        ghostedIDs.remove(panel.id)
        withAnimation(panel.foldsLikeDuo ? DuoFold.opening(.mailOpen) : .easeOut(duration: 0.18)) {
            panels.removeAll { $0.id == panel.id }
            panels.append(panel)
            if panels.count > 2 { panels.removeFirst(panels.count - 2) }
        }
        engagedIDs.formIntersection(Set(panels.map(\.id)))
    }

    func close(_ panel: PanelKind) {
        remove([panel], part: .mailClose)
    }

    /// `snapshot: false` als het paneel net niet in beeld was (slepen naar een andere mailbox): dan geen afbeelding.
    func closeMail(messageID: String, snapshot: Bool = true) {
        guard let panel = panels.first(where: { $0.id == "mail-\(messageID)" }) else { return }
        remove([panel], part: .mailClose, snapshot: snapshot)
    }

    /// Alle mailpanelen van een gesprek (na archiveren).
    func closeThread(_ threadID: String) {
        remove(panels.filter { panel in
            if case .mail(let ref) = panel { return ref.threadID == threadID }
            return false
        }, part: .mailClose)
    }

    /// Na versturen: het gesprek of opstelblok vouwt weg.
    func closeAfterSending(id: String) {
        guard let panel = panels.first(where: { $0.id == id }) else { return }
        remove([panel], part: .send)
    }

    /// Mail en opstellen: eerst een afbeelding laten wegvouwen (echt matglas), anders de benaderde vouw van het paneel.
    private func remove(_ closing: [PanelKind], part: FoldSpeed, snapshot: Bool = true) {
        guard !closing.isEmpty else { return }
        engagedIDs.subtract(closing.map(\.id))
        var ghosted: Set<String> = []
        for panel in closing where snapshot && panel.foldsLikeDuo {
            if DuoWindowFold.shared.foldAway(panelID: panel.id, part: part) { ghosted.insert(panel.id) }
        }
        let live = closing.filter { !ghosted.contains($0.id) }
        if !live.isEmpty {
            let liveIDs = Set(live.map(\.id))
            withAnimation(live.contains(where: \.foldsLikeDuo) ? DuoFold.closing(part) : .easeOut(duration: 0.18)) {
                panels.removeAll { liveIDs.contains($0.id) }
            }
        }
        guard !ghosted.isEmpty else { return }
        ghostedIDs.formUnion(ghosted)
        Task { @MainActor in
            // Eerst de overgang zonder vouw laten gelden, dan weghalen; de rest schuift gewoon op.
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.easeOut(duration: 0.18)) { panels.removeAll { ghosted.contains($0.id) } }
            try? await Task.sleep(for: .milliseconds(400))
            ghostedIDs.subtract(ghosted)
        }
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
            let height = max(geo.size.height - 40, 1)
            HStack(spacing: 12) {
                ForEach(store.panels) { panel in
                    PanelChrome(panel: panel)
                        .transition(panel.foldsLikeDuo
                                    ? AnyTransition.duoFold(height: height,
                                                            hidesInstantly: store.ghostedIDs.contains(panel.id))
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
                                .font(.werk(size: 17))
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
                                .font(.werk(size: 17))
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
        .background(PanelProbe(panelID: panel.id))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ThingsColor.separator))
        .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
    }
}
