import SwiftUI
import WerkbankCore

extension CoordinateSpace {
    /// Coördinatenruimte van het hele hoofdvenster; slepen tussen board en agenda rekent hierin.
    static let main = CoordinateSpace.named("main")
}

struct BoardTarget: Equatable {
    var column: BoardColumn
    /// Positie binnen de andere kaarten van die kolom (de gesleepte kaart zelf niet meegeteld).
    var index: Int
}

struct AgendaSlot: Equatable {
    var day: Date
    var start: Date
}

/// Geometrie van de agenda in "main"-coördinaten, gevuld door AgendaView.
final class AgendaGeometry {
    var dayFrames: [Date: CGRect] = [:]
    var frame: CGRect = .zero
    var startHour = 8
    var endHour = 18
    var hourHeight: CGFloat = 46
    var scrollViewport: CGRect = .zero

    var timelineTop: CGFloat { dayFrames.values.map(\.minY).min() ?? 0 }
}

/// Bestuurt het slepen van kaarten: over het board (herschikken, tussen kolommen) en naar de agenda (inplannen).
/// De gesleepte kaart wordt door `DragOverlay` boven alles getekend, zodat hij tussen board en agenda kan reizen.
@MainActor
@Observable
final class DragCoordinator {
    enum Phase { case idle, dragging, landing }
    enum Region { case board, agenda, outside }

    // MARK: Observeerbare status

    private(set) var phase: Phase = .idle
    private(set) var card: TodoCard?
    private(set) var region: Region = .outside
    private(set) var target: BoardTarget?
    private(set) var agendaSlot: AgendaSlot?

    private(set) var overlayOrigin: CGPoint = .zero
    private(set) var overlayScale: CGFloat = 1
    private(set) var overlayOpacity: Double = 1
    private(set) var tilt: Double = 0
    private(set) var cardSize: CGSize = .zero

    /// Concept-afspraak op de agenda (stap 2 en 3 van het inplannen).
    var draft: ScheduleDraft?
    /// Kaart die na het neerzetten een kleine "pop" moet maken.
    var popID: UUID?

    var isDragging: Bool { phase != .idle }

    // MARK: Geometrie (niet geobserveerd: verandert bij elke layoutpas)

    @ObservationIgnored var cardFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var columnFrames: [BoardColumn: CGRect] = [:]
    @ObservationIgnored var stackFrames: [BoardColumn: CGRect] = [:]
    @ObservationIgnored var boardFrame: CGRect = .zero
    @ObservationIgnored let agenda = AgendaGeometry()
    @ObservationIgnored private(set) var pointer: CGPoint = .zero

    @ObservationIgnored var onBoardDrop: ((TodoCard, BoardColumn, Int) -> Void)?
    @ObservationIgnored var onAgendaDrop: ((TodoCard, AgendaSlot) -> Void)?

    static let cardSpacing: CGFloat = 8

    @ObservationIgnored private var order: [BoardColumn: [UUID]] = [:]
    @ObservationIgnored private var origin: BoardTarget?
    @ObservationIgnored private var grab: CGSize = .zero
    @ObservationIgnored private var lastX: CGFloat = 0
    @ObservationIgnored private var tiltReset: Task<Void, Never>?

