//
//  ThingsComponents.swift
//  Basiscomponenten volgens Things-Design.md §7–§8
//
//  Vereist: ThingsTheme.swift
//  Doelplatformen: iOS 17+ / macOS 14+
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Vaste lijsten (§2.1)

enum ThingsList: String, CaseIterable, Identifiable {
    case inbox, today, evening, upcoming, anytime, someday, logbook, trash

    var id: String { rawValue }

    /// Nederlandse weergavenamen; pas aan naar eigen voorkeur.
    var title: String {
        switch self {
        case .inbox:    return "Inbox"
        case .today:    return "Vandaag"
        case .evening:  return "Vanavond"
        case .upcoming: return "Gepland"
        case .anytime:  return "Altijd"
        case .someday:  return "Ooit"
        case .logbook:  return "Logboek"
        case .trash:    return "Prullenbak"
        }
    }

    var symbol: String {
        switch self {
        case .inbox:    return "tray.fill"
        case .today:    return "star.fill"
        case .evening:  return "moon.fill"
        case .upcoming: return "calendar"
        case .anytime:  return "square.stack.3d.up.fill"
        case .someday:  return "archivebox.fill"
        case .logbook:  return "checkmark.square.fill"
        case .trash:    return "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .inbox:    return ThingsColor.inbox
        case .today:    return ThingsColor.today
        case .evening:  return ThingsColor.evening
        case .upcoming: return ThingsColor.upcoming
        case .anytime:  return ThingsColor.anytime
        case .someday:  return ThingsColor.someday
        case .logbook:  return ThingsColor.logbook
        case .trash:    return ThingsColor.trash
        }
    }
}

