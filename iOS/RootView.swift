import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// iPhone/iPad: twee tabs (Board, Tijd) in Things-stijl. De Magic Plus rechtsonder schrijft tijd (klant, case,
/// uitgevoerd), net als de snelle actie op het beginscherm.
struct RootView: View {
    enum Tab: Hashable { case board, time }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var tab: Tab = .board
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var isImporting = false

    var body: some View {
        @Bindable var state = appState

        ZStack {
            TabView(selection: $tab) {
                NavigationStack {
                    BoardListView()
                        .toolbar { boardToolbar }
                        .tabChrome(running: running, plus: enterTime)
                }
                .tabItem { Label("Board", systemImage: "square.grid.2x2") }
                .tag(Tab.board)

                NavigationStack {
                    TimeListView()
                        .toolbar { settingsToolbar }
                        .tabChrome(running: [], plus: enterTime)
                }
                .tabItem { Label("Tijd", systemImage: "clock") }
                .tag(Tab.time)
            }

            ToastOverlay(message: appState.toast)
        }
        .preferredColorScheme(AppearanceSetting(stored: appearanceRaw).colorScheme)
        .scrollIndicators(.never)
        .sheet(isPresented: $state.isEnteringTime) {
            TimeEntrySheet { appState.isEnteringTime = false }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showArchive) {
            NavigationStack {
                ArchiveView()
                    .navigationTitle("Archief")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { showArchive = false } } }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PreferencesView()
                    .navigationTitle("Voorkeuren")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { showSettings = false } } }
            }
        }
        .sheet(item: $state.stopContext) { stop in
            if let entry = TimerService.allEntries(in: context).first(where: { $0.id == stop.entryID }) {
                StopSheet(entry: entry, defaultEnd: stop.defaultEnd)
                    .presentationDetents([.large])
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [UTType(filenameExtension: "eml") ?? .data, .emailMessage],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                MailImporter.handle(urls: urls, context: context, appState: appState)
            }
        }
        // Slepen van .eml-bestanden (iPad, Split View).
        .onDrop(of: [.emailMessage, .fileURL], isTargeted: $state.isDropTargeted) { providers in
            MailImporter.handle(providers: providers, context: context, appState: appState)
        }
        .overlay {
            if appState.isDropTargeted {
                ZStack {
                    ThingsColor.accent.opacity(0.10)
                    Text("Laat los om de mail aan de Inbox toe te voegen")
                        .thingsFont(.listTitle)
                        .foregroundStyle(ThingsColor.accent)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .task { PhoneDictation.shared.refresh() }
        // Het spraakmodel uit het geheugen als de app weg is; terug in beeld gaat een onderbroken download verder.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: PhoneDictation.shared.unload()
            case .active: PhoneDictation.shared.refresh()
            default: break
            }
        }
    }

    private func enterTime() {
        appState.isEnteringTime = true
    }

    @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Instellingen")
        }
    }

    @ToolbarContentBuilder private var boardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Instellingen")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showArchive = true } label: { Image(systemName: "archivebox") }
                .accessibilityLabel("Archief")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { isImporting = true } label: { Label("Importeer .eml…", systemImage: "envelope") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

/// Nieuwe kaart in een kolom (plus in de kolomkop) met `#klant` voor een label.
struct QuickAddSheet: View {
    let column: BoardColumn
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nieuwe kaart in \(column.title)")
                .thingsFont(.listTitle)
                .foregroundStyle(ThingsColor.textPrimary)
            TextField("Titel — #klant voor een label", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
            HStack {
                Button("Annuleer") { dismiss() }
                Spacer()
                Button("Voeg toe", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .presentationDetents([.height(190)])
        .onAppear { focused = true }
    }

    private func add() {
        guard BoardService.addQuickEntry(text, column: column, in: context) != nil else { return }
        appState.showToast("Toegevoegd aan \(column.title)")
        dismiss()
    }
}

private extension View {
    /// Lopende-timerbalk en Magic Plus (tijd schrijven) binnen een tab, zodat ze boven de tabbalk staan.
    func tabChrome(running: [TimeEntry], plus: @escaping () -> Void) -> some View {
        self
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !running.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(running) { entry in RunningTimerRow(entry: entry) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                MagicPlusButton(title: "Tijd schrijven", action: plus)
                    .padding(ThingsMetrics.magicPlusInset)
            }
    }
}
