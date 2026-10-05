# Werkbank

Native macOS- en iOS-app (SwiftUI, SwiftData, EventKit) in de visuele stijl van Things.
Functionele specificatie: [`Werkbank-Specificatie.md`](Werkbank-Specificatie.md). Ontwerpspecificatie: [`Things-Design.md`](Things-Design.md).

> **Status: bouwt en de kerntests slagen, maar de app is nog niet uitgeprobeerd.** De code is geschreven zonder
> Xcode (Linux-omgeving). GitHub Actions (`.github/workflows/werkbank.yml`) bouwt beide targets op een macOS-runner
> (Werkbank-macOS en Werkbank-iOS voor de simulator, zonder codesigning) en draait de 38 tests van `WerkbankCore`; alles is groen.
> Niemand heeft de app gestart. Het slepen, de agendatoegang, de menubalk, de snelle invoer en het inplannen zijn dus
> alleen gecompileerd, niet uitgevoerd. Verwacht gedrags- en visuele afwijkingen bij het eerste gebruik.

## Bouwen

Snel: `./Scripts/update.sh` haalt de nieuwste versie op, maakt het project opnieuw en opent het in Xcode.
Handmatig:

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
- Board met kolommen (standaard Inbox, Te doen, Bezig, Wacht op klant) die je kunt hernoemen, toevoegen en verwijderen (menu ⋯ in de kolomkop; toevoegen via Voorkeuren › Kolommen, op iOS via de tegel rechts van de laatste kolom); het icoon (SF Symbol uit een keuze of zelf getypt, of een emoji) en de kleur kies je door op het icoon in de kolomkop te klikken (ook via ⋯ › Icoon en kleur…); een kolom verplaats je door aan de kolomkop te slepen (of via het menu: Naar links/rechts); bij verwijderen gaan de kaarten naar de eerste andere kolom; eigen sleepgebaar (start na 5 px, 105% schaal, kanteling ±14°, placeholder, vlucht naar de plek met "pop").
- Kaarten naar de agenda slepen: starttijd (kwartieren) → eindtijd (greep) → popover met `GH: vdm|ndm|<tijd> <titel>` → echt `EKEvent`.
- Taken openen met één klik (Mac) of tik (iOS): titel, klant, notities en subtaken. Subtaken staan ook op de kaart (afvinken); op de Mac verschijnt "Subtaak toevoegen" onderaan de kaart zodra je erboven zweeft, Return voegt toe en gaat door met de volgende. Op iOS voeg je subtaken toe in het geopende venster.
- Afronden: het ronde vakje links van de titel (of Afronden in het contextmenu) haalt een taak van het board; afgeronde taken staan in het archief (knop met archiefdoosje in de werkbalk naast Voorkeuren, op iOS in de balk van het board) met Terugzetten en Verwijderen. 'Klaar' is dus geen kolom meer; kaarten uit een oude Klaar-kolom staan na de update in het archief (zonder afrondingsdatum).
- Snelle invoer met globale sneltoets (standaard ⌥⌘T), `#klant` wordt label.
- `.eml` op het venster slepen → kaarten in de Inbox, klantnaam uit domein/koppeltabel/freemail, logo via Google Custom Search met favicon-terugval.
- Gmail-paneel links (⌥⌘G): inloggen met Google, inbox bekijken, een mail naar een kolom slepen. De mail wordt een kaart (titel, afzender, tekst) en wordt daarna in Gmail gearchiveerd. Zie "Gmail koppelen".
- Tijd schrijven: één lopende timer, pauze/hervat/stop, verplichte omschrijving, eindtijdcontrole, afronding, "geschreven"-vinkje (een afgevinkte regel gaat naar het uitklapbare onderdeel "Al geschreven" onderaan), CSV-export (`BillingExporter`-protocol).
- Menubalkknop met lopende tijd, bestaande to-do starten, snelle support (starten of direct loggen).
- Voorkeuren (⌘,), een eigen venster met tabs: **Agenda's** (welke agenda's zichtbaar zijn, standaard doelagenda), **Weergave** (thema automatisch/licht/donker, werkweek of dag, werkdagen, uren), **Kolommen** (toevoegen, hernoemen, icoon, verwijderen) en **Overig** (sneltoets, afronding, waarschuwingsdrempel, koppeltabel, Google-sleutel).

## iOS: bewust anders

Het bureaubladontwerp (board + agenda + tijdlijst tegelijk, slepen tussen panelen) past niet op een telefoon. Op iOS:

