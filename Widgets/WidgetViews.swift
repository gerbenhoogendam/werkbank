import AppIntents
import SwiftUI
import WidgetKit

/// De kleuren en letters van Etiket (zoals `Ph` in de app; de extensie kan die niet gebruiken).
enum W {
    static let paper = Color(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF1 / 255)
    static let card = Color.white
    static let ink = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255)
    static let ink2 = Color(red: 0x55 / 255, green: 0x55 / 255, blue: 0x4F / 255)
    static let ink3 = Color(red: 0x7A / 255, green: 0x7A / 255, blue: 0x72 / 255)
    static let faint = Color(red: 0xA8 / 255, green: 0xA8 / 255, blue: 0x9E / 255)
    static let line = Color(red: 0xDA / 255, green: 0xDA / 255, blue: 0xD2 / 255)
    static let well = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xE5 / 255)
    /// Accent en bijschriftkleur volgen het thema van de app (Limoen of Blauw, via de gedeelde map).
    static var isBlue: Bool { WidgetShare.defaults?.string(forKey: "phone.theme") == "blauw" }
    static var lime: Color {
        isBlue ? Color(red: 0x2E / 255, green: 0xC5 / 255, blue: 0xFF / 255)
               : Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x1E / 255)
    }
    static var olive: Color {
        isBlue ? Color(red: 0x00 / 255, green: 0x4E / 255, blue: 0x73 / 255)
               : Color(red: 0x4F / 255, green: 0x5E / 255, blue: 0x00 / 255)
    }
    static let late = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x00 / 255)

    static func poster(_ size: CGFloat) -> Font { .custom("BebasNeue-Regular", size: size) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    static let agendaURL = URL(string: "zwoegbank://agenda")!
    static let timeURL = URL(string: "zwoegbank://tijd")!
    static let speakURL = URL(string: "zwoegbank://tijd/inspreken")!

    static func hm(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Leeg als het vandaag is, anders "MORGEN" of "WO 3".
    static func day(_ date: Date, from now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "MORGEN"
        }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "")
        return "\(weekday) \(calendar.component(.day, from: date))".uppercased()
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

/// Bijschrift met een streepje ervoor, in olijf.
struct WEyebrow: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(W.olive).frame(width: 12, height: 1)
            Text(text.uppercased()).font(W.text(9, .semibold)).tracking(1.4).foregroundStyle(W.olive).lineLimit(1)
        }
    }
}

/// Uren tegen het dagdoel: een putje met een inktbalk.
struct WGoalBar: View {
    let seconds: TimeInterval
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(W.well.shadow(.inner(color: W.ink.opacity(0.16), radius: 1.5, y: 1.5)))
                Rectangle().fill(W.ink)
                    .frame(width: proxy.size.width * min(1, seconds / WidgetSnapshot.dayGoal))
            }
        }
        .frame(height: height)
    }
}

/// De knoppen om tijd te schrijven (ontwerp D3): gelijk, wit met een limoen rand en het zwarte balkje eronder;
/// loopt er een timer, dan vooraan STOP met een oranje rand (opent de stopsheet) en spreken en typen als icoon.
struct WTimeButtons: View {
    var labels = false
    var running = false
    var height: CGFloat = 42

    private var showLabels: Bool { labels && !running }

    var body: some View {
        HStack(spacing: 6) {
            if running {
                Button(intent: StopTimerIntent()) {
                    face(icon: "stop.fill", title: labels ? "STOP" : nil, border: W.late)
                }
                .accessibilityLabel("Timer stoppen")
            }
            Button(intent: SpeakTimeIntent()) {
                face(icon: "mic", title: showLabels ? "SPREKEN" : nil, border: W.lime)
            }
            .accessibilityLabel("Tijd inspreken")
            Button(intent: TypeTimeIntent()) {
                face(icon: "keyboard", title: showLabels ? "TYPEN" : nil, border: W.lime)
            }
            .accessibilityLabel("Tijd typen")
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .padding(.bottom, 3)
    }

    private func face(icon: String, title: String?, border: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: title == nil ? 16 : 13, weight: .medium))
            if let title { Text(title).font(W.text(9.5, .semibold)).tracking(1.1).lineLimit(1) }
        }
        .foregroundStyle(W.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(W.card)
        .overlay(Rectangle().strokeBorder(border, lineWidth: 3))
        .background(Rectangle().fill(W.ink).offset(y: 3))
    }
}

