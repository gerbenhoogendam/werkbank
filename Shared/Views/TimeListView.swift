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
    #if os(macOS)
    @State private var showDayClose = false
    #endif
    @State private var exportDocument = CSVDocument(data: Data())
    @State private var isExporting = false

    /// De regels in één keer verdeeld (niet per onderdeel van de weergave opnieuw filteren en sorteren).
    @MainActor
    private struct Parts {
        var running: [TimeEntry] = []
        /// Nog te schrijven: bovenaan. Afgevinkte regels gaan naar "Al geschreven" onderaan.
        var toWrite: [TimeEntry] = []
        var written: [TimeEntry] = []
        var outstanding: Double = 0

        init(_ entries: [TimeEntry], sortWritten: Bool) {
            for entry in entries {
                switch (entry.status, entry.isWritten) {
                case (.running, _): running.append(entry)
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
        let running = parts.running.sorted { ($0.firstStart ?? $0.createdAt) < ($1.firstStart ?? $1.createdAt) }
        let toWrite = parts.toWrite
        let written = parts.written
        let look = ThemeStore.shared.look
        return VStack(spacing: 0) {
            header(outstanding: parts.outstanding, count: toWrite.count)
            if look == .standaard { Rectangle().fill(ThingsColor.separator).frame(height: 1) }

            if entries.isEmpty {
                ThingsEmptyStateSymbol(symbol: "clock", text: "Nog geen tijdregels")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(running) { entry in
                            RunningTimerRow(entry: entry)
                                .padding(.bottom, 6)
                        }
                        ForEach(Array(toWrite.enumerated()), id: \.element.id) { offset, entry in
                            TimeEntryRow(entry: entry, index: offset + 1)
                        }
                        if !written.isEmpty {
                            writtenHeader(count: written.count)
                            if showWritten {
                                ForEach(Array(written.enumerated()), id: \.element.id) { offset, entry in
                                    TimeEntryRow(entry: entry, index: offset + 1)
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
            if look != .standaard {
                TimeTotalFooter(hours: parts.outstanding, count: toWrite.count)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        // Tischsuper: een teakrand langs de buitenkant, zoals de platenspeler (de andere zit links van de mail).
        .padding(.trailing, look == .tischsuper ? 9 : 0)
        .background(ThingsColor.timeListBackground)
        .overlay(alignment: .trailing) {
            if look == .tischsuper { ThemeParts.teak.frame(width: 9) }
        }
        .task { await ClientDirectory.shared.refresh() }   // logo's per klant
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
                    .font(.werk(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showWritten ? 90 : 0))
                if ThemeStore.shared.look == .karmijn {
                    KarmijnLabel(text: "Al geschreven")
                    Text("\(count)").font(.werkSerif(size: 15, italic: true))
                } else if ThemeStore.shared.look == .spark {
                    // Een grijze sectie zoals Folders in Spark, met het aantal in een grijs chipje.
                    Text("Al geschreven")
                        .font(.werk(size: 11.5))
                    Text("\(count)")
                        .font(.werk(size: 11))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ThingsColor.tagBackground))
                } else {
                    Text("Al geschreven")
                        .thingsFont(.heading)
                    Text("\(count)")
                        .thingsFont(.metadata)
                        .monospacedDigit()
                }
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

    private func header(outstanding: Double, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch ThemeStore.shared.look {
            case .standaard:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tijd schrijven")
                        .thingsFont(.heading)
                        .foregroundStyle(ThingsColor.accent)
                    Text("Nog te factureren: \(Billing.formatHours(outstanding)) u")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .monospacedDigit()
                }
            case .drukproef:
                VStack(alignment: .leading, spacing: 10) {
                    ThemedHeading(title: "Tijd schrijven", detail: "Te factureren (N°\(String(format: "%02d", count)))")
                    // Een kop in drie kleuren zoals op de poster.
                    (Text("\(DutchNumber.word(count)) \(count == 1 ? "regel" : "regels")").foregroundColor(ThingsColor.textPrimary)
                        + Text(" open -").foregroundColor(ThingsColor.today)
                        + Text("\nnog te schrijven.").foregroundColor(ThingsColor.textSecondary))
                        .font(.werk(size: 24, weight: .medium))
                        .kerning(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .principes:
                // Twee koppen naast elkaar met elk een regel erboven, zoals de affiche.
                HStack(alignment: .top, spacing: 14) {
                    RuledHeading(text: "Tijd\nschrijven")
                    RuledHeading(text: "Nog te\nfactureren")
                }
            case .wandklok:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tijd schrijven")
                        .font(.werk(size: 22, weight: .bold))
                        .kerning(-0.6)
                        .foregroundStyle(ThingsColor.textPrimary)
                    DashLabel(text: "nog te factureren")
                }
            case .tischsuper:
                VStack(alignment: .leading, spacing: 3) {
                    SuperscriptTitle(title: "Tijd schrijven", superscript: "\(count)")
                    ThemeParts.labelValue("Status", "nog te factureren")
                }
            case .rekenmachine:
                VStack(alignment: .leading, spacing: 3) {
                    ThemedHeading(title: "Tijd schrijven")
                    Text("Nog te factureren").font(.werk(size: 11.5)).foregroundStyle(ThingsColor.textPrimary)
                }
            case .karmijn:
                VStack(alignment: .leading, spacing: 4) {
                    KarmijnLabel(text: "Nog te factureren")
                    Text("TIJD SCHRIJVEN")
                        .font(.werkDisplay(size: 32))
                        .foregroundStyle(ThingsColor.today)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .displayTight(32)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tijd schrijven")
                        .font(.werk(size: 15, weight: ThemeStore.shared.look == .spark ? .bold : .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                    Text("Nog te factureren").font(.werk(size: 11.5)).foregroundStyle(ThingsColor.textSecondary)
                }
            }
            Spacer()
            #if os(macOS)
            Button { showDayClose = true } label: {
                ClaudeSpark()
                    .frame(width: 15, height: 15)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .help("Dag afsluiten (⇧⌘E)")
            .accessibilityLabel("Dag afsluiten")
            .sheet(isPresented: $showDayClose) {
                DayCloseView()
                    .environment(appState)
            }
            #endif
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

            // iOS: de Magic Plus rechtsonder opent de tijdinvoer.
            #if os(macOS)
            Button { showSupport = true } label: {
                Image(systemName: "plus")
                    .font(.werk(size: 13, weight: .semibold))
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
            #endif
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
                .font(.werk(size: 40))
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

    private var karmijn: Bool { ThemeStore.shared.look == .karmijn }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if karmijn {
                    KarmijnStar().fill(ThingsColor.running).frame(width: 10, height: 10)
                } else {
                    Circle().fill(ThingsColor.running).frame(width: 9, height: 9)
                }
            }
            .accessibilityHidden(true)
            ClientLogo(name: entry.client, size: 18)

            VStack(alignment: .leading, spacing: 1) {
                if karmijn {
                    Text(entry.title.uppercased())
                        .font(.werk(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    Text(entry.client)
                        .font(.werk(size: 11))
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(entry.title)
                        .thingsFont(.todoTitleOpen)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(1)
                    Text(entry.client)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let time = Billing.formatHMS(entry.elapsed(at: timeline.date))
                if karmijn {
                    Text(time).font(.werkNumbers(size: 20)).foregroundStyle(ThingsColor.today)
                } else {
                    Text(time)
                        .thingsFont(.todoTitleOpen)
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
                }
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
        .background {
            // Karmijn: wat loopt staat in een rood kader, net als de lopende kaart.
            if karmijn {
                Rectangle().strokeBorder(ThemeParts.karmijn, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                    .fill(ThingsColor.running.opacity(0.10))
            }
        }
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
                .font(.werk(size: 10, weight: .bold))
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
    /// Volgnummer in de lijst ("01."), alleen getoond in Karmijn.
    var index: Int? = nil
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Opengeklapt: klant, case en uitgevoerd, elk met een kopieerknop (voor het boekhoudpakket).
    @State private var expanded = false
    /// Veld dat bewerkt wordt (dubbelklik).
    @State private var editingField: BookingField?
    @State private var isHovering = false

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
                BookingDetails(entry: entry, editing: $editingField)
                    .padding(.leading, 30)
                    .padding(.bottom, 10)
            }
        }
        .opacity(entry.isWritten && !expanded ? 0.55 : 1)
    }

    private var summaryRow: some View {
        Group {
            if ThemeStore.shared.look == .karmijn { karmijnSummary } else { plainSummary }
        }
        .frame(minHeight: 44)
        .help(entry.status == .finished
              ? entry.workDescription + (entry.correctionSeconds != 0
                  ? "\nGemeten \(Billing.formatHM(entry.accumulated)) u, te factureren \(Billing.formatHours(TimerService.billedHours(entry))) u"
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

    private var plainSummary: some View {
        HStack(spacing: 8) {
            TodoCheckbox(status: writtenBinding, title: entry.title)
                .disabled(entry.status != .finished)
                .help(entry.status == .finished ? "Geschreven in het facturatiesysteem" : "Stop eerst de timer")
            ClientLogo(name: entry.client, size: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .thingsFont(.todoTitle)
                        .strikethrough(entry.isWritten)
                        .foregroundStyle(entry.isWritten ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                        .lineLimit(1)
                    if !entry.dictatedFields.isEmpty { DictatedMark() }
                }
                Group {
                    if ThemeStore.shared.look == .tischsuper {
                        ThemeParts.labelValue("Klant", subtitle)
                    } else {
                        Text(subtitle)
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
            .modifier(OpenGestures(entry: entry, expanded: $expanded, editingField: $editingField))
            Spacer(minLength: 4)

            if entry.status == .finished { expandButton }

            trailingTimeView

            if entry.status == .finished { copyButton }

            controls
        }
        // Principes: een regel van 2 pt boven elke rij, zoals de lijst met principes.
        .overlay(alignment: .top) {
            if ThemeStore.shared.look == .principes {
                Rectangle().fill(ThemeParts.rowRule).frame(height: 2)
            }
        }
    }

    /// De duur rechts, zoals het thema cijfers toont.
    @ViewBuilder private var trailingTimeView: some View {
        switch ThemeStore.shared.look {
        case .tischsuper:
            Text(trailingTime)
                .font(.werk(size: 15, weight: .ultraLight))
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textPrimary)
        case .drukproef:
            Text(trailingTime)
                .font(.werkNumbers(size: 11))
                .foregroundStyle(ThingsColor.textPrimary)
        case .spark:
            Text(trailingTime)
                .font(.werk(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThingsColor.tagBackground))
        default:
            Text(trailingTime)
                .thingsFont(.todoTitle)
                .monospacedDigit()
                .foregroundStyle(ThingsColor.textSecondary)
        }
    }

    /// Karmijn: rood volgnummer (ook het vinkje voor geschreven), titel in kapitalen, duur in schreef en een haarlijn
    /// erboven; uitklappen en kopiëren verschijnen bij aanwijzen.
    private var karmijnSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            writtenIndex
            ClientLogo(name: entry.client, size: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.title.uppercased())
                        .font(.werk(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .strikethrough(entry.isWritten)
                        .foregroundStyle(entry.isWritten ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                        .lineLimit(1)
                    if !entry.dictatedFields.isEmpty { DictatedMark() }
                }
                Text(subtitle)
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .modifier(OpenGestures(entry: entry, expanded: $expanded, editingField: $editingField))
            Spacer(minLength: 4)

            if entry.status == .finished {
                expandButton.opacity(isHovering || expanded ? 1 : 0)
                copyButton.opacity(isHovering ? 1 : 0)
            }

            Text(trailingTime)
                .font(.werkSerif(size: 17))
                .foregroundStyle(ThingsColor.textPrimary)

            controls
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(ThingsColor.separator).frame(height: 1) }
        .onHover { isHovering = $0 }
    }

    /// Karmijn: het volgnummer is de knop voor "geschreven"; bij aanwijzen een leeg vakje, daarna een vinkje.
    private var writtenIndex: some View {
        let canMark = entry.status == .finished
        return Button {
            TimerService.setWritten(entry, !entry.isWritten, in: context)
        } label: {
            Group {
                if entry.isWritten {
                    Image(systemName: "checkmark").font(.werk(size: 10, weight: .bold))
                } else if isHovering && canMark {
                    Rectangle().strokeBorder(ThingsColor.running, lineWidth: 1).frame(width: 11, height: 11)
                } else {
                    Text(index.map { String(format: "%02d.", $0) } ?? "")
                        .font(.werk(size: 11, weight: .bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(ThingsColor.running)
            .frame(width: 22, height: 15, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canMark)
        .help(canMark ? "Geschreven in het facturatiesysteem" : "Stop eerst de timer")
        .accessibilityLabel(entry.isWritten ? "Geschreven" : "Markeer als geschreven")
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.werk(size: 10, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .foregroundStyle(ThingsColor.textTertiary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Inklappen" : "Klant, case en uitgevoerd tonen om te kopiëren")
    }

    /// Case en uitgevoerd in één keer, voor het documentatiepakket.
    private var copyButton: some View {
        CopyButton(text: BookingDetails.documentationText(entry), symbol: "doc.on.clipboard",
                   help: "Case en uitgevoerd kopiëren")
    }

    /// Alleen de klant: een regel uit een kaarttimer ziet er na het stoppen hetzelfde uit als een snelle invoer.
    private var subtitle: String {
        var text = entry.client
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

/// Klik klapt een afgeronde regel open; dubbelklik klapt open en zet de case meteen in bewerkmodus.
private struct OpenGestures: ViewModifier {
    let entry: TimeEntry
    @Binding var expanded: Bool
    @Binding var editingField: BookingField?

    func body(content: Content) -> some View {
        content
            // Eerst dubbelklik, dan enkele klik: anders wint de enkele klik altijd.
            .onTapGesture(count: 2) {
                guard entry.status == .finished else { return }
                withAnimation(.easeOut(duration: 0.15)) { expanded = true }
                editingField = .caseTitle
            }
            .onTapGesture {
                guard entry.status == .finished else { return }
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }
    }
}

// MARK: - Voor het boekhoudpakket

/// Klant, case en uitgevoerd van een afgeronde regel: aan te passen en per veld te kopiëren.
/// Velden van een afgeronde regel die je met een dubbelklik aanpast.
enum BookingField: Hashable {
    case client, caseTitle, performed, hours

    /// Het ingesproken veld dat hierbij hoort.
    var dictated: DictatedField? {
        switch self {
        case .client: .client
        case .caseTitle: .caseTitle
        case .performed: .performed
        case .hours: nil
        }
    }

    var label: String {
        switch self {
        case .client: "Klant"
        case .caseTitle: "Case"
        case .performed: "Uitgevoerd"
        case .hours: "Uren"
        }
    }
}

/// Klant, case, uitgevoerd en uren: dubbelklik om aan te passen (Return bewaart, Esc annuleert, ⌘Z draait terug),
/// per regel kopiëren.
private struct BookingDetails: View {
    @Bindable var entry: TimeEntry
    @Binding var editing: BookingField?
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var cancelled = false
    @FocusState private var focused: Bool

    /// Zoals het in het documentatiepakket komt.
    static func documentationText(_ entry: TimeEntry) -> String {
        "Case: \(entry.title)\nUitgevoerd: \(entry.workDescription)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(.client, copy: value(.client))
            row(.caseTitle, copy: entry.title.isEmpty ? "" : "Case: \(entry.title)")
            row(.performed, copy: entry.workDescription.isEmpty ? "" : "Uitgevoerd: \(entry.workDescription)")
            row(.hours, copy: value(.hours))
        }
        .thingsFont(.notes)
        .onChange(of: editing, initial: true) { old, new in
            if let old, old != new, !cancelled { save(old, draft) }
            cancelled = false
            draft = new.map(value) ?? ""
            if new != nil, new != .client { Task { @MainActor in focused = true } }
        }
        .onChange(of: focused) { _, isFocused in
            // Ernaast klikken bewaart (het klantveld bewaart met Return).
            if !isFocused, let field = editing, field != .client { editing = nil }
        }
    }

    private func value(_ field: BookingField) -> String {
        switch field {
        case .client: entry.client == TimerService.noClient ? "" : entry.client
        case .caseTitle: entry.title
        case .performed: entry.workDescription
        case .hours: Billing.formatHours(TimerService.billedHours(entry))
        }
    }

    private func row(_ field: BookingField, copy: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(field.label)
                .font(.werk(size: 12, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
                .frame(width: 70, alignment: .leading)
            Group {
                if editing == field {
                    editor(field)
                        .onKeyPress(.escape) {
                            cancelled = true
                            editing = nil
                            return .handled
                        }
                } else {
                    let text = value(field)
                    Text(text.isEmpty ? "—" : text)
                        .foregroundStyle(text.isEmpty || field == .hours ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = field }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editing != field, let dictated = field.dictated, entry.dictatedFields.contains(dictated) {
                DictatedMark()
            }
            CopyButton(text: copy)
        }
    }

    @ViewBuilder private func editor(_ field: BookingField) -> some View {
        switch field {
        case .client:
            ClientField(text: $draft, autofocus: true, onCommit: { editing = nil })
        case .performed:
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...8)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { editing = nil }
        case .caseTitle, .hours:
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { editing = nil }
        }
    }

    /// Bewaart één veld; ⌘Z zet de vorige waarden terug.
    private func save(_ field: BookingField, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = Values(entry)
        switch field {
        case .client:
            entry.client = TimerService.normalized(trimmed)
        case .caseTitle:
            guard !trimmed.isEmpty else { return }
            entry.title = trimmed
        case .performed:
            entry.workDescription = trimmed
        case .hours:
            guard let hours = Self.parseHours(trimmed) else { return }
            entry.accumulated = hours * 3600 + entry.correctionSeconds
        }
        // Zelf aangepast: nagelezen, dus geen microfoon meer.
        if Values(entry) != before, let dictated = field.dictated { entry.dictatedFields.remove(dictated) }
        let after = Values(entry)
        guard after != before else { return }
        TimerService.save(context)
        let id = entry.id
        let context = context
        UndoCenter.shared.record("Tijdregel aanpassen", undo: {
            if let entry = TimerService.entry(withID: id, in: context) { before.apply(to: entry); TimerService.save(context) }
        }, redo: {
            if let entry = TimerService.entry(withID: id, in: context) { after.apply(to: entry); TimerService.save(context) }
        })
    }

    /// "0,25", "0.5", "1", "1:30" → uren.
    static func parseHours(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        let hours: Double?
        if parts.count == 2, let h = Double(parts[0]), let m = Double(parts[1]) {
            hours = h + m / 60
        } else {
            hours = Double(text.replacingOccurrences(of: ",", with: "."))
        }
        guard let hours, hours > 0, hours < 24 else { return nil }
        return hours
    }

    private struct Values: Equatable {
        var client: String
        var title: String
        var performed: String
        var accumulated: TimeInterval
        var dictated: String

        init(_ entry: TimeEntry) {
            client = entry.client
            title = entry.title
            performed = entry.workDescription
            accumulated = entry.accumulated
            dictated = entry.dictatedRaw
        }

        func apply(to entry: TimeEntry) {
            entry.client = client
            entry.title = title
            entry.workDescription = performed
            entry.accumulated = accumulated
            entry.dictatedRaw = dictated
        }
    }
}

/// Ingesproken en nog niet zelf aangepast: nalezen voordat je kopieert.
struct DictatedMark: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.werk(size: 10, weight: .semibold))
            .foregroundStyle(Color.orange)
            .help("Ingesproken")
            .accessibilityLabel("Ingesproken")
    }
}

/// Kopieert tekst naar het klembord; het icoon wordt even een vinkje.
struct CopyButton: View {
    let text: String
    var symbol = "doc.on.doc"
    var help = "Kopiëren"
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
            Image(systemName: copied ? "checkmark" : symbol)
                .font(.werk(size: 11, weight: .semibold))
                .foregroundStyle(copied ? Color.green : ThingsColor.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help(help)
        .accessibilityLabel("Kopieer")
    }
}

/// Totaal nog te factureren onderaan Tijd schrijven, zoals het thema het toont.
private struct TimeTotalFooter: View {
    let hours: Double
    /// Aantal regels dat nog geschreven moet worden.
    var count = 0

    private var text: String {
        let minutes = Int((hours * 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    var body: some View {
        switch ThemeStore.shared.look {
        case .drukproef:
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1).padding(.bottom, 12)
                Text(text)
                    .font(.werkNumbers(size: 48))
                    .tracking(-1.8)
                    .foregroundStyle(ThingsColor.today)
                HStack(spacing: 10) {
                    Rectangle().fill(ThingsColor.textSecondary).frame(width: 14, height: 1)
                    Text("TOTAAL TE FACTUREREN").font(.werk(size: 10, weight: .medium)).foregroundStyle(ThingsColor.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .principes:
            // De blauwe capsule van de affiche, met het luidsprekerrooster rechts.
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Totaal").font(.werk(size: 11)).opacity(0.8)
                    Text(text).font(.werk(size: 20, weight: .medium)).monospacedDigit()
                }
                Spacer(minLength: 4)
                PosterGrille(color: Color(hex: 0x062C52), columnWidth: 28)
            }
            .foregroundStyle(Color.white)
            .padding(.leading, 20)
            .padding(.trailing, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(ThingsColor.accent))
        case .sneeuwwitje:
            // Een witte kaart met het totaal op een schaal van 0 tot 8 uur.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Totaal").font(.werk(size: 11.5)).foregroundStyle(ThingsColor.textSecondary)
                    Spacer()
                    Text(text).font(.werk(size: 22, weight: .medium)).monospacedDigit().foregroundStyle(ThingsColor.textPrimary)
                }
                TuningBar(fraction: hours / 8, labels: ["0", "2", "4", "6", "8"])
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.cardBackground)
                .shadow(color: ThingsColor.cardShadow, radius: 12, y: 6))
        case .karmijn:
            // Het totaal groot in een rood kader, met het label ernaast.
            HStack(alignment: .center, spacing: 14) {
                Text(text)
                    .font(.werkNumbers(size: 42))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                    .displayTight(42)
                VStack(alignment: .leading, spacing: 2) {
                    KarmijnLabel(text: "Totaal", size: 9.5)
                    KarmijnLabel(text: "Te factureren", size: 9.5)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .overlay(Rectangle().strokeBorder(ThemeParts.karmijn, lineWidth: 1))
        case .rekenmachine:
            // Het totaal in lcd-cijfers op het scherm.
            LCDPanel(radius: 10) {
                HStack {
                    Text("TOTAAL").font(.werk(size: 9)).tracking(0.9).foregroundStyle(ThemeParts.lcdLabel)
                    Spacer()
                    LCDDigits(text: text, size: 24)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        case .wandklok:
            // Het totaal groot en vet, zoals de prijs op het horlogeblad.
            VStack(alignment: .leading, spacing: 3) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1).padding(.bottom, 9)
                DashLabel(text: "totaal", size: 11)
                Text(text)
                    .font(.werk(size: 34, weight: .bold))
                    .kerning(-1)
                    .monospacedDigit()
                    .foregroundStyle(ThingsColor.textPrimary)
                Text("\(count) \(count == 1 ? "regel" : "regels")")
                    .font(.werk(size: 11))
                    .foregroundStyle(ThingsColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tischsuper:
            // De voetregel van het RT 20-blad naast het totaal, dun en groot.
            VStack(spacing: 10) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        ThemeParts.labelValue("Totaal", "te factureren")
                        ThemeParts.labelValue("Regels", "\(count)")
                    }
                    Spacer()
                    Text(text)
                        .font(.werk(size: 34, weight: .ultraLight))
                        .kerning(-1.2)
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
                }
            }
        case .spark, .standaard:
            VStack(spacing: 10) {
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text("Totaal").font(.werk(size: 11.5)).foregroundStyle(ThingsColor.textSecondary)
                    Spacer()
                    Text(text)
                        .font(.werk(size: 20, weight: ThemeStore.shared.look == .spark ? .bold : .light))
                        .monospacedDigit()
                        .foregroundStyle(ThingsColor.textPrimary)
                }
            }
        }
    }
}