/// Grote lijsttitel met icoon (§4.1, §4.2).
struct ThingsListHeader: View {
    let title: String
    var symbol: String? = nil
    var color: Color = ThingsColor.accent

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .thingsFont(.listTitle)
            }
            Text(title)
                .thingsFont(.listTitle)
                .foregroundStyle(ThingsColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ThingsListHeader {
    init(_ list: ThingsList) {
        self.init(title: list.title, symbol: list.symbol, color: list.color)
    }
}

// MARK: - Checkbox (§8.3)

enum TodoStatus: Equatable {
    case open, completed, canceled
}

/// Afgerond vierkant. Klik = afronden, ⌥-klik (macOS) = annuleren.
struct TodoCheckbox: View {
    @Binding var status: TodoStatus
    var title: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = ThingsMetrics.checkboxSize
    @State private var pop = false

    var body: some View {
        Button(action: toggle) {
            ZStack {
                RoundedRectangle(cornerRadius: ThingsMetrics.checkboxRadius, style: .continuous)
                    .fill(fillColor)
                RoundedRectangle(cornerRadius: ThingsMetrics.checkboxRadius, style: .continuous)
                    .strokeBorder(status == .open ? ThingsColor.checkboxStroke : .clear, lineWidth: 1.5)

                if status != .open {
                    Image(systemName: status == .completed ? "checkmark" : "xmark")
                        .font(.system(size: size * 0.6, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(pop ? 1.15 : 1)
            // Grotere klik-/tikzone dan het zichtbare vakje.
            .frame(width: ThingsMetrics.minTapTarget * 0.6, height: ThingsMetrics.minTapTarget * 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: status) { _, new in new == .completed }
        .accessibilityLabel(accessibilityText)
    }

    private var fillColor: Color {
        switch status {
        case .open:      return .clear
        case .completed: return ThingsColor.accent
        case .canceled:  return ThingsColor.textTertiary
        }
    }

    private var accessibilityText: String {
        switch status {
        case .open:      return "Taak afronden: \(title)"
        case .completed: return "Afgerond: \(title)"
        case .canceled:  return "Geannuleerd: \(title)"
        }
    }

    private func toggle() {
        #if os(macOS)
        let cancel = NSEvent.modifierFlags.contains(.option)
        #else
        let cancel = false
        #endif

        withAnimation(ThingsMotion.check(reduceMotion: reduceMotion)) {
            if status == .open {
                status = cancel ? .canceled : .completed
            } else {
                status = .open
            }
        }

        guard !reduceMotion, status == .completed else { return }
        withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) { pop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { pop = false }
        }
    }
}

// MARK: - Project-voortgang (§7, §8.5)

struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center,
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(max(progress, 0), 1)),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Cirkel die zich als taartdiagram vult.
struct ProjectProgressPie: View {
    var progress: Double
    var size: CGFloat = ThingsMetrics.checkboxSize

    var body: some View {
        ZStack {
            Circle().strokeBorder(ThingsColor.accent, lineWidth: 1.5)
            PieSlice(progress: progress)
                .fill(ThingsColor.accent)
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
        .accessibilityLabel("Voortgang \(Int(progress * 100)) procent")
    }
}

// MARK: - Checklist-item (§7: kleine cirkel)

struct ChecklistItemRow: View {
    @Binding var isDone: Bool
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isDone.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isDone ? .clear : ThingsColor.checkboxStroke, lineWidth: 1.2)
                    if isDone {
                        Circle().fill(ThingsColor.accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 12, height: 12)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? ThingsColor.textSecondary : ThingsColor.textPrimary)
                .thingsFont(.notes)
        }
    }
}

// MARK: - Tag (§8.6)

struct TagPill: View {
    let name: String

    var body: some View {
        Text(name)
            .thingsFont(.tag)
            .foregroundStyle(ThingsColor.tagText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: ThingsMetrics.tagRadius, style: .continuous)
                    .fill(ThingsColor.tagBackground)
            )
            .accessibilityLabel("Tag \(name)")
    }
}

// MARK: - Deadline (§3: rode vlag, rood bij vandaag/verlopen)

struct DeadlineLabel: View {
    let deadline: Date
    var now: Date = .now

    private var days: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: now),
                                  to: cal.startOfDay(for: deadline)).day ?? 0
    }

    private var text: String {
        switch days {
        case ..<(-1): return "\(-days) dagen te laat"
        case -1:      return "1 dag te laat"
        case 0:       return "vandaag"
        case 1:       return "nog 1 dag"
        default:      return "nog \(days) dagen"
        }
    }

    private var isUrgent: Bool { days <= 0 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
            Text(text)
        }
        .thingsFont(.metadata)
        .foregroundStyle(isUrgent ? ThingsColor.deadline : ThingsColor.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deadline \(text)")
    }
}

// MARK: - Heading in project (§8.4)

struct ThingsHeading: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.accent)
            Rectangle()
                .fill(ThingsColor.separator)
                .frame(height: 1)
        }
        .padding(.top, ThingsMetrics.headingTopSpacing)
        .padding(.bottom, ThingsMetrics.headingBottomSpacing)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Sectiekop voor "Vanavond" onder Vandaag (§8.7).
struct EveningSectionHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: ThingsList.evening.symbol)
                    .foregroundStyle(ThingsColor.evening)
                Text(ThingsList.evening.title)
                    .foregroundStyle(ThingsColor.textPrimary)
            }
            .thingsFont(.heading)
            Rectangle()
                .fill(ThingsColor.separator)
                .frame(height: 1)
        }
        .padding(.top, ThingsMetrics.headingTopSpacing)
        .padding(.bottom, ThingsMetrics.headingBottomSpacing)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - To-do-model (alleen voor weergave)

struct TodoRowModel: Identifiable {
    let id = UUID()
    var title: String
    var notes: String = ""
    var status: TodoStatus = .open
    var parent: String? = nil
    var tags: [String] = []
    var deadline: Date? = nil
    var isScheduledToday = false
    var hasChecklist = false
    var repeats = false
    var hasReminder = false
}

// MARK: - To-do-rij, gesloten (§8.1)

struct TodoRow: View {
    @Binding var item: TodoRowModel
    /// Toon ster en bovenliggend project (overzichtslijsten zoals Gepland, Altijd).
    var showsContext = false
    var isSelected = false

