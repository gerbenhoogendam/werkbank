import SwiftData
import SwiftUI

/// Hoofdvenster: board boven (±45%), agenda onder links (¾), Tijd schrijven onder rechts (¼).
struct MainView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(DragCoordinator.self) private var drag

    var body: some View {
        @Bindable var state = appState

        ZStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    BoardView()
                        .frame(height: geo.size.height * 0.45)
                    Rectangle().fill(ThingsColor.separator).frame(height: 1)
                    HStack(spacing: 0) {
                        AgendaView()
                            .frame(width: geo.size.width * 0.75)
                        Rectangle().fill(ThingsColor.separator).frame(width: 1)
                        TimeListView()
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
        .onDrop(of: [.emailMessage, .fileURL], isTargeted: $state.isDropTargeted) { providers in
            MailImporter.handle(providers: providers, context: context, appState: appState)
        }
        .sheet(item: $state.stopContext) { stop in
            if let entry = TimerService.allEntries(in: context).first(where: { $0.id == stop.entryID }) {
                StopSheet(entry: entry, defaultEnd: stop.defaultEnd)
            }
        }
        .toolbar {
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
                Text("Laat los om de mail aan de Inbox toe te voegen")
                    .thingsFont(.listTitle)
            }
            .foregroundStyle(ThingsColor.accent)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

#if DEBUG
/// Tijdelijke diagnose van het slepen; verdwijnt zodra het slepen bevestigd werkt.
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
