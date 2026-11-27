import AppIntents
import SwiftUI
import WidgetKit

/// Widgets van Zwoeg Bank (ontwerp: canvas "Werkbank iOS", pagina Widgets): B Vandaag, C Tijd, D Tijd en volgende,
/// F op het vergrendelscherm en G in het bedieningspaneel.
@main
struct ZwoegWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TimeWidget()
        TimeNextWidget()
        LockSpeakWidget()
        LockHoursWidget()
        LockNextWidget()
        SpeakTimeControl()
        TypeTimeControl()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.vandaag", provider: DayProvider()) { entry in
            TodayView(entry: entry).containerBackground(W.paper, for: .widget)
        }
        .configurationDisplayName("Vandaag")
        .description("De afspraken van vandaag.")
        .supportedFamilies([.systemMedium])
    }
}

struct TimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.tijd", provider: DayProvider()) { entry in
            TimeView(entry: entry).containerBackground(W.paper, for: .widget)
        }
        .configurationDisplayName("Tijd")
        .description("Uren vandaag; inspreken of typen.")
        .supportedFamilies([.systemSmall])
    }
}

struct TimeNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.tijd-volgende", provider: DayProvider()) { entry in
            TimeNextView(entry: entry).containerBackground(W.paper, for: .widget)
        }
        .configurationDisplayName("Tijd en volgende")
        .description("Uren vandaag en de volgende afspraak.")
        .supportedFamilies([.systemMedium])
    }
}

struct LockSpeakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.lock-inspreken", provider: DayProvider()) { _ in
            LockSpeakView().containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Tijd inspreken")
        .description("Opent het inspreken van tijd.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockHoursWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.lock-uren", provider: DayProvider()) { entry in
            LockHoursView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Uren vandaag")
        .description("Uren tegen 8 uur.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZwoegBank.lock-volgende", provider: DayProvider()) { entry in
            LockNextView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Volgende afspraak")
        .description("De volgende afspraak.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

// MARK: - G · Bedieningspaneel (ook vergrendelscherm en Actieknop)

struct SpeakTimeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ZwoegBank.control-inspreken") {
            ControlWidgetButton(action: SpeakTimeIntent()) {
                Label("Tijd inspreken", systemImage: "mic.fill")
            }
        }
        .displayName("Tijd inspreken")
    }
}

struct TypeTimeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ZwoegBank.control-typen") {
            ControlWidgetButton(action: TypeTimeIntent()) {
                Label("Tijd typen", systemImage: "keyboard")
            }
        }
        .displayName("Tijd typen")
    }
}
