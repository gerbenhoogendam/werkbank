import SwiftUI
import WerkbankCore

/// Een afspraak bekijken: titel, tijd, plaats, notities en deelnemers; tijd schrijven of openen in Agenda.
struct AgendaEventSheet: View {
    let event: AgendaEvent
    /// Sluit het blad en opent daarna de tijdinvoer.
    let onWriteTime: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        PhEyebrow(text: event.calendarTitle)
                        Text(event.title.uppercased())
                            .font(Ph.poster(40))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .padding(.bottom, -4)
                        if !event.isAllDay {
                            HStack(alignment: .lastTextBaseline, spacing: 10) {
                                Text("\(DutchDate.time(event.start)) – \(DutchDate.time(event.end))")
                                    .font(Ph.poster(28))
                                    .foregroundStyle(Ph.ink)
                                PhCaps(text: Billing.formatHM(event.end.timeIntervalSince(event.start)), size: 10.5)
                            }
                        }
                    }
                    details
                    if let notes = event.notes { notesCard(notes) }
                    if !event.attendees.isEmpty { attendeesCard }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            actions
        }
        .background(Ph.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Ph.paper)
        .presentationDragIndicator(.visible)
    }

    private var timeText: String {
        let day = AgendaDates.dayAndMonth(event.start)
        if event.isAllDay { return "\(day) · HELE DAG" }
        if !AgendaDates.sameDay(event.start, event.end.addingTimeInterval(-1)) {
            return "\(day) \(DutchDate.time(event.start)) – \(AgendaDates.dayAndMonth(event.end)) \(DutchDate.time(event.end))"
        }
        return "\(day) · \(DutchDate.time(event.start)) – \(DutchDate.time(event.end))"
    }

    private var details: some View {
        VStack(spacing: 0) {
            PhFieldRow(label: "Tijd") {
                Text(timeText)
                    .font(Ph.text(14))
                    .monospacedDigit()
                    .foregroundStyle(Ph.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            if let location = event.location {
                PhFieldRow(label: "Waar") {
                    Text(location)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            }
            PhFieldRow(label: "Agenda") {
                HStack(spacing: 8) {
                    Rectangle().fill(event.color).frame(width: 10, height: 10)
                    Text(event.calendarTitle)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if let organizer = event.organizer {
                PhFieldRow(label: "Van") {
                    Text(organizer)
                        .font(Ph.text(14))
                        .foregroundStyle(Ph.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let url = event.url {
                PhFieldRow(label: "Link") {
                    Button {
                        openURL(url)
                    } label: {
                        Text(url.host ?? url.absoluteString)
                            .font(Ph.text(14, .medium))
                            .foregroundStyle(Ph.olive)
                            .underline()
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .phCard()
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhCaps(text: "Notities")
            Text(notes)
                .font(Ph.text(14))
                .foregroundStyle(Ph.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .phCard()
        }
    }

    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhCaps(text: "Deelnemers \(event.attendees.count)")
            VStack(spacing: 0) {
                ForEach(Array(event.attendees.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 10) {
                        PhAvatar(name: name, size: 28)
                        Text(name)
                            .font(Ph.text(14))
                            .foregroundStyle(Ph.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if index < event.attendees.count - 1 { Rectangle().fill(Ph.hair).frame(height: 1) }
                    }
                }
            }
            .phCard()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("TIJD SCHRIJVEN", action: onWriteTime)
                .buttonStyle(PhPrimaryStyle())
            Button("OPEN IN AGENDA") {
                let seconds = Int(event.start.timeIntervalSinceReferenceDate)
                if let url = URL(string: "calshow:\(seconds)") { openURL(url) }
            }
            .buttonStyle(PhSecondaryStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ph.paper)
        .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
    }
}
