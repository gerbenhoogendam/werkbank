import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Lijst "Tijd schrijven": lopende timer bovenaan, daaronder de regels (nieuwste eerst).
struct TimeListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TimeEntry.createdAt, order: .reverse) private var entries: [TimeEntry]

    @State private var showSupport = false
    @State private var exportDocument = CSVDocument(data: Data())
    @State private var isExporting = false

    private var running: TimeEntry? { entries.first { $0.status == .running } }
    private var others: [TimeEntry] { entries.filter { $0.status != .running } }
    private var outstanding: Double { TimerService.outstandingHours(entries) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)

            if entries.isEmpty {
                ThingsEmptyStateSymbol(symbol: "clock", text: "Nog geen tijdregels")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let running {
                            RunningTimerRow(entry: running)
                                .padding(.bottom, 6)
                        }
                        ForEach(others) { entry in
                            TimeEntryRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(ThingsColor.backgroundContent)
        .fileExporter(isPresented: $isExporting, document: exportDocument,
                      contentType: .commaSeparatedText, defaultFilename: "Werkbank-tijd") { result in
            if case .success = result { appState.showToast("Export bewaard") }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tijd schrijven")
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.accent)
                Text("Nog te factureren: \(Billing.formatHours(outstanding)) u")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Menu {
                Button("Alle afgeronde regels") { export(onlyUnwritten: false) }
                Button("Alleen nog niet geschreven") { export(onlyUnwritten: true) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Exporteer afgeronde regels als CSV")

            Button { showSupport = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThingsColor.accent)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Snelle support")
            .accessibilityLabel("Snelle support")
            .popover(isPresented: $showSupport, arrowEdge: .bottom) {
                SupportEntryView { showSupport = false }
                    .frame(width: 300)
                    .padding(12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func export(onlyUnwritten: Bool) {
        let lines = entries
            .filter { $0.status == .finished && (!onlyUnwritten || !$0.isWritten) }
            .sorted { ($0.finishedAt ?? $0.createdAt) < ($1.finishedAt ?? $1.createdAt) }
            .map(\.billingLine)
        let exporter: BillingExporter = CSVBillingExporter()
        guard let data = try? exporter.export(lines) else { return }
        exportDocument = CSVDocument(data: data)
        isExporting = true
    }
}

struct ThingsEmptyStateSymbol: View {
    let symbol: String
    var text: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(ThingsColor.textTertiary.opacity(0.6))
            if let text {
                Text(text).thingsFont(.metadata).foregroundStyle(ThingsColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lopende timer

struct RunningTimerRow: View {
    let entry: TimeEntry
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ThingsColor.running)
                .frame(width: 9, height: 9)
                .opacity(pulse ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                Text(entry.client)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
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
                appState.requestStop(entry, in: context)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                .fill(ThingsColor.running.opacity(0.10))
        )
    }
}

struct SmallIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = ThingsColor.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(ThingsColor.tagBackground))
                .frame(width: ThingsMetrics.minTapTarget * 0.6, height: ThingsMetrics.minTapTarget * 0.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Overige regels

struct TimeEntryRow: View {
    let entry: TimeEntry
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private var writtenBinding: Binding<TodoStatus> {
        Binding(
            get: { entry.isWritten ? .completed : .open },
            set: { TimerService.setWritten(entry, $0 == .completed, in: context) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            TodoCheckbox(status: writtenBinding, title: entry.title)
                .disabled(entry.status != .finished)
                .help(entry.status == .finished ? "Geschreven in het facturatiesysteem" : "Stop eerst de timer")

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .thingsFont(.todoTitle)
                    .strikethrough(entry.isWritten)
                    .foregroundStyle(entry.isWritten ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Text(trailingTime)
                .thingsFont(.todoTitle)
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textSecondary)

            controls
        }
        .frame(minHeight: 44)
        .opacity(entry.isWritten ? 0.55 : 1)
        .help(entry.status == .finished
              ? entry.workDescription + (entry.correctionSeconds > 0
                  ? "\nGemeten \(Billing.formatHM(entry.accumulated)) u, correctie −\(Int((entry.correctionSeconds / 60).rounded())) min"
                  : "")
              : "")
        .contextMenu {
            if entry.status == .finished {
                Button(entry.isWritten ? "Markeer als niet geschreven" : "Markeer als geschreven") {
                    TimerService.setWritten(entry, !entry.isWritten, in: context)
                }
            }
            Button("Verwijderen", role: .destructive) {
                context.delete(entry)
                TimerService.save(context)
            }
        }
    }

    private var subtitle: String {
        var text = "\(entry.client) · \(entry.source.title)"
        if entry.status == .paused {
            text += entry.interruptions > 0 ? " · Pauze · \(entry.interruptions)× onderbroken" : " · Pauze"
        }
        return text
    }

    private var trailingTime: String {
        switch entry.status {
        case .finished: return "\(Billing.formatHours(TimerService.billedHours(entry))) u"
        default:        return Billing.formatHM(entry.accumulated)
        }
    }

    @ViewBuilder private var controls: some View {
        switch entry.status {
        case .notStarted:
            SmallIconButton(symbol: "play.fill", label: "Start", tint: ThingsColor.accent) {
                TimerService.start(entry, in: context)
            }
        case .paused:
            SmallIconButton(symbol: "play.fill", label: "Hervat", tint: ThingsColor.accent) {
                TimerService.start(entry, in: context)
            }
            SmallIconButton(symbol: "stop.fill", label: "Stop") {
                appState.requestStop(entry, in: context)
            }
        case .running, .finished:
            EmptyView()
        }
    }
}
