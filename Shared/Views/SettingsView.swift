import SwiftData
import SwiftUI
#if os(macOS)
import KeyboardShortcuts
#endif

struct SettingsView: View {
    @AppStorage(SettingsKey.roundingMinutes) private var rounding = 15
    @AppStorage(SettingsKey.agendaMode) private var agendaMode = "week"
    @AppStorage(SettingsKey.workDays) private var workDays = "1,2,3,4,5"
    @AppStorage(SettingsKey.startHour) private var startHour = 8
    @AppStorage(SettingsKey.endHour) private var endHour = 18
    @AppStorage(SettingsKey.defaultCalendar) private var defaultCalendar = ""
    @AppStorage(SettingsKey.googleAPIKey) private var apiKey = ""
    @AppStorage(SettingsKey.googleCX) private var searchEngineID = ""
    @AppStorage(SettingsKey.longRunMinutes) private var longRunMinutes = 60

    @Environment(\.modelContext) private var context
    @Query(sort: \ClientMapping.domain) private var mappings: [ClientMapping]
    @State private var newDomain = ""
    @State private var newClient = ""

    private let calendarService = CalendarService.shared
    private static let dayNames = ["ma", "di", "wo", "do", "vr", "za", "zo"]

    var body: some View {
        Form {
            #if os(macOS)
            Section("Snelle invoer") {
                KeyboardShortcuts.Recorder("Sneltoets", name: .quickEntry)
            }
            #endif

            Section("Facturatie") {
                Picker("Afronden op", selection: $rounding) {
                    Text("1 minuut").tag(1)
                    Text("6 minuten").tag(6)
                    Text("15 minuten").tag(15)
                }
                Stepper("Waarschuwing na \(longRunMinutes) min zonder pauze",
                        value: $longRunMinutes, in: 15...480, step: 15)
            }

            Section("Agenda") {
                Picker("Weergave", selection: $agendaMode) {
                    Text("Werkweek").tag("week")
                    Text("Dag").tag("day")
                }
                .pickerStyle(.segmented)

                LabeledContent("Werkdagen") {
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(Self.dayNames[day - 1], isOn: dayBinding(day))
                                .toggleStyle(.button)
                        }
                    }
                }
                Stepper("Begin: \(startHour):00", value: $startHour, in: 0...(endHour - 1))
                Stepper("Einde: \(endHour):00", value: $endHour, in: (startHour + 1)...24)

                if calendarService.hasAccess {
                    Picker("Standaard doelagenda", selection: $defaultCalendar) {
                        Text("Automatisch (\"Werk\" of eerste)").tag("")
                        ForEach(calendarService.writableCalendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                } else {
                    Text("Geef Werkbank toegang tot je agenda's om een doelagenda te kiezen.")
                        .foregroundStyle(ThingsColor.textSecondary)
                }
            }

            Section {
                ForEach(mappings) { mapping in
                    HStack {
                        Text(mapping.domain).monospaced()
                        Spacer()
                        Text(mapping.client).foregroundStyle(ThingsColor.textSecondary)
                        Button(role: .destructive) {
                            context.delete(mapping)
                            try? context.save()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("domein.nl", text: $newDomain)
                    TextField("Klant", text: $newClient)
                    Button("Voeg toe") { addMapping() }
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty
                                  || newClient.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Koppeltabel domein → klant")
            } footer: {
                Text("Wordt ook automatisch aangevuld als je het label van een mailkaart wijzigt.")
            }

            Section {
                SecureField("API-sleutel", text: $apiKey)
                TextField("Search Engine ID (cx)", text: $searchEngineID)
            } header: {
                Text("Logo's zoeken (Google Afbeeldingen)")
            } footer: {
                Text("Zonder sleutel gebruikt Werkbank het favicon van het domein.")
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { AppSettings.parseWorkDays(workDays).contains(day) },
            set: { on in
                var days = Set(AppSettings.parseWorkDays(workDays))
                if on { days.insert(day) } else if days.count > 1 { days.remove(day) }
                workDays = days.sorted().map(String.init).joined(separator: ",")
            }
        )
    }

    private func addMapping() {
        BoardService.upsertMapping(domain: newDomain.trimmingCharacters(in: .whitespaces),
                                   client: newClient.trimmingCharacters(in: .whitespaces), in: context)
        try? context.save()
        newDomain = ""
        newClient = ""
    }
}
