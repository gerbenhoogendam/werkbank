import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// De iPhone-app (nieuw ontwerp, canvas "Werkbank iOS"): vier onderdelen onder een eigen tabbalk in de stijl Etiket.
/// Snelle acties op het beginscherm openen nog steeds de tijdinvoer.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @State private var tab: PhTab = .mail
    /// Verbetering: eerst het scherm vastleggen, dan het blad.
    @State private var feedback: FeedbackStart?

    var body: some View {
        @Bindable var state = appState

        ZStack {
            Group {
                switch tab {
                case .mail: MailHome()
                case .agenda: AgendaHome()
                case .tijd: TijdHome()
                case .board: BoardHome()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PhTabBar(tab: $tab, timerRunning: !running.isEmpty)
            }

            ToastOverlay(message: appState.toast)
        }
        .phScreen()
        .preferredColorScheme(.light)
        .scrollIndicators(.never)
        .sheet(item: $state.timeEntry) { start in
            TimeEntrySheet(start: start) { appState.timeEntry = nil }
                .presentationDetents([.large])
        }
        .sheet(item: $feedback) { start in
            FeedbackDictationSheet(screenshot: start.screenshot)
                .presentationDetents([.large])
        }
        .sheet(item: $state.stopContext) { stop in
            if let entry = TimerService.entry(withID: stop.entryID, in: context) {
                StopSheet(entry: entry, defaultEnd: stop.defaultEnd)
                    .presentationDetents([.large])
            }
        }
        .task {
            PhoneDictation.shared.refresh()
            await PhonePreferencesSync.shared.pull()
            PhoneStars.shared.reload()
        }
        // Het spraakmodel uit het geheugen als de app weg is; terug in beeld gaat een onderbroken download verder.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: PhoneDictation.shared.unload()
            case .active:
                PhoneDictation.shared.refresh()
                Task {
                    await PhonePreferencesSync.shared.pull()
                    PhoneStars.shared.reload()
                    await PhoneGmail.shared.reloadAll()
                }
            default: break
            }
        }
    }
}

enum PhTab: String, CaseIterable {
    case mail, agenda, tijd, board

    var title: String {
        switch self {
        case .mail: "Mail"
        case .agenda: "Agenda"
        case .tijd: "Tijd"
        case .board: "Board"
        }
    }

    var symbol: String {
        switch self {
        case .mail: "envelope"
        case .agenda: "calendar"
        case .tijd: "clock"
        case .board: "rectangle.split.3x1"
        }
    }
}

/// De tabbalk: inktlijn erboven, het gekozen onderdeel limoen en verzonken; een oranje stip als er tijd loopt.
struct PhTabBar: View {
    @Binding var tab: PhTab
    let timerRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PhTab.allCases, id: \.self) { item in
                let on = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .medium))
                        Text(item.title.uppercased())
                            .font(Ph.text(10, .semibold))
                            .tracking(1.6)
                    }
                    .foregroundStyle(on ? Ph.ink : Ph.ink2)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .background {
                        if on {
                            Rectangle().fill(Ph.lime.shadow(.inner(color: Ph.ink.opacity(0.22), radius: 1.5, y: 2)))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item == .tijd && timerRunning {
                            Circle().fill(Ph.late).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Ph.paper, lineWidth: 2))
                                .padding(.top, 6).padding(.trailing, 14)
                                .accessibilityLabel("Tijd loopt")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 4)
        .background {
            Rectangle().fill(Ph.paper.shadow(.drop(color: Ph.ink.opacity(0.05), radius: 7, y: -4)))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
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

/// Het blad Verbetering met de screenshot van het moment dat je erop tikte.
struct FeedbackStart: Identifiable {
    let id = UUID()
    let screenshot: CapturedScreen
}