/// Uren vandaag groot, "van 8:00" en de balk; loopt er iets, dan de klant en de lopende tijd erboven.
struct WHours: View {
    let entry: DayEntry
    var size: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let running = entry.running {
                HStack(spacing: 4) {
                    Rectangle().fill(W.late).frame(width: 6, height: 6)
                    Text(running.client.isEmpty ? "LOOPT" : running.client.uppercased())
                        .font(W.text(9, .semibold)).tracking(1.2).foregroundStyle(W.ink).lineLimit(1)
                }
            } else {
                WEyebrow(text: "Vandaag")
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(W.hm(entry.seconds)).font(W.poster(size)).foregroundStyle(W.ink)
                Text("van 8:00").font(W.text(10.5)).foregroundStyle(W.ink2)
            }
            .padding(.top, 4)
            WGoalBar(seconds: entry.seconds).padding(.top, 5)
        }
    }
}

// MARK: - B · Vandaag

struct TodayView: View {
    let entry: DayEntry

    private var day: Date { entry.shownDay }
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: entry.date) }
    private var list: [WidgetSnapshot.Event] { entry.events(on: day) }

    private var rows: [WidgetSnapshot.Event] {
        let list = self.list
        let firstOpen = list.firstIndex { $0.isAllDay || $0.end > entry.date } ?? list.count
        let start = max(0, min(firstOpen - 1, list.count - 5))
        return Array(list.dropFirst(start).prefix(5))
    }

    /// Vandaag of een latere dag: de weekdag, of "Morgen".
    private var eyebrow: String {
        if isToday { return day.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "") }
        let label = W.day(day, from: entry.date)
        return label == "MORGEN" ? "Morgen" : day.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WEyebrow(text: eyebrow)
                Text(day.formatted(.dateTime.day())).font(W.poster(66)).foregroundStyle(W.ink).padding(.top, 4)
                Text(day.formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased())
                    .font(W.poster(21)).foregroundStyle(W.ink2)
                Spacer(minLength: 0)
                Text(isToday ? (list.count == 1 ? "1 afspraak" : "\(list.count) afspraken")
                             : (entry.today.isEmpty ? "vandaag niets" : "vandaag klaar"))
                    .font(W.text(10)).foregroundStyle(W.ink2)
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if rows.isEmpty {
                    Text("Geen afspraken").font(W.text(12)).foregroundStyle(W.ink3)
                }
                ForEach(rows, id: \.self) { event in row(event) }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(W.agendaURL)
    }

    @ViewBuilder private func row(_ event: WidgetSnapshot.Event) -> some View {
        let past = !event.isAllDay && event.end <= entry.date
        let now = !event.isAllDay && event.start <= entry.date && event.end > entry.date
        let time = event.isAllDay ? "dag" : W.time(event.start)
        if now {
            HStack(spacing: 8) {
                Text(time).fontWeight(.semibold).frame(width: 32, alignment: .leading)
                Text(event.title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(W.text(12))
            .foregroundStyle(W.ink)
            .padding(.horizontal, 6)
            .frame(height: 25)
            .background(W.lime)
            .background(Rectangle().fill(W.ink).offset(y: 2))
            .overlay(Rectangle().strokeBorder(W.ink, lineWidth: 1.5))
            .padding(.horizontal, -6)
        } else {
            HStack(spacing: 8) {
                Text(time).frame(width: 32, alignment: .leading)
                Text(event.title).lineLimit(1)
            }
            .font(W.text(12))
            .foregroundStyle(past ? W.faint : W.ink)
            .frame(height: 21)
        }
    }
}

// MARK: - C · Tijd

struct TimeView: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WHours(entry: entry, size: 36)
            next.padding(.top, 9)
            Spacer(minLength: 6)
            WTimeButtons(labels: false, running: entry.running != nil, height: 40)
        }
        .widgetURL(W.timeURL)
    }

    /// De volgende eigen afspraak op één regel: de tijd op een limoen etiket (zoals in D), de titel erachter.
    @ViewBuilder private var next: some View {
        if let event = entry.next {
            HStack(spacing: 6) {
                Text(W.time(event.start)).font(W.poster(18)).foregroundStyle(W.ink)
                    .padding(.horizontal, 4).padding(.top, 1)
                    .background(W.lime)
                    .background(Rectangle().fill(W.ink).offset(y: 2))
                let day = W.day(event.start, from: entry.date)
                Text(day.isEmpty ? event.title : "\(day.lowercased()) · \(event.title)")
                    .font(W.text(11, .semibold)).foregroundStyle(W.ink).lineLimit(1)
            }
        } else {
            Text("Geen afspraken meer").font(W.text(11)).foregroundStyle(W.ink3)
        }
    }
}

