import AppKit
import SwiftData
import SwiftUI

/// Hoofdvenster: board boven (±45%), agenda onder links (¾), Tijd schrijven onder rechts (¼).
struct MainView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(DragCoordinator.self) private var drag
    @Environment(\.undoManager) private var undoManager

    // Verdeling van het venster; bewaard tussen sessies. Dubbelklik op een scheidingslijn zet hem terug.
    @AppStorage("layout.boardFraction") private var boardFraction = Self.defaultBoardFraction
    @AppStorage("layout.agendaFraction") private var agendaFraction = Self.defaultAgendaFraction
    // Gmail-paneel links (standaard verborgen); breedte schuifbaar en bewaard.
    @AppStorage("gmail.panelVisible") private var gmailVisible = false
    @AppStorage("gmail.panelWidth") private var gmailWidth = Self.defaultGmailWidth
    @State private var boardDragStart: Double?
    @State private var agendaDragStart: Double?
    @State private var gmailDragStart: Double?
    @State private var showArchive = false
    // Maandagenda: `monthShown` houdt de weergave in beeld, `monthOpen` stuurt het open- en dichtvouwen.
    @State private var monthShown = false
    @State private var monthOpen = false

    private static let defaultGmailWidth = 300.0
    private static let gmailRange = 240.0...720.0

    private static let defaultBoardFraction = 0.45
    private static let defaultAgendaFraction = 0.75
    private static let boardRange = 0.18...0.72
    private static let agendaRange = 0.35...0.85

    private var mailMode: MailModeStore { MailModeStore.shared }

    /// Het board, de agenda en Tijd schrijven, met links het Mail-paneel.
    @ViewBuilder private var workbench: some View {
        HStack(spacing: 0) {
            if gmailVisible {
                GmailPanel()
                    .themePanel()
                    .frame(width: clamp(gmailWidth, Self.gmailRange))
                SplitDivider(isHorizontalLine: false,
                             label: "Schuif de breedte van het Gmail-paneel",
                             fill: dividerFill(ThingsColor.mailBackground),
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
                        .themePanel()
                        .frame(height: geo.size.height * clamp(boardFraction, Self.boardRange))
                    SplitDivider(isHorizontalLine: true,
                                 fill: dividerFill(ThingsColor.agendaBackground),
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
                            .themePanel()
                            .frame(width: geo.size.width * clamp(agendaFraction, Self.agendaRange))
                        SplitDivider(isHorizontalLine: false,
                                     fill: dividerFill(ThingsColor.agendaBackground),
                                     onChanged: { translation in
                                         let start = agendaDragStart ?? agendaFraction
                                         agendaDragStart = start
                                         agendaFraction = clamp(start + Double(translation / geo.size.width), Self.agendaRange)
                                     },
                                     onEnded: { agendaDragStart = nil },
                                     onReset: { agendaFraction = Self.defaultAgendaFraction })
                            .zIndex(1)
                        TimeListView()
                            .themePanel()
                    }
                }
                // Over het hele venster, behalve het Gmail-paneel.
                .overlay {
                    if monthShown {
                        MonthAgendaView(isOpen: $monthOpen, onClose: closeMonthAgenda)
                            .transition(.identity)
                    }
                }
            }
        }
    }

    var body: some View {
        @Bindable var state = appState

        ZStack {
            // De mailmodus neemt het hele venster over (dubbelklik op Mail); terug met Werkbank of Esc. Tijdens het slepen
            // van een mail zwiept hij naar beneden weg en staat de werkbank erachter; Esc haalt hem terug. De werkbank
            // blijft daarvoor achter de mail bestaan (onbereikbaar), zodat er bij het wegzwiepen niets opgebouwd hoeft
            // te worden: alleen verschuiven, en dat neemt ook de mail zelf (een webweergave) mee.
            GeometryReader { proxy in
                ZStack {
                    workbench
                        .overlay {
                            mailShade
                                .allowsHitTesting(false)
                                .animation(Self.swoop(receded: mailMode.isReceded), value: mailMode.isReceded)
                        }
                        .disabled(!workbenchLive)
                        .accessibilityHidden(!workbenchLive)
                    if mailMode.isActive {
                        MailModeView()
                            .themePanel()
                            .background(alignment: .top) { swoopShadow }
                            .offset(y: mailMode.isReceded ? proxy.size.height + 48 : 0)
                            .animation(Self.swoop(receded: mailMode.isReceded), value: mailMode.isReceded)
                            .allowsHitTesting(!mailMode.isReceded)
                    }
                }
                .clipped()
            }
            .overlay(alignment: .top) {
                ZStack {
                    if mailMode.isActive && mailMode.isReceded {
                        Button { mailMode.restore() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                Text("Mail")
                            }
                        }
                        .buttonStyle(MailModeButtonStyle(prominent: true))
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: mailMode.isReceded)
            }
            // Drukproef: losse vlakken met de vensterkleur eromheen.
            .padding(ThemeStore.shared.look.panelGap)
            // Mail en Claude in beeld: de rest van de app vervaagt, zodat je je op de inhoud richt. Een klik in het
            // vervaagde deel sluit wat je alleen las (niet waar je een antwoord, analyse of invoer in bent begonnen).
            .blur(radius: focusMode ? 7 : 0)
            .overlay {
                if focusMode {
                    Color.black.opacity(0.06)
                        .contentShape(Rectangle())
                        .onTapGesture { PanelStore.shared.closeUnengaged() }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: focusMode)

            // Boven het board en de agenda (rechts van het Gmail-paneel), niet in de blur.
            PanelOverlay()
                .padding(.leading, gmailVisible ? clamp(gmailWidth, Self.gmailRange) + 7 : 0)

            if appState.isDropTargeted { dropOverlay }

            DragOverlay()
            ToastOverlay(message: appState.toast)

            // ⇧⌘A: open gesprek of geselecteerde mail archiveren.
            Button("") { MailCommands.archiveFocused(appState: appState) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            // Esc: haalt de weggezwiepte mail terug, of annuleert een lopend concept op de agenda.
            Button("") {
                if mailMode.isReceded { mailMode.restore() } else { drag.draft = nil }
            }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        // De mail komt terug: een half ingepland concept op de agenda verdwijnt, alsof er niets is gebeurd.
        .onChange(of: mailMode.isReceded) { _, receded in if !receded { drag.draft = nil } }
        .providingSubtasks()
        .coordinateSpace(.named("main"))
        // Openen en sluiten met de Duo-vouw.
        .background(DuoWindowHook(isMain: true).frame(width: 0, height: 0))
        // ⌘Z voor handelingen in de app loopt via de UndoManager van dit venster.
        .onChange(of: undoManager, initial: true) { _, manager in UndoCenter.shared.manager = manager }
        // Nergens scrollbalken: ze nemen alleen maar ruimte in.
        .scrollIndicators(.never)
        // Letter en grootte van het thema voor tekst zonder eigen stijl.
        .font(.werk(size: 13))
        .background(ThingsColor.window)
        .onDrop(of: [.emailMessage, .fileURL, .gmailMessage], isTargeted: $state.isDropTargeted) { providers in
            if GmailDrop.accepts(providers) {
                return GmailDrop.handle(providers: providers, column: .inbox, archive: false, context: context, appState: appState)
            }
            return MailImporter.handle(providers: providers, context: context, appState: appState)
        }
        .sheet(item: $state.stopContext) { stop in
            if let entry = TimerService.entry(withID: stop.entryID, in: context) {
                StopSheet(entry: entry, defaultEnd: stop.defaultEnd)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                // Wisselen tussen werkbank en mailmodus, direct naast de vensterknopjes.
                if mailMode.isActive {
                    Button { mailMode.close() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.werk(size: 10, weight: .semibold))
                            Text("Werkbank")
                        }
                    }
                    .buttonStyle(ToolbarSwitchStyle())
                    .help("Terug naar de werkbank (⌘1 of Esc)")
                } else {
                    Button { mailMode.open() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope")
                            Text("Mail")
                            Image(systemName: "chevron.right").font(.werk(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(ToolbarSwitchStyle())
                    .help("Mailmodus (⌘2)")
                }
            }
            ToolbarItem(placement: .navigation) {
                // Het Mail-paneel hoort bij de werkbank; in de mailmodus doet dit knopje niets zichtbaars.
                if !mailMode.isActive {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { gmailVisible.toggle() }
                    } label: {
                        Label("Gmail", systemImage: "sidebar.left")
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .help("Mailpaneel tonen of verbergen (⇧⌘L)")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleMonthAgenda()
                } label: {
                    Label("Maandagenda", systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .help("Vier werkweken tegelijk (⌥⌘A)")
            }
            ToolbarItem(placement: .primaryAction) {
                // Verbetering inspreken en aanwijzen; regelt zo nodig spraakmodel, microfoon en schermopname.
                Button {
                    Dictation.shared.toggleFeedbackMode()
                } label: {
                    Label("Verbetering", systemImage: Dictation.shared.isFeedbackActive ? "lightbulb.fill" : "lightbulb")
                }
                .help("Verbetering inspreken en aanwijzen (F18)")
            }
            ToolbarItem(placement: .primaryAction) {
                // Snel wisselen van thema; eigen kleuren per thema blijven bewaard.
                Menu {
                    Picker("Thema", selection: Binding(get: { ThemeStore.shared.theme.id },
                                                       set: { ThemeStore.shared.select($0) })) {
                        ForEach(WerkbankTheme.all) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label("Thema", systemImage: "paintpalette")
                }
                .help("Thema wisselen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showArchive.toggle()
                } label: {
                    Label("Archief", systemImage: "archivebox")
                }
                .help("Archief: afgeronde taken")
                .popover(isPresented: $showArchive, arrowEdge: .bottom) {
                    ArchiveView()
                        .frame(width: 400, height: 460)
                }
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

    /// De werkbank is te gebruiken: geen mailmodus, of de mail is weg (of komt nog terug).
    private var workbenchLive: Bool { !mailMode.isActive || mailMode.isReceded || mailMode.isReturning }

    /// Wegzwiepen: na een klein optillen versnellend naar beneden. Terug: veerkrachtig omhoog, licht doorschietend.
    private static func swoop(receded: Bool) -> Animation {
        receded ? .timingCurve(0.4, -0.12, 0.75, 0.3, duration: 0.32) : .spring(duration: 0.42, bounce: 0.12)
    }

    /// De werkbank achter de mail iets donkerder, in de vorm van het paneel; trekt weg terwijl de mail wegzwiept.
    @ViewBuilder private var mailShade: some View {
        let shade = Color.black.opacity(mailMode.isActive && !mailMode.isReceded ? 0.22 : 0)
        let look = ThemeStore.shared.look
        if look == .telemetrie {
            shade.clipShape(ChamferedRect(cut: 16))
        } else {
            shade.clipShape(RoundedRectangle(cornerRadius: look.panelRadius, style: .continuous))
        }
    }

    /// Schaduw boven de bovenrand van de mail terwijl hij wegzwiept; in rust valt hij buiten beeld.
    private var swoopShadow: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            .frame(height: 36)
            .offset(y: -36)
            .allowsHitTesting(false)
    }

    /// Blur en "klik ernaast om te sluiten" zolang er een mail- of Claude-paneel open is (niet tijdens slepen).
    private var focusMode: Bool { PanelStore.shared.hasFocusPanels && !MailDragState.shared.isDragging }

    private func toggleMonthAgenda() {
        if monthShown && monthOpen {
            closeMonthAgenda()
        } else if !monthShown {
            monthShown = true   // de weergave zet zelf `monthOpen` aan zodra ze in beeld is
        }
    }

    private func closeMonthAgenda() {
        monthOpen = false
        // Pas weghalen als het dichtvouwen klaar is (langste vertraging 0,25 s + 0,2 s).
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !monthOpen { monthShown = false }
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
                    .font(.werk(size: 34))
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

extension MainView {
    /// Kleur van de strook tussen twee panelen: in Standaard wit, in een thema die van het paneel ernaast, en bij
    /// losse vlakken (Drukproef) en een afwijkende agenda (Karmijn) de vensterkleur.
    fileprivate func dividerFill(_ neighbour: Color) -> Color {
        switch ThemeStore.shared.look {
        case .standaard: ThingsColor.backgroundContent
        case .drukproef, .karmijn, .telemetrie, .puls: ThingsColor.window
        default: neighbour
        }
    }
}

extension View {
    /// Een paneel van het hoofdvenster; bij losse vlakken (Drukproef) met afgeronde hoeken, in Telemetrie met een
    /// afgesneden hoek en een haarlijn erom.
    @ViewBuilder func themePanel() -> some View {
        let radius = ThemeStore.shared.look.panelRadius
        if ThemeStore.shared.look == .telemetrie {
            clipShape(ChamferedRect(cut: 16))
                .overlay(ChamferedRect(cut: 16).strokeBorder(ThingsColor.separator, lineWidth: 1).allowsHitTesting(false))
        } else if radius > 0 {
            clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self
        }
    }
}

/// Scheidingslijn tussen twee panelen die je door te slepen kunt verschuiven. In het midden een kort greepje, ook in
/// thema's met losse vlakken (daar is de lijn zelf onzichtbaar), zodat je ziet dat hij schuift. Dubbelklik zet terug.
struct SplitDivider: View {
    /// `true`: een horizontale lijn (verschuift op en neer); `false`: een verticale lijn (links/rechts).
    let isHorizontalLine: Bool
    var label: String? = nil
    var fill: Color = ThingsColor.backgroundContent
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let onReset: () -> Void

    @State private var isHovering = false

    private static let thickness: CGFloat = 7

    var body: some View {
        // Een echt klikvlak van 7 pt (geen overlay buiten de eigen afmetingen), met de zichtbare lijn in het midden.
        ZStack {
            Rectangle().fill(fill)
            Rectangle()
                .fill(isHovering ? ThingsColor.accent
                      : (ThemeStore.shared.look.panelGap > 0 ? Color.clear : ThingsColor.separator))
                .frame(width: isHorizontalLine ? nil : (isHovering ? 2 : 1),
                       height: isHorizontalLine ? (isHovering ? 2 : 1) : nil)
            Capsule()
                .fill(isHovering ? ThingsColor.accent : ThingsColor.textTertiary.opacity(0.45))
                .frame(width: isHorizontalLine ? 32 : 3, height: isHorizontalLine ? 3 : 32)
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