    var body: some View {
        HStack(alignment: .center, spacing: ThingsMetrics.checkboxTitleGap) {
            TodoCheckbox(status: $item.status, title: item.title)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if showsContext && item.isScheduledToday {
                        Image(systemName: "star.fill")
                            .foregroundStyle(ThingsColor.today)
                            .thingsFont(.metadata)
                            .accessibilityLabel("Vandaag")
                    }
                    Text(item.title.isEmpty ? "Nieuwe taak" : item.title)
                        .strikethrough(item.status == .canceled)
                        .foregroundStyle(titleColor)
                        .thingsFont(.todoTitle)
                        .lineLimit(1)

                    statusIcons
                }

                if showsContext, let parent = item.parent {
                    Text(parent)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(item.tags, id: \.self) { TagPill(name: $0) }
            }

            if let deadline = item.deadline {
                DeadlineLabel(deadline: deadline)
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: ThingsMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
                .fill(isSelected ? ThingsColor.selection : .clear)
        )
        .contentShape(Rectangle())
    }

    private var titleColor: Color {
        if item.title.isEmpty { return ThingsColor.textTertiary }
        return item.status == .open ? ThingsColor.textPrimary : ThingsColor.textSecondary
    }

    @ViewBuilder
    private var statusIcons: some View {
        HStack(spacing: 4) {
            if !item.notes.isEmpty    { Image(systemName: "doc.text") }
            if item.hasChecklist      { Image(systemName: "checklist") }
            if item.repeats           { Image(systemName: "repeat") }
            if item.hasReminder       { Image(systemName: "bell.fill") }
        }
        .thingsFont(.metadata)
        .foregroundStyle(ThingsColor.textSecondary)
        .accessibilityHidden(true)
    }
}

// MARK: - To-do, geopend als "wit vel papier" (§8.2)

struct TodoDetailCard: View {
    @Binding var item: TodoRowModel
    var onClose: () -> Void = {}

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: ThingsMetrics.checkboxTitleGap) {
                TodoCheckbox(status: $item.status, title: item.title)
                TextField("Nieuwe taak", text: $item.title)
                    .textFieldStyle(.plain)
                    .thingsFont(.todoTitleOpen)
                    .foregroundStyle(ThingsColor.textPrimary)
                    .focused($titleFocused)
                    .onSubmit(onClose)
            }

            TextField("Notities", text: $item.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .thingsFont(.notes)
                .foregroundStyle(ThingsColor.textSecondary)
                .lineLimit(1...10)
                .padding(.leading, ThingsMetrics.minTapTarget * 0.6 + ThingsMetrics.checkboxTitleGap)

            // Progressieve onthulling: velden zitten weggestopt rechtsonder.
            HStack(spacing: 14) {
                if !item.tags.isEmpty {
                    HStack(spacing: 4) { ForEach(item.tags, id: \.self) { TagPill(name: $0) } }
                }
                if let deadline = item.deadline { DeadlineLabel(deadline: deadline) }
                Spacer()
                fieldButton("tag", label: "Tags")
                fieldButton("checklist", label: "Checklist")
                fieldButton("calendar", label: "Wanneer")
                fieldButton("flag", label: "Deadline")
            }
        }
        .padding(16)
        .thingsCard()
        .onAppear { titleFocused = item.title.isEmpty }
        #if os(macOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    private func fieldButton(_ symbol: String, label: String) -> some View {
        Button {
            // Koppel hier je eigen popovers (Jump Start, tags, deadline).
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(ThingsColor.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Uitklapbare to-do: rij ↔ kaart op dezelfde plek (§10)

struct ExpandableTodo: View {
    @Binding var item: TodoRowModel
    @Binding var expandedID: UUID?
    var showsContext = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expandedID == item.id }

    /// Mac: dubbelklik opent (enkele klik = selecteren). iOS: één tik.
    private var openTapCount: Int {
        #if os(macOS)
        return 2
        #else
        return 1
        #endif
    }

    var body: some View {
        Group {
            if isExpanded {
                TodoDetailCard(item: $item) { setExpanded(false) }
                    .padding(.vertical, 8)
                    .transition(ThingsMotion.expandTransition(reduceMotion: reduceMotion))
            } else {
                TodoRow(item: $item, showsContext: showsContext)
                    .onTapGesture(count: openTapCount) { setExpanded(true) }
            }
        }
    }

    private func setExpanded(_ open: Bool) {
        withAnimation(ThingsMotion.expand(reduceMotion: reduceMotion)) {
            expandedID = open ? item.id : nil
        }
    }
}

// MARK: - Magic Plus (§8.9)

/// Alleen tikken. Slepen-om-in-te-voegen vergt een eigen DragGesture die de drop-positie
/// in de lijst bepaalt; dat hangt af van je lijstimplementatie en zit hier niet in.
struct MagicPlusButton: View {
    var action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: ThingsMetrics.magicPlusSize, height: ThingsMetrics.magicPlusSize)
                .background(Circle().fill(ThingsColor.accent))
                .shadow(color: ThingsColor.accent.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel("Nieuwe taak")
    }
}