- Drie tabs: **Board** (alle kolommen naast elkaar, horizontaal scrollen), **Agenda** (dagoverzicht), **Tijd** (dezelfde lijst als op de Mac).
- Kaarten pak je op door ze ingedrukt te houden en sleep je naar een andere kolom of een andere plek in dezelfde kolom (contextmenu "Verplaats naar" blijft als alternatief), timer via veeg of knop. Kolommen hernoem, voeg toe en verwijder je via het menu in de kolomkop.
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
- **Kolommen en slepen op iOS**: kolombeheer (`ColumnRecord`, `BoardService`) en slepen met `draggable`/`dropDestination` zijn niet uitgevoerd op een apparaat. Of het scherm tijdens het slepen vanzelf horizontaal naar de volgende kolom schuift is niet getest. Kolommen verplaatsen is niet op een apparaat uitgeprobeerd; op iOS moet je daarvoor de kolomkop ingedrukt houden. Maakt een tweede apparaat de standaardkolommen aan vóórdat iCloud een verwijdering heeft binnengehaald, dan kan een verwijderde standaardkolom terugkomen.
- **Taak openen met één klik** vervangt het dubbelklikken op titel of klant op de kaart (dat kon niet naast een enkele klik). Nieuwe kaarten openen nog wel direct in bewerkmodus; titel en klant pas je daarna aan in het geopende venster. Of klikken op de kaart het slepen op het Mac-board niet hindert is niet getest.
- **Gmail-paneel**: compileert, maar is nooit uitgevoerd tegen een echt Google-account. Archiveren haalt het label INBOX van het hele gesprek (zoals de knop Archiveren in Gmail), niet alleen van het gesleepte bericht.
- De bundle-id is een placeholder (`com.example.werkbank`).

## iCloud-synchronisatie

Kaarten, tijdregels en de koppeltabel worden via iCloud (SwiftData + CloudKit) tussen je Mac en iPhone/iPad
gesynchroniseerd. Voorkeuren en de agenda-keuze blijven per apparaat; twee apparaten kunnen elk een eigen lopende timer hebben.
Status en een schakelaar staan in Voorkeuren › Overig (een wijziging geldt na herstarten).

Instellen (eenmalig, betaald Apple Developer-account nodig):
1. `cp Config/Local.xcconfig.example Config/Local.xcconfig` en vul `APP_BUNDLE_ID` (jouw unieke bundle-id, bijv.
   `nl.itgwerkbank.werkbank`) en `DEVELOPMENT_TEAM` (Team ID) in. Dit bestand wordt niet gecommit en blijft
   dus staan bij elke `xcodegen generate`. De iCloud-container wordt `iCloud.<APP_BUNDLE_ID>`.
2. `xcodegen generate` en open het project. Xcode maakt bij automatische ondertekening de App ID, de container en het
   push-profiel zelf aan (Signing & Capabilities toont iCloud › CloudKit en Push Notifications).
3. Log op elk apparaat in bij iCloud en gebruik op Mac en iOS hetzelfde bundle-id.

Let op: de eerste keer dat CloudKit draait, wordt het schema in de *Development*-omgeving aangemaakt. Voor
TestFlight/App Store moet je het schema in het CloudKit Dashboard naar *Production* uitrollen.
Bestaande lokale gegevens uit een build zonder iCloud worden meegenomen; lukt de migratie niet, dan bewaart de app de
oude database als back-up (`default.store.backup-…`) en begint leeg.

## Gmail koppelen

Het Gmail-paneel (macOS) gebruikt de Gmail API met inloggen via Google (OAuth met PKCE). Er staat geen wachtwoord of client secret
in de app; de refresh-token staat in de sleutelhanger. De app vraagt de scope `gmail.modify`: lezen en archiveren, geen verwijderen of versturen.

