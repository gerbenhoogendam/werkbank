import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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

    /// "Al geschreven" is standaard ingeklapt; de keuze blijft bewaard.
    @AppStorage("timeList.writtenExpanded") private var showWritten = false
    @State private var showSupport = false
    @State private var exportDocument = CSVDocument(data: Data())
    @State private var isExporting = false

    /// De regels in één keer verdeeld (niet per onderdeel van de weergave opnieuw filteren en sorteren).
    @MainActor
    private struct Parts {
        var running: TimeEntry?
        /// Nog te schrijven: bovenaan. Afgevinkte regels gaan naar "Al geschreven" onderaan.
        var toWrite: [TimeEntry] = []
        var written: [TimeEntry] = []
        var outstanding: Double = 0

        init(_ entries: [TimeEntry], sortWritten: Bool) {
            for entry in entries {
                switch (entry.status, entry.isWritten) {
                case (.running, _): if running == nil { running = entry }
                case (_, true): written.append(entry)
                default: toWrite.append(entry)
                }
            }
            outstanding = TimerService.outstandingHours(toWrite)
            // Alleen sorteren als de lijst open staat; dicht is het aantal genoeg.
            if sortWritten {
                written.sort { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) }
            }
        }
    }

    var body: some View {
        let parts = Parts(entries, sortWritten: showWritten)
        let running = parts.running
        let toWrite = parts.toWrite
        let written = parts.written
        return VStack(spacing: 0) {
            header(outstanding: parts.outstanding)
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
                        ForEach(toWrite) { entry in
                            TimeEntryRow(entry: entry)
                        }
                        if !written.isEmpty {
                            writtenHeader(count: written.count)
                            if showWritten {
                                ForEach(written) { entry in
                                    TimeEntryRow(entry: entry)
                                }
                            }
                        }
                    }
                    .animation(ThingsMotion.reorder, value: toWrite.map(\.id))
                    .animation(ThingsMotion.reorder, value: showWritten ? written.map(\.id) : [])
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

    /// Uitklapbare kop onder de regels die nog geschreven moeten worden.
    private func writtenHeader(count: Int) -> some View {
        Button {
            withAnimation(ThingsMotion.reorder) { showWritten.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showWritten ? 90 : 0))
                Text("Al geschreven")
                    .thingsFont(.heading)
                Text("\(count)")
                    .thingsFont(.metadata)
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(ThingsColor.textSecondary)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Al geschreven, \(count) regels, \(showWritten ? "uitgeklapt" : "ingeklapt")")
    }

    private func header(outstanding: Double) -> some View {
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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ThingsColor.running)
                .frame(width: 9, height: 9)
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
    /// Opengeklapt: klant, case en uitgevoerd, elk met een kopieerknop (voor het boekhoudpakket).
    @State private var expanded = false

    private var writtenBinding: Binding<TodoStatus> {
        Binding(
            get: { entry.isWritten ? .completed : .open },
            set: { TimerService.setWritten(entry, $0 == .completed, in: context) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
            if expanded, entry.status == .finished {
                BookingDetails(entry: entry)
                    .padding(.leading, 30)
                    .padding(.bottom, 10)
            }
        }
        .opacity(entry.isWritten && !expanded ? 0.55 : 1)
    }

    private var summaryRow: some View {
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
            .contentShape(Rectangle())
            .onTapGesture {
                guard entry.status == .finished else { return }
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }
            Spacer(minLength: 4)

            if entry.status == .finished {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(ThingsColor.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Inklappen" : "Klant, case en uitgevoerd tonen om te kopiëren")
            }

            Text(trailingTime)
                .thingsFont(.todoTitle)
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textSecondary)

            controls
        }
        .frame(minHeight: 44)
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
                TimerService.discard(entry, in: context)   // via discard: ⌘Z zet hem terug
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

// MARK: - Voor het boekhoudpakket

/// Klant, case en uitgevoerd van een afgeronde regel: aan te passen en per veld te kopiëren.
private struct BookingDetails: View {
    @Bindable var entry: TimeEntry
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("Klant", copy: entry.client == TimerService.noClient ? "" : entry.client) {
                TextField("", text: Binding(
                    get: { entry.client == TimerService.noClient ? "" : entry.client },
                    set: { entry.client = TimerService.normalized($0); TimerService.save(context) }))
            }
            field("Case", copy: entry.title) {
                TextField("", text: Binding(
                    get: { entry.title },
                    set: { entry.title = $0; TimerService.save(context) }))
            }
            field("Uitgevoerd", copy: entry.workDescription) {
                TextField("", text: Binding(
                    get: { entry.workDescription },
                    set: { entry.workDescription = $0; TimerService.save(context) }), axis: .vertical)
                    .lineLimit(1...8)
            }
            field("Uren", copy: Billing.formatHours(TimerService.billedHours(entry))) {
                Text(Billing.formatHours(TimerService.billedHours(entry)))
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textSecondary)
            }
        }
        .thingsFont(.notes)
    }

    private func field<Content: View>(_ label: String, copy text: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
                .frame(width: 70, alignment: .leading)
            content()
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: text)
        }
    }
}

/// Kopieert tekst naar het klembord; het icoon wordt even een vinkje.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? Color.green : ThingsColor.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help("Kopiëren")
        .accessibilityLabel("Kopieer")
    }
}