extension View {
    /// Plaatst de Magic Plus rechtsonder (iOS). Op macOS gebeurt niets: daar gebruik je ⌘N.
    @ViewBuilder
    func magicPlus(action: @escaping () -> Void) -> some View {
        #if os(iOS)
        overlay(alignment: .bottomTrailing) {
            MagicPlusButton(action: action)
                .padding(ThingsMetrics.magicPlusInset)
        }
        #else
        self
        #endif
    }
}

// MARK: - Lege staat (§8.14)

struct ThingsEmptyState: View {
    let list: ThingsList

    var body: some View {
        Image(systemName: list.symbol)
            .font(.system(size: 64))
            .foregroundStyle(ThingsColor.textTertiary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("\(list.title) is leeg")
    }
}

// MARK: - Voorbeeldscherm

private struct TodayPreview: View {
    @State private var todos: [TodoRowModel] = [
        .init(title: "Offerte Synology uitwerken", parent: "Klant X", tags: ["Werk"],
              deadline: .now, hasReminder: true),
        .init(title: "UniFi-firmware controleren", parent: "Beheer", tags: ["15 min"]),
        .init(title: "Boodschappen", notes: "Melk, brood", hasChecklist: true),
    ]
    @State private var evening: [TodoRowModel] = [
        .init(title: "Factuur versturen", repeats: true)
    ]
    @State private var expandedID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ThingsListHeader(.today)
                    .padding(.bottom, 16)

                ForEach($todos) { $todo in
                    ExpandableTodo(item: $todo, expandedID: $expandedID, showsContext: true)
                }

                EveningSectionHeader()
                ForEach($evening) { $todo in
                    ExpandableTodo(item: $todo, expandedID: $expandedID)
                }

                ThingsHeading(title: "Voorbeeldheading")
                HStack(spacing: 12) {
                    ProjectProgressPie(progress: 0.4)
                    Text("Project met 40% voortgang")
                        .thingsFont(.todoTitle)
                        .foregroundStyle(ThingsColor.textPrimary)
                }
            }
            .padding(ThingsMetrics.contentPadding)
            .frame(maxWidth: ThingsMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ThingsColor.backgroundContent)
        .magicPlus {
            let new = TodoRowModel(title: "")
            todos.append(new)
            withAnimation(ThingsMotion.expand(reduceMotion: false)) { expandedID = new.id }
        }
    }
}

#Preview("Vandaag – licht") {
    TodayPreview()
}

#Preview("Vandaag – donker") {
    TodayPreview()
        .preferredColorScheme(.dark)
}

#Preview("Lijsticonen") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ThingsList.allCases) { list in
            Label {
                Text(list.title).thingsFont(.sidebarItem)
            } icon: {
                Image(systemName: list.symbol).foregroundStyle(list.color)
            }
        }
    }
    .padding()
    .background(ThingsColor.backgroundSidebar)
}
