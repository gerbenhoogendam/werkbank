import AppKit
import SwiftData
import SwiftUI

/// Hoofdvenster: board boven (±45%), agenda onder links (¾), Tijd schrijven onder rechts (¼).
struct MainView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(DragCoordinator.self) private var drag

    // Verdeling van het venster; bewaard tussen sessies. Dubbelklik op een scheidingslijn zet hem terug.
    @AppStorage("layout.boardFraction") private var boardFraction = Self.defaultBoardFraction
    @AppStorage("layout.agendaFraction") private var agendaFraction = Self.defaultAgendaFraction
    // Gmail-paneel links (standaard verborgen); breedte schuifbaar en bewaard.
    @AppStorage("gmail.panelVisible") private var gmailVisible = false
    @AppStorage("gmail.panelWidth") private var gmailWidth = Self.defaultGmailWidth
    @State private var boardDragStart: Double?
    @State private var agendaDragStart: Double?
    @State private var gmailDragStart: Double?

    private static let defaultGmailWidth = 300.0
    private static let gmailRange = 240.0...480.0

    private static let defaultBoardFraction = 0.45
    private static let defaultAgendaFraction = 0.75
    private static let boardRange = 0.18...0.72
    private static let agendaRange = 0.35...0.85

    var body: some View {
        @Bindable var state = appState

        ZStack {
            HStack(spacing: 0) {
                if gmailVisible {
                    GmailPanel()
                        .frame(width: clamp(gmailWidth, Self.gmailRange))
                    SplitDivider(isHorizontalLine: false,
                                 label: "Schuif de breedte van het Gmail-paneel",
                                 onChanged: { translation in
                                     let start = gmailDragStart ?? gmailWidth
                                     gmailDragStart = start
                                     gmailWidth = clamp(start + Double(translation), Self.gmailRange)
                                 },
                                 onEnded: { gmailDragStart = nil },
                                 onReset: { gmailWidth = Self.defaultGmailWidth })
                        .zIndex(1)
                }
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        BoardView()
                            .frame(height: geo.size.height * clamp(boardFraction, Self.boardRange))
                        SplitDivider(isHorizontalLine: true,
                                     onChanged: { translation in
                                         let start = boardDragStart ?? boardFraction
                                         boardDragStart = start
                                         boardFraction = clamp(start + Double(translation / geo.size.height), Self.boardRange)
                                     },
                                     onEnded: { boardDragStart = nil },
                                     onReset: { boardFraction = Self.defaultBoardFraction })
                            .zIndex(1)
                        HStack(spacing: 0) {
                            AgendaView()
                                .frame(width: geo.size.width * clamp(agendaFraction, Self.agendaRange))
                            SplitDivider(isHorizontalLine: false,
                                         onChanged: { translation in
                                             let start = agendaDragStart ?? agendaFraction
                                             agendaDragStart = start
                                             agendaFraction = clamp(start + Double(translation / geo.size.width), Self.agendaRange)
                                         },
                                         onEnded: { agendaDragStart = nil },
                                         onReset: { agendaFraction = Self.defaultAgendaFraction })
                                .zIndex(1)
                            TimeListView()
                        }
                    }
                }
            }

            if appState.isDropTargeted { dropOverlay }

            DragOverlay()
            ToastOverlay(message: appState.toast)
            #if DEBUG
            DragDebugHUD()
            #endif

            // Esc: annuleert een lopend concept op de agenda.
            Button("") { drag.draft = nil }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .coordinateSpace(.named("main"))
        .background(ThingsColor.backgroundContent)
        .onDrop(of: [.emailMessage, .fileURL, .gmailMessage], isTargeted: $state.isDropTargeted) { providers in
            if GmailDrop.accepts(providers) {
                return GmailDrop.handle(providers: providers, column: .inbox, context: context, appState: appState)
            }
            return MailImporter.handle(providers: providers, context: context, appState: appState)
        }
        .sheet(item: $state.stopContext) { stop in
            if let entry = TimerService.allEntries(in: context).first(where: { $0.id == stop.entryID }) {
                StopSheet(entry: entry, defaultEnd: stop.defaultEnd)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { gmailVisible.toggle() }
                } label: {
                    Label("Gmail", systemImage: "sidebar.left")
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .help("Gmail-paneel tonen of verbergen (⌥⌘G)")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Voorkeuren", systemImage: "gearshape")
                }
                .help("Voorkeuren (⌘,)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    QuickEntryController.shared.show()
                } label: {
                    Label("Snelle invoer ⌥⌘T", systemImage: "plus.circle.fill")
                }
                .help("Nieuwe kaart in de Inbox (werkt ook vanuit andere apps met de sneltoets)")
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Rectangle().fill(ThingsColor.accent.opacity(0.10))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ThingsColor.accent, style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
                .padding(10)
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 34))
                Text("Laat los op een kolom om de mail daar toe te voegen")
                    .thingsFont(.listTitle)
            }
            .foregroundStyle(ThingsColor.accent)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

/// Scheidingslijn tussen twee panelen die je door te slepen kunt verschuiven.
private struct SplitDivider: View {
    /// `true`: een horizontale lijn (verschuift op en neer); `false`: een verticale lijn (links/rechts).
    let isHorizontalLine: Bool
    var label: String? = nil
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let onReset: () -> Void

    @State private var isHovering = false

    private static let thickness: CGFloat = 7

    var body: some View {
        // Een echt klikvlak van 7 pt (geen overlay buiten de eigen afmetingen), met de zichtbare lijn in het midden.
        ZStack {
            Rectangle().fill(ThingsColor.backgroundContent)
            Rectangle()
                .fill(isHovering ? ThingsColor.accent : ThingsColor.separator)
                .frame(width: isHorizontalLine ? nil : (isHovering ? 2 : 1),
                       height: isHorizontalLine ? (isHovering ? 2 : 1) : nil)
        }
        .frame(width: isHorizontalLine ? nil : Self.thickness, height: isHorizontalLine ? Self.thickness : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
            if inside {
                (isHorizontalLine ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    onChanged(isHorizontalLine ? value.translation.height : value.translation.width)
                }
                .onEnded { _ in onEnded() }
        )
            .accessibilityLabel(label ?? (isHorizontalLine ? "Schuif de verdeling tussen board en agenda"
                                                           : "Schuif de verdeling tussen agenda en Tijd schrijven"))
    }
}

#if DEBUG
/// Tijdelijke diagnose van het slepen; verdwijnt zodra het slepen naar de agenda bevestigd werkt.
private struct DragDebugHUD: View {
    @Environment(DragCoordinator.self) private var drag

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            Text(drag.debugSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}
#endif