// MARK: - D · Tijd en volgende

struct TimeNextView: View {
    let entry: DayEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Link(destination: W.timeURL) { WHours(entry: entry, size: 44) }
                Spacer(minLength: 6)
                WTimeButtons(labels: true, running: entry.running != nil, height: 40)
            }
            Link(destination: W.agendaURL) { next }
                .frame(width: 128)
        }
    }

    private var next: some View {
        VStack(alignment: .leading, spacing: 0) {
            let day = entry.next.map { W.day($0.start, from: entry.date) } ?? ""
            Text(day.isEmpty ? "VOLGENDE" : "VOLGENDE · \(day)")
                .font(W.text(8.5, .semibold)).tracking(1.4).foregroundStyle(W.ink2).lineLimit(1)
            if let event = entry.next {
                // Ontwerp D3: de tijd op een limoen etiket met een balkje eronder.
                Text(W.time(event.start)).font(W.poster(32)).foregroundStyle(W.ink)
                    .padding(.horizontal, 5).padding(.top, 2)
                    .background(W.lime)
                    .background(Rectangle().fill(W.ink).offset(y: 2))
                    .padding(.top, 6)
                Text(event.title).font(W.text(12, .semibold)).foregroundStyle(W.ink).lineLimit(1).padding(.top, 6)
                Spacer(minLength: 4)
                // Daarna nog twee, klein.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.afterNext, id: \.self) { later in
                        HStack(spacing: 5) {
                            let laterDay = W.day(later.start, from: entry.date)
                            Text(laterDay.isEmpty ? W.time(later.start)
                                                  : "\(laterDay == "MORGEN" ? "morgen" : laterDay.prefix(2).lowercased()) \(W.time(later.start))")
                                .fontWeight(.semibold)
                            Text(later.title).lineLimit(1)
                        }
                        .font(W.text(9.5))
                        .foregroundStyle(W.ink2)
                    }
                }
            } else {
                Text("Niets meer").font(W.text(12)).foregroundStyle(W.ink3).padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Rectangle().fill(W.well.shadow(.inner(color: W.ink.opacity(0.16), radius: 2, y: 2))))
    }
}

// MARK: - F · Vergrendelscherm

struct LockSpeakView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill").font(.system(size: 22, weight: .medium))
        }
        .widgetURL(W.speakURL)
        .accessibilityLabel("Tijd inspreken")
    }
}

struct LockHoursView: View {
    let entry: DayEntry

    var body: some View {
        Gauge(value: min(1, entry.seconds / WidgetSnapshot.dayGoal)) {
            Text("Uren")
        } currentValueLabel: {
            Text(W.hm(entry.seconds))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(W.timeURL)
    }
}

struct LockNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                if let event = entry.next {
                    let day = W.day(event.start, from: entry.date).lowercased()
                    Label("\(day.isEmpty ? "" : day + " ")\(W.time(event.start)) \(event.title)", systemImage: "calendar")
                } else {
                    Label("Geen afspraken meer", systemImage: "calendar")
                }
            } else if let event = entry.next {
                VStack(alignment: .leading, spacing: 1) {
                    let day = W.day(event.start, from: entry.date).lowercased()
                    Text("\(day.isEmpty ? "" : day + " ")\(W.time(event.start)) – \(W.time(event.end))")
                        .font(.caption2.weight(.semibold))
                    Text(event.title).font(.headline).lineLimit(1)
                    if !event.location.isEmpty { Text(event.location).font(.caption2).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Geen afspraken meer").font(.headline)
            }
        }
        .widgetURL(W.agendaURL)
    }
}