Eenmalig instellen (gratis Google-account volstaat):
1. Maak op [console.cloud.google.com](https://console.cloud.google.com) een project en zet onder *APIs & Services › Library* de **Gmail API** aan.
2. *OAuth-toestemmingsscherm* (Google Auth Platform): type **Extern**, app-naam Werkbank, jouw e-mailadres. Voeg onder *Gegevenstoegang* de scope
   `https://www.googleapis.com/auth/gmail.modify` toe en jouw Gmail-adres als testgebruiker.
3. Zet de publicatiestatus op **In productie**. Blijft hij op *Testen*, dan verloopt de login elke 7 dagen. In productie zonder verificatie
   toont Google bij het eerste inloggen "Google heeft deze app niet geverifieerd": kies *Geavanceerd › Doorgaan naar Werkbank*. Voor eigen gebruik is verificatie niet nodig (limiet 100 gebruikers).
4. *Credentials › OAuth-client-ID aanmaken*, type **iOS**, bundle-id = jouw `APP_BUNDLE_ID`. Kopieer de client-id (eindigt op `.apps.googleusercontent.com`).
5. Zet in `Config/Local.xcconfig`: `GOOGLE_CLIENT_ID = <client-id>`, draai `xcodegen generate` en bouw opnieuw.

Gebruik: ⌥⌘G of de knop linksboven in de werkbalk opent het paneel; *Inloggen met Google*. Klik een mail om hem in de lijst open te klappen (alleen de tekst, geen opmaak of bijlagen); de archiefknop staat in de rij (bij aanwijzen) en onder de opengeklapte mail en archiveert zonder kaart. Onder de tekst kun je ook meteen een taak maken: titel (standaard het onderwerp), al bestede minuten en kolom; daarna wordt de mail gearchiveerd. Veeg een mail (twee vingers op het trackpad) naar links om te archiveren of naar rechts om meteen een taak te maken (onderwerp als titel, in de Inbox, daarna gearchiveerd). Sleep een mail naar een kolom. Eerst wordt de kaart gemaakt,
daarna wordt de mail in Gmail gearchiveerd. Mislukt archiveren, dan blijft de kaart staan, blijft de mail in de inbox en krijg je een melding.

## TestFlight (testers uitnodigen)

De build en upload lopen via GitHub Actions (`.github/workflows/testflight.yml`); jij regelt eenmalig de Apple-kant en de geheimen.
Dit is nog nooit uitgevoerd: ik kan niet inloggen bij Apple. Verwacht dat de eerste run om iets vraagt.

**Eenmalig bij Apple**
1. [developer.apple.com](https://developer.apple.com) › Account: je betaalde account en je Team ID (staat al in `Config/Local.xcconfig`).
2. [App Store Connect](https://appstoreconnect.apple.com) › Apps › **+ › Nieuwe app** (niet "Nieuwe appbundel"): vink de platforms aan (iOS en eventueel macOS),
   kies een unieke naam, primaire taal Nederlands, jouw `APP_BUNDLE_ID` als bundle-id (staat hij niet in de lijst, bouw dan eerst één keer vanuit Xcode met je team,
   dan registreert Xcode hem) en een eigen SKU. iOS en macOS delen één app zolang ze hetzelfde bundle-id hebben; een platform voeg je later toe via het linkermenu.
3. App Store Connect › Gebruikers en toegang › Integraties › App Store Connect API › **Teamsleutels**: genereer een sleutel met rol **Beheerder**
   (nodig voor cloud-ondertekening). Download het `.p8`-bestand (kan maar één keer) en noteer *Key ID* en *Issuer ID*.
4. [CloudKit-dashboard](https://icloud.developer.apple.com) › jouw container `iCloud.<bundle-id>` › **Deploy schema changes** naar *Production*.
   Zonder dit synchroniseren TestFlight-builds niet via iCloud (die gebruiken de Production-omgeving).

**Eenmalig in GitHub** (repo › Settings › Secrets and variables › Actions)
- Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (de volledige inhoud van het `.p8`-bestand, inclusief de BEGIN/END-regels).
- Variables: `APPLE_TEAM_ID`, `APP_BUNDLE_ID`, en optioneel `GOOGLE_CLIENT_ID` (voor het Gmail-paneel).

**Uploaden**: Actions › *TestFlight* › Run workflow › kies platform en versienummer. Het buildnummer loopt vanzelf op.
Na een paar minuten verwerkt Apple de build; daarna staat hij in App Store Connect › TestFlight.

**Testers**
- *Intern* (tot 100 mensen met een rol in je App Store Connect-team): direct beschikbaar, geen controle door Apple.
- *Extern* (iedereen, via e-mail of openbare link): de eerste build gaat langs Beta App Review. Je moet een beschrijving, een feedback-e-mailadres
  en meestal een privacybeleid-URL invullen.
- Testers installeren de app TestFlight (iPhone, iPad en Mac) en accepteren de uitnodiging.

**Let op voor anderen**
- Elke tester heeft eigen gegevens in zijn eigen iCloud; er wordt niets met jou gedeeld.
- Gmail-paneel: de OAuth-client in je Google Cloud-project werkt voor maximaal 100 gebruikers en toont bij het eerste inloggen "app niet geverifieerd".
  Staat het project nog op *Testen*, dan moet je elke tester als testgebruiker toevoegen.
- Het logo zoeken via Google vraagt een eigen API-sleutel (Voorkeuren › Overig); zonder sleutel wordt het favicon gebruikt.
- De Mac-app in TestFlight vraagt een Mac App Store-ondertekening; cloud-ondertekening met de Beheerder-sleutel regelt dat zelf.