    /// Momentopname voor de tijdelijke debug-regel (alleen zichtbaar in Debug-builds).
    var debugSummary: String {
        func rect(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
        func place(_ t: BoardTarget?) -> String { t.map { "\($0.column.rawValue)#\($0.index)" } ?? "nil" }
        let slotText = agendaSlot.map { "\(DutchDate.weekdayShort($0.day)) \(DutchDate.time($0.start))" } ?? "nil"
        let draftText = draft.map { "\(DutchDate.time($0.start))-\(DutchDate.time($0.end)) \($0.step)" } ?? "nil"
        return "phase \(phase) region \(region) target \(place(target)) origin \(place(origin))\n"
            + "board \(rect(boardFrame)) kolommen \(columnFrames.count) stapels \(stackFrames.count)\n"
            + "agenda \(rect(agenda.frame)) dagen \(agenda.dayFrames.count) uurhoogte \(Int(agenda.hourHeight)) "
            + "uren \(agenda.startHour)-\(agenda.endHour) top \(Int(agenda.timelineTop))\n"
            + "slot \(slotText) draft \(draftText)\n"
            + "pointer \(Int(pointer.x)),\(Int(pointer.y))"
    }

    // MARK: Slepen

    func begin(card: TodoCard, frame: CGRect, pointer: CGPoint, order: [BoardColumn: [UUID]]) {
        guard phase == .idle else { return }
        draft = nil
        self.card = card
        self.order = order
        self.pointer = pointer
        lastX = pointer.x
        grab = CGSize(width: pointer.x - frame.minX, height: pointer.y - frame.minY)
        cardSize = frame.size
        overlayOrigin = frame.origin
        overlayOpacity = 1
        tilt = 0

        let column = card.column
        let index = order[column]?.firstIndex(of: card.id) ?? 0
        origin = BoardTarget(column: column, index: index)
        target = origin
        agendaSlot = nil
        region = .board
        phase = .dragging

        // De kaart komt los: iets groter (animatie staat in DragOverlay).
        overlayScale = 1.05
    }

    func update(pointer: CGPoint) {
        guard phase == .dragging else { return }
        self.pointer = pointer
        overlayOrigin = CGPoint(x: pointer.x - grab.width, y: pointer.y - grab.height)
        updateTilt(dx: pointer.x - lastX)
        lastX = pointer.x

        let newRegion = region(at: pointer)
        if newRegion != region { region = newRegion }

        let desiredScale: CGFloat = newRegion == .agenda ? 0.8 : 1.05
        if desiredScale != overlayScale { overlayScale = desiredScale }

        switch newRegion {
        case .board:
            // Bij een mislukte berekening de vorige doelplek houden in plaats van het doel te wissen.
            if let t = boardTarget(for: pointer), t != target { target = t }
            if agendaSlot != nil { agendaSlot = nil }
        case .agenda:
            if target != origin { target = origin }
            let slot = agendaSlot(for: pointer)
            if slot != agendaSlot { agendaSlot = slot }
        case .outside:
            if target != origin { target = origin }
            if agendaSlot != nil { agendaSlot = nil }
        }
    }

    func end(pointer: CGPoint) {
        guard phase == .dragging, let card else { return }
        update(pointer: pointer)
        tiltReset?.cancel()
        phase = .landing

        if region == .agenda, let slot = agendaSlot, let rect = agendaBlockRect(for: slot) {
            // Kleiner wordend in het voorbeeldblok, dan verdwijnen.
            overlayOrigin = CGPoint(x: rect.midX - cardSize.width / 2, y: rect.midY - cardSize.height / 2)
            overlayScale = 0.25
            overlayOpacity = 0
            tilt = 0
            finish(after: .milliseconds(210)) { [weak self] in
                self?.onAgendaDrop?(card, slot)
            }
            return
        }

        // Naar de placeholder vliegen met een licht doorverende curve.
        let destination = target ?? origin ?? BoardTarget(column: card.column, index: 0)
        let rect = slotRect(for: destination, excluding: card.id)
        if let rect { overlayOrigin = rect.origin }
        overlayScale = 1
        tilt = 0
        let moved = destination != origin
        finish(after: .milliseconds(200)) { [weak self] in
            self?.popID = card.id
            if moved { self?.onBoardDrop?(card, destination.column, destination.index) }
        }
    }

    /// Gebaar onderbroken zonder einde (venster verliest focus, app-wissel): kaart vliegt terug naar zijn plek.
    func cancel() {
        guard phase == .dragging, let card else { return }
        tiltReset?.cancel()
        phase = .landing
        target = origin
        agendaSlot = nil
        if let origin, let rect = slotRect(for: origin, excluding: card.id) { overlayOrigin = rect.origin }
        overlayScale = 1
        tilt = 0
        finish(after: .milliseconds(200)) {}
    }

    // MARK: Afronden

    private func finish(after delay: Duration, commit: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            // Zonder animatie, zodat de echte kaart naadloos de placeholder vervangt.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                commit()
                self.reset()
            }
        }
    }

    private func reset() {
        phase = .idle
        card = nil
        target = nil
        agendaSlot = nil
        origin = nil
        region = .outside
        overlayScale = 1
        overlayOpacity = 1
        tilt = 0
        order = [:]
    }

    // MARK: Kanteling

    /// Kantelt mee met de horizontale snelheid (max ±14°) en veert terug als je stilhoudt.
    private func updateTilt(dx: CGFloat) {
        let target = max(-14, min(14, Double(dx) * 1.6))
        let blended = tilt * 0.5 + target * 0.5
        tilt = blended

        tiltReset?.cancel()
        tiltReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            self?.tilt = 0
        }
    }

    // MARK: Board-berekeningen

    /// Het boardgebied: het gemeten boardframe, anders de samenvoeging van de kolomframes.
    private var boardArea: CGRect? {
        if boardFrame.width > 1 { return boardFrame }
        guard let first = columnFrames.values.first else { return nil }
        return columnFrames.values.dropFirst().reduce(first) { $0.union($1) }
    }

    private func region(at point: CGPoint) -> Region {
        if agenda.frame.width > 1, agenda.frame.contains(point) { return .agenda }
        // Zonder gemeten geometrie liever board dan niets: de kaart kan dan tenminste van kolom wisselen.
        guard let area = boardArea else { return .board }
        return area.insetBy(dx: -24, dy: -24).contains(point) ? .board : .outside
    }

    /// Frame van de kaartenstapel in een kolom; terugval op het kolomframe onder de kop als de
    /// stapel zelf niet gemeten is.
    private func stackFrame(for column: BoardColumn) -> CGRect? {
        if let stack = stackFrames[column] { return stack }
        guard let frame = columnFrames[column] else { return nil }
        return CGRect(x: frame.minX + 10, y: frame.minY + 44, width: frame.width - 20, height: 0)
    }

    /// Dichtstbijzijnde kolom op x-positie; index op de verticale middens van de kaarten.
    /// Berekend uit de gemeten kaarthoogtes (niet uit verschuivende frames), zodat de placeholder niet flikkert.
    private func boardTarget(for point: CGPoint) -> BoardTarget? {
        guard let column = columnFrames.min(by: { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) })?.key,
              let stack = stackFrame(for: column), let card else { return nil }

        let draggedCenterY = point.y - grab.height + cardSize.height / 2
        var top = stack.minY
        var index = 0
        for id in (order[column] ?? []) where id != card.id {
            let height = cardFrames[id]?.height ?? cardSize.height
            if top + height / 2 < draggedCenterY { index += 1 }
            top += height + Self.cardSpacing
        }
        return BoardTarget(column: column, index: index)
    }

    private func slotRect(for target: BoardTarget, excluding id: UUID) -> CGRect? {
        guard let stack = stackFrame(for: target.column) else { return nil }
        var y = stack.minY
        for other in (order[target.column] ?? []).filter({ $0 != id }).prefix(target.index) {
            y += (cardFrames[other]?.height ?? cardSize.height) + Self.cardSpacing
        }
        return CGRect(x: stack.minX, y: y, width: stack.width, height: cardSize.height)
    }

    // MARK: Agenda-berekeningen

    private func agendaSlot(for point: CGPoint) -> AgendaSlot? {
        guard let (day, _) = agenda.dayFrames.first(where: { $0.value.minX <= point.x && point.x < $0.value.maxX }) else {
            return nil
        }
        let minutesFromStart = Int(((point.y - agenda.timelineTop) / agenda.hourHeight * 60).rounded(.down))
        let lower = agenda.startHour * 60
        let upper = agenda.endHour * 60 - Scheduling.step
        let minutes = min(max(agenda.startHour * 60 + minutesFromStart, lower), upper)
        return AgendaSlot(day: day, start: Scheduling.start(onDayOf: day, minutesFromMidnight: minutes))
    }

    /// Frame van het voorbeeldblok (1 uur) in "main"-coördinaten.
    func agendaBlockRect(for slot: AgendaSlot) -> CGRect? {
        guard let column = agenda.dayFrames[slot.day] else { return nil }
        let cal = Calendar.current
        let minutes = cal.component(.hour, from: slot.start) * 60 + cal.component(.minute, from: slot.start)
        let y = agenda.timelineTop + CGFloat(minutes - agenda.startHour * 60) / 60 * agenda.hourHeight
        return CGRect(x: column.minX + 2, y: y, width: column.width - 4, height: agenda.hourHeight)
    }
}
