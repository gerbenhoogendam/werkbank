import SwiftData
import SwiftUI
#if os(macOS)
import KeyboardShortcuts
#endif

/// Voorkeuren met drie tabs: Agenda's, Weergave en Overig.
/// macOS: eigen venster (⌘,). iOS: als blad vanuit het tandwiel.
struct PreferencesView: View {
    var body: some View {
        TabView {
            CalendarsPreferences()
                .tabItem { Label("Agenda's", systemImage: "calendar") }
            DisplayPreferences()
                .tabItem { Label("Weergave", systemImage: "paintbrush") }
            OtherPreferences()
                .tabItem { Label("Overig", systemImage: "gearshape") }
        }
        #if os(macOS)
        .frame(width: 560, height: 500)
        #endif
    }
}

// MARK: - Agenda's

private struct CalendarsPreferences: View {
    @AppStorage(SettingsKey.hiddenCalendars) private var hiddenRaw = ""
    @AppStorage(SettingsKey.defaultCalendar) private var defaultCalendar = ""

    private let service = CalendarService.shared

    var body: some View {
        Form {
            if service.hasAccess {
                Section {
                    ForEach(service.calendars) { calendar in
                        Toggle(isOn: visibleBinding(calendar.id)) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(calendar.color)
                            }
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                    }
                } header: {
                    Text("Zichtbare agenda's")
                } footer: {
                    Text("Uitgevinkte agenda's zijn nergens zichtbaar. De aangevinkte agenda's kun je boven de agenda tijdelijk aan/uit zetten. Er wordt niets aan de agenda's zelf gewijzigd.")
                }

                Section("Standaard agenda") {
                    Picker("Nieuwe afspraken in", selection: $defaultCalendar) {
                        Text("Automatisch (\"Werk\" of eerste)").tag("")
                        ForEach(service.writableCalendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                }
            } else {
                Section {
                    CalendarAccessView(service: service)
                        .frame(minHeight: 260)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func visibleBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !AppSettings.parseHidden(hiddenRaw).contains(id) },
            set: { visible in
                var hidden = AppSettings.parseHidden(hiddenRaw)
                if visible { hidden.remove(id) } else { hidden.insert(id) }
                hiddenRaw = hidden.sorted().joined(separator: ",")
            }
        )
    }
}

// MARK: - Weergave

private struct DisplayPreferences: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system.rawValue
    @AppStorage(SettingsKey.agendaMode) private var agendaMode = "week"
    @AppStorage(SettingsKey.workDays) private var workDays = "1,2,3,4,5"
    @AppStorage(SettingsKey.startHour) private var startHour = 8
    @AppStorage(SettingsKey.endHour) private var endHour = 18

    private static let dayNames = ["ma", "di", "wo", "do", "vr", "za", "zo"]

    var body: some View {
        Form {
            Section("Uiterlijk") {
                Picker("Thema", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
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
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, new in
            #if os(macOS)
            AppearanceSetting(stored: new).applyToApp()
            #endif
        }
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
}

// MARK: - Overig

private struct OtherPreferences: View {
    @AppStorage(SettingsKey.roundingMinutes) private var rounding = 15
    @AppStorage(SettingsKey.longRunMinutes) private var longRunMinutes = 60
    @AppStorage(SettingsKey.googleAPIKey) private var apiKey = ""
    @AppStorage(SettingsKey.googleCX) private var searchEngineID = ""
    @AppStorage(Persistence.cloudToggleKey) private var iCloudSync = true

    @Environment(\.modelContext) private var context
    @Query(sort: \ClientMapping.domain) private var mappings: [ClientMapping]
    @State private var newDomain = ""
    @State private var newClient = ""

    var body: some View {
        Form {
            #if os(macOS)
            Section("Snelle invoer") {
                KeyboardShortcuts.Recorder("Sneltoets", name: .quickEntry)
            }
            #endif

            Section {
                Toggle("Synchroniseren via iCloud", isOn: $iCloudSync)
                    .disabled(!Persistence.isCloudBuild)
            } header: {
                Text("iCloud")
            } footer: {
                Text(iCloudStatus)
            }

            Section("Facturatie") {
                Picker("Afronden op", selection: $rounding) {
                    Text("1 minuut").tag(1)
                    Text("6 minuten").tag(6)
                    Text("15 minuten").tag(15)
                }
                Stepper("Waarschuwing na \(longRunMinutes) min zonder pauze",
                        value: $longRunMinutes, in: 15...480, step: 15)
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
    }

    private func addMapping() {
        BoardService.upsertMapping(domain: newDomain.trimmingCharacters(in: .whitespaces),
                                   client: newClient.trimmingCharacters(in: .whitespaces), in: context)
        try? context.save()
        newDomain = ""
        newClient = ""
    }
}

extension OtherPreferences {
    fileprivate var iCloudStatus: String {
        if !Persistence.isCloudBuild {
            return "Deze build is niet voor iCloud ingericht: de gegevens blijven alleen op dit apparaat."
        }
        if Persistence.isSyncing {
            return "Kaarten en tijdregels worden via iCloud met je andere apparaten gesynchroniseerd. Voorkeuren en de agenda-keuze blijven per apparaat. Een wijziging van deze schakelaar geldt na herstarten."
        }
        return Persistence.syncPreferred
            ? "Niet actief: log in bij iCloud op dit apparaat en start Werkbank opnieuw."
            : "Uit: de gegevens blijven alleen op dit apparaat. Geldt na herstarten."
    }
}
