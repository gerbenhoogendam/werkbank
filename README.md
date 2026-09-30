# Werkbank

Native macOS- en iOS-app (SwiftUI, SwiftData, EventKit) in de visuele stijl van Things.
Functionele specificatie: [`Werkbank-Specificatie.md`](Werkbank-Specificatie.md). Ontwerpspecificatie: [`Things-Design.md`](Things-Design.md).

> **Status: bouwt en de kerntests slagen, maar de app is nog niet uitgeprobeerd.** De code is geschreven zonder
> Xcode (Linux-omgeving). GitHub Actions (`.github/workflows/werkbank.yml`) bouwt beide targets op een macOS-runner
> (Werkbank-macOS en Werkbank-iOS voor de simulator, zonder codesigning) en draait de 38 tests van `WerkbankCore`; alles is groen.
> Niemand heeft de app gestart. Het slepen, de agendatoegang, de menubalk, de snelle invoer en het inplannen zijn dus
> alleen gecompileerd, niet uitgevoerd. Verwacht gedrags- en visuele afwijkingen bij het eerste gebruik.

## Bouwen

Vereist Xcode 16 of nieuwer (macOS 14+ / iOS 17+ als doelplatform) en [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Werkbank.xcodeproj
```

Daarna in `project.yml` of in Xcode: `DEVELOPMENT_TEAM` invullen en `com.example` vervangen door je eigen bundle-prefix.
Twee schema's: **Werkbank-macOS** en **Werkbank-iOS**. Het pakket `KeyboardShortcuts` (globale sneltoets) wordt via Swift Package Manager opgehaald.

## Tests en CI

De logica staat in een Foundation-only pakket, zodat ze los van de UI te testen is. Dezelfde tests, plus een build van beide targets, draaien op GitHub Actions bij elke push en pull request.

```sh
cd WerkbankCore
swift test
```

Gedekt: .eml-parsing (encoded words, gevouwen headers), klantnaam uit domein, hashtag-label, afronding op 1/6/15 min,
eindtijdcorrectie, afronden op 15 min bij inplannen, prefixregel (vdm/ndm/tijd), GH-titelopbouw, overlappende afspraken en CSV-export.

## Indeling

| Map | Inhoud |
|---|---|
| `WerkbankCore/` | Pure logica + unit tests |
| `Shared/Design/` | `ThingsTheme.swift`, `ThingsComponents.swift` (aangeleverd), `WerkbankTokens.swift` (extra tokens) |
| `Shared/Models/` | SwiftData: `TodoCard`, `TimeEntry`, `ClientMapping` |
| `Shared/Services/` | Timer, board, agenda (EventKit), logo's, mailimport, instellingen |
| `Shared/Views/` | Kaart, Tijd schrijven, stopsheet, snelle support, instellingen, inplan-bevestiging |
| `macOS/` | Hoofdvenster, board met slepen, agenda, snelle invoer (NSPanel), menubalk |
| `iOS/` | Tabs (Board, Agenda, Tijd), Magic Plus, inplanblad |

## Wat er is (macOS)

- Hoofdvenster: board boven (45%), agenda linksonder (¾), Tijd schrijven rechtsonder (¼).
- Board met vijf kolommen; eigen sleepgebaar (start na 5 px, 105% schaal, kanteling ±14°, placeholder, vlucht naar de plek met "pop").
- Kaarten naar de agenda slepen: starttijd (kwartieren) → eindtijd (greep) → popover met `GH: vdm|ndm|<tijd> <titel>` → echt `EKEvent`.
- Snelle invoer met globale sneltoets (standaard ⌥⌘T), `#klant` wordt label.
- `.eml` op het venster slepen → kaarten in de Inbox, klantnaam uit domein/koppeltabel/freemail, logo via Google Custom Search met favicon-terugval.
- Tijd schrijven: één lopende timer, pauze/hervat/stop, verplichte omschrijving, eindtijdcontrole, afronding, "geschreven"-vinkje, CSV-export (`BillingExporter`-protocol).
- Menubalkknop met lopende tijd, bestaande to-do starten, snelle support (starten of direct loggen).
- Voorkeuren (⌘,), een eigen venster met tabs: **Agenda's** (welke agenda's zichtbaar zijn, standaard doelagenda), **Weergave** (thema automatisch/licht/donker, werkweek of dag, werkdagen, uren) en **Overig** (sneltoets, afronding, waarschuwingsdrempel, koppeltabel, Google-sleutel).

