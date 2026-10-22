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
    /// Panelen die nu wegklappen (na het versturen van een mail).
    private(set) var foldingIDs: Set<String> = []
    /// Panelen waarin je iets doet (antwoord, analyse, invoer). Die sluiten niet bij een klik ernaast.
    @ObservationIgnored private var engagedIDs: Set<String> = []

    /// Mail- en Claude-panelen: daarvoor gaat de rest van de app in de blur.
    var hasFocusPanels: Bool { panels.contains { !$0.isEvent } }

    func markEngaged(_ id: String) { engagedIDs.insert(id) }

    /// Klik naast de panelen: sluit wat alleen gelezen werd. Afspraken regelen dat zelf (wijzigingen gaan voor).
    func closeUnengaged() {
        withAnimation(.easeOut(duration: 0.18)) {
            panels.removeAll { !$0.isEvent && !engagedIDs.contains($0.id) }
        }
        engagedIDs.formIntersection(Set(panels.map(\.id)))
    }

    static let foldDuration = 0.30

    func open(_ panel: PanelKind) {
        withAnimation(.easeOut(duration: 0.18)) {
            panels.removeAll { $0.id == panel.id }
            panels.append(panel)
            if panels.count > 2 { panels.removeFirst(panels.count - 2) }
        }
        engagedIDs.formIntersection(Set(panels.map(\.id)))
    }

    func close(_ panel: PanelKind) {
        withAnimation(.easeOut(duration: 0.18)) { panels.removeAll { $0.id == panel.id } }
        engagedIDs.remove(panel.id)
    }

    func closeMail(messageID: String) {
        withAnimation(.easeOut(duration: 0.18)) { panels.removeAll { $0.id == "mail-\(messageID)" } }
        engagedIDs.remove("mail-\(messageID)")
    }

    /// Klapt een paneel van boven naar achteren weg (zoals een blad dat omvalt) en haalt het daarna weg.
    func foldAway(id: String) {
        guard panels.contains(where: { $0.id == id }), !foldingIDs.contains(id) else { return }
        withAnimation(.easeIn(duration: Self.foldDuration)) { _ = foldingIDs.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.foldDuration + 0.05))
            panels.removeAll { $0.id == id }
            foldingIDs.remove(id)
            engagedIDs.remove(id)
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
            HStack(spacing: 12) {
                ForEach(store.panels) { panel in
                    PanelChrome(panel: panel)
                        .modifier(FoldAwayEffect(angle: store.foldingIDs.contains(panel.id) ? 90 : 0))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
    }
}

/// Wegklappen naar achteren rond de onderrand; hoe verder, hoe donkerder (zelfde stijl als de Maandagenda).
private struct FoldAwayEffect: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(Color.black.opacity(0.3 * min(angle / 90, 1)).allowsHitTesting(false))
            .opacity(angle >= 89 ? 0 : 1)
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, anchorZ: 0, perspective: 0.35)
            .allowsHitTesting(angle == 0)
    }
}
