import Observation
import SwiftUI

/// Een paneel dat boven op het hoofdvenster ligt (mail of Claude-analyse), in plaats van een los venster.
enum PanelKind: Hashable, Identifiable {
    case mail(MailRef)
    case claude
    case event(AgendaEvent)

    var id: String {
        switch self {
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

    func open(_ panel: PanelKind) {
        withAnimation(.easeOut(duration: 0.18)) {
            panels.removeAll { $0.id == panel.id }
            panels.append(panel)
            if panels.count > 2 { panels.removeFirst(panels.count - 2) }
        }
    }

    func close(_ panel: PanelKind) {
        withAnimation(.easeOut(duration: 0.18)) { panels.removeAll { $0.id == panel.id } }
    }

    func closeMail(messageID: String) {
        withAnimation(.easeOut(duration: 0.18)) { panels.removeAll { $0.id == "mail-\(messageID)" } }
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
            case .event(let event):
                EventDetailView(event: event)
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ThingsColor.separator))
        .shadow(color: ThingsColor.cardShadow, radius: 18, x: 0, y: 6)
    }
}
