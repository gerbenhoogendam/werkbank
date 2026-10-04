import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// iPhone/iPad: drie tabs (Board, Agenda, Tijd) in Things-stijl, met Magic Plus rechtsonder.
struct RootView: View {
    enum Tab: Hashable { case board, agenda, time }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]
    @Query(sort: \ColumnRecord.sortOrder) private var columnRecords: [ColumnRecord]

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var tab: Tab = .board
    /// Kolom die het meest in beeld is (voor de Magic Plus).
    @State private var columnID: String? = BoardColumn.inboxID
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var showQuickAdd = false
    @State private var showSupport = false
    @State private var isImporting = false

    private var currentColumn: BoardColumn {
        let columns = columnRecords.map(\.column)
        return columns.first { $0.id == columnID } ?? columns.first ?? .inbox
    }

    var body: some View {
        @Bindable var state = appState

        ZStack {
            TabView(selection: $tab) {
                NavigationStack {
                    BoardListView(columnID: $columnID)
                        .toolbar { boardToolbar }
                        .tabChrome(running: running.first, plus: { showQuickAdd = true })
                }
                .tabItem { Label("Board", systemImage: "square.grid.2x2") }
                .tag(Tab.board)

                NavigationStack {
                    DayAgendaView()
                        .toolbar { settingsToolbar }
                        .tabChrome(running: running.first, plus: nil)
                }
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(Tab.agenda)

                NavigationStack {
                    TimeListView()
                        .toolbar { settingsToolbar }
                        .tabChrome(running: nil, plus: { showSupport = true })
                }
                .tabItem { Label("Tijd", systemImage: "clock") }
                .tag(Tab.time)
            }

            ToastOverlay(message: appState.toast)
        }
        .preferredColorScheme(AppearanceSetting(stored: appearanceRaw).colorScheme)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showQuickAdd) { QuickAddSheet(column: currentColumn) }
        .sheet(isPresented: $showSupport) {
            NavigationStack {
                SupportEntryView { showSupport = false }
                    .padding()
                    .navigationTitle("Snelle support")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Sluit") { showSupport = false } } }
            }
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

/// Nieuwe kaart in de huidige kolom met `#klant` voor een label.
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
    /// Lopende-timerbalk en Magic Plus binnen een tab, zodat ze boven de tabbalk staan.
    func tabChrome(running: TimeEntry?, plus: (() -> Void)?) -> some View {
        self
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let running {
                    RunningTimerRow(entry: running)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let plus {
                    MagicPlusButton(action: plus)
                        .padding(ThingsMetrics.magicPlusInset)
                }
            }
    }
}