## iOS: bewust anders

Het bureaubladontwerp (board + agenda + tijdlijst tegelijk, slepen tussen panelen) past niet op een telefoon. Op iOS:

- Drie tabs: **Board** (kolomkiezer + lijst), **Agenda** (dagoverzicht), **Tijd** (dezelfde lijst als op de Mac).
- Kaarten verplaats je via het contextmenu ("Verplaats naar"), herschikken via "Wijzig", timer via veeg of knop.
- Inplannen via een blad met datumkiezers, met dezelfde kwartier- en `GH:`-regels.
- Magic Plus voor een nieuwe kaart (Board) of snelle support (Tijd). Lopende timer als balk onderaan.
- `.eml` importeren via de menuknop of slepen (iPad).
- Geen globale sneltoets en geen menubalk (bestaan niet op iOS).

## Bekende risico's en open punten

- **Slepen** (`macOS/DragCoordinator.swift`, `BoardView.swift`, `AgendaView.swift`) is het meest complexe deel; het compileert maar is nooit uitgevoerd. De index-berekening gebruikt gemeten kaarthoogtes; de agenda schuift bij de boven-/onderrand per uur.
- **Mail uit Mail.app slepen**: wordt verwerkt als `public.email-message`-data of als bestands-URL met extensie `.eml`. Of Mail.app op jouw systeem een van die twee aanbiedt (i.p.v. een bestandsbelofte) is niet getest. Sleep anders eerst naar Finder.
- **Autoscroll van de agenda** tijdens slepen gaat per uur en houdt de laatst bekende scrollpositie bij; na handmatig scrollen kan de eerste stap verspringen.
- **Hele-dag-afspraken** staan in een strook onder de dagkop; ze hebben geen tijdblok.
- **Popover inplannen** is een eigen zwevend paneel (geen `NSPopover`); de hoogte is een schatting van 300 pt.
- **Eindtijd bij inplannen** wordt begrensd op het einde van het zichtbare agenda-uur (instelling), niet op middernacht.
- **Voor 08:00** is de standaardprefix `vdm` (de spec zegt daar niets over).
- **Google API-sleutel** staat in `UserDefaults` (niet in de Keychain).
- Geen app-icoon en geen asset-catalogus.
- De bundle-id is een placeholder (`com.example.werkbank`).

## iCloud-synchronisatie

Kaarten, tijdregels en de koppeltabel worden via iCloud (SwiftData + CloudKit) tussen je Mac en iPhone/iPad
gesynchroniseerd. Voorkeuren en de agenda-keuze blijven per apparaat; twee apparaten kunnen elk een eigen lopende timer hebben.
Status en een schakelaar staan in Voorkeuren › Overig (een wijziging geldt na herstarten).

Instellen (eenmalig, betaald Apple Developer-account nodig):
1. Zet in `project.yml` bij `BUNDLE_ID_PREFIX` je eigen prefix (bijv. `nl.gerbenhoogendam`) en je Team ID bij `DEVELOPMENT_TEAM`.
   Het bundle-id wordt `<prefix>.werkbank`, de iCloud-container `iCloud.<prefix>.werkbank`.
2. `xcodegen generate` en open het project. Xcode maakt bij automatische ondertekening de container en het
   push-profiel zelf aan (Signing & Capabilities toont iCloud › CloudKit en Push Notifications).
3. Log op elk apparaat in bij iCloud en gebruik dezelfde prefix op Mac en iOS.

Let op: de eerste keer dat CloudKit draait, wordt het schema in de *Development*-omgeving aangemaakt. Voor
TestFlight/App Store moet je het schema in het CloudKit Dashboard naar *Production* uitrollen.
Bestaande lokale gegevens uit een build zonder iCloud worden meegenomen; lukt de migratie niet, dan bewaart de app de
oude database als back-up (`default.store.backup-…`) en begint leeg.
