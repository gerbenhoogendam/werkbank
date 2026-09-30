import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI
import WerkbankCore

/// Klokicoon in de menubalk; bij een lopende timer staat de verstreken tijd ernaast.
struct MenuBarLabel: View {
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            if let entry = running.first {
                Text(Billing.formatHMS(entry.elapsed(at: now)))
                    .monospacedDigit()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

/// Paneel achter de menubalkknop: lopende timer, bestaande to-do starten of snelle support.
struct MenuBarPanel: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case todo = "Bestaande to-do"
        case support = "Snelle support"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState
    @Query(sort: \TodoCard.sortOrder) private var cards: [TodoCard]
    @Query(filter: #Predicate<TimeEntry> { $0.statusRaw == "running" }) private var running: [TimeEntry]

    @State private var mode: Mode = .todo
    @State private var selectedID: UUID?

    private var openCards: [TodoCard] { cards.filter { $0.column != .done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry = running.first {
                runningSection(entry)
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .todo:    todoSection
            case .support: SupportEntryView { closePanel() }
            }

            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            Text("Snelle invoer: \(shortcutDescription)")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
        }
        .padding(14)
        .frame(width: 340)
        .background(ThingsColor.backgroundContent)
    }

    private var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: .quickEntry)?.description ?? "niet ingesteld"
    }

    // MARK: Lopende timer

    private func runningSection(_ entry: TimeEntry) -> some View {
        HStack(spacing: 10) {
            Circle().fill(ThingsColor.running).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).thingsFont(.todoTitleOpen).lineLimit(1)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text(entry.client).thingsFont(.metadata).lineLimit(1)
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(Billing.formatHMS(entry.elapsed(at: timeline.date)))
                    .thingsFont(.todoTitleOpen)
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textPrimary)
            }
            SmallIconButton(symbol: "pause.fill", label: "Pauze") {
                TimerService.pause(entry, in: context)
            }
            SmallIconButton(symbol: "stop.fill", label: "Stop") {
                // De stopsheet staat in het hoofdvenster: open en activeer dat.
                appState.requestStop(entry, in: context)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                closePanel()
            }
        }
    }

    // MARK: Bestaande to-do

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if openCards.isEmpty {
                Text("Geen open to-do's")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(openCards) { card in
                            Button { selectedID = card.id } label: {
                                HStack {
                                    Text(card.title)
                                        .thingsFont(.todoTitle)
                                        .foregroundStyle(ThingsColor.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(card.column.title)
                                        .thingsFont(.metadata)
                                        .foregroundStyle(ThingsColor.textSecondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                                        .fill(selectedID == card.id ? ThingsColor.selection : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }

            HStack {
                Spacer()
                Button("Start timer") {
                    guard let card = openCards.first(where: { $0.id == selectedID }) else { return }
                    TimerService.startTimer(for: card, in: context)
                    appState.showToast("Timer gestart: \(card.title)")
                    selectedID = nil
                    closePanel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedID == nil)
            }
        }
    }

    /// Sluit het menubalkpaneel (het is het key-venster zolang het openstaat).
    private func closePanel() {
        NSApp.keyWindow?.orderOut(nil)
    }
}
