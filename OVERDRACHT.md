# Overdracht

Stand van 24 oktober 2026. Voor een Claude-sessie die op de Mac van de eigenaar draait en de app
zelf kan bouwen, starten en bedienen. Tot nu toe is alles gebouwd vanuit een Linux-container zonder Xcode: alleen CI
controleerde of het compileerde, en de eigenaar testte het gedrag.

## Werken met de eigenaar

- Nederlands, to the point, geen complimenten en geen onterecht gelijk. Zeg hoe het zit, ook als iets niet werkt of
  niet getest is.
- Korte genummerde stappen. Vraag om context als een verzoek onduidelijk is, in plaats van te gokken.
- De app is alleen voor eigen gebruik: zie `CLAUDE.md` (geen helpteksten, labels in `Color.fieldLabel`, meldingen
  via `AppState.announce`).
- Geef aan wat je echt gezien of getest hebt en wat niet.

## Bouwen en testen op de Mac

- Bijwerken, bouwen en starten: `./Scripts/update-and-run.sh` (git pull, XcodeGen, Debug-build in `DerivedData/`,
  oude Werkbank afsluiten, nieuwe openen).
- Alleen bouwen, zonder pull:
  `xcodegen generate --quiet && xcodebuild -project Werkbank.xcodeproj -scheme Werkbank-macOS -configuration Debug -derivedDataPath DerivedData -quiet build`
- Logica-tests: `cd WerkbankCore && swift test` (114 tests).
- Schermafbeelding: `screencapture -x /tmp/werkbank.png`.
- Nieuwe bestanden staan pas in het project na `xcodegen generate` (het script doet dat).
- `Config/Local.xcconfig` (bundle-id, team, Google-client) staat niet in git. Zonder dat bestand werkt Gmail niet.
- CI (GitHub Actions, `.github/workflows/werkbank.yml`) bouwt macOS en iOS en draait de tests bij elke push naar
  `main`. Na een push moet die groen zijn. CI gebruikt dezelfde Xcode als de Mac (`XCODE_VERSION` in de workflow,
  runner `xcode-27`); werk die bij als Xcode op de Mac wordt bijgewerkt.
- Er werkt soms ook een cloudsessie aan dezelfde repo. Commit en push je eigen werk voordat je stopt, en begin met
  `git pull`. Anders faalt het `--ff-only` in het script.

## Testregels (echte gegevens)

De app draait met de echte Gmail-mailboxen, agenda's, kaarten en tijdregels van de eigenaar.

- Niets versturen, archiveren, verplaatsen naar een andere mailbox of naar de prullenbak in echte mailboxen.
- Geen kaarten afvinken, verwijderen of verplaatsen op het echte board. Een testkaart maken mag; ruim die weer op.
- Geen afspraken maken, wijzigen of verplaatsen in echte agenda's.
- Geen tijdregels toevoegen of wijzigen, behalve testregels die je daarna weer verwijdert (⌘Z werkt).
- Claude-aanroepen in de app kosten geld: alleen waar de test het nodig heeft.
- Wijst de eigenaar een testmailbox of testagenda aan, dan mag daar wel alles.
- Twijfel je: eerst vragen.

## Wat getest moet worden

Gemaakt, gecompileerd en door CI gekomen, maar nog niet in de app gezien:

1. **Wacht op klant** (`macOS/WaitingWatcher.swift`). Kaarten uit een Gmail-mail onthouden `mailThreadID` en
   `mailAccount`. Antwoord (⌘R of beantwoorden) in dat gesprek: kaart naar de kolom met sleutel `waiting`, de pil
   zegt "Mail verzonden · kaart naar …". Mailt iemand anders daarna in het gesprek, dan binnen 3 minuten naar `todo`
   met blauwe stip en melding "Antwoord: …". Alleen te testen met een testmailbox of met toestemming.
2. **Dag afsluiten** (`macOS/DayClose.swift`, ⇧⌘E of het Claude-icoon in de kop van Tijd schrijven). Claude krijgt
   afspraken, verzonden mails, afgeronde taken en bestaande tijdregels en stelt regels voor. Controleer: komt het
   venster open, laden de voorstellen, kloppen de bronnen, is alles aanpasbaar, voegt Toevoegen alleen het
   aangevinkte toe, haalt ⌘Z alles weer weg.
3. **Inactiviteit** (`macOS/IdleWatcher.swift`). Timer loopt, 10 minuten of langer geen invoer, of slaapstand: bij
   terugkomst toont de pil "x min weg" met Eraf en Laten. Om te testen kun je `IdleWatcher.threshold` tijdelijk
   verlagen (niet committen).
4. **Verplaatskaart** bij het slepen van een mail naar de tabs (`macOS/MailMoveZone.swift`): oplichten werkt volgens
   de eigenaar. Nog na te gaan: knippert de kaart bij de overgang van de tabs naar een vlak, en werkt hij ook bij
   slepen vanaf de greep van een geopend gesprek.
5. **Versturen** gaat direct (Verstuur, ⌘↩, ⇧⌘D), zonder vraag.
6. **Mailtimer** (`macOS/MailTimer.swift`): knop in de kop van een gesprek en onder een antwoord. Eén regel per
   gesprek (`TimeEntry.mailThreadID`); opnieuw starten telt op, ook na stoppen, tot de regel als geschreven is
   afgevinkt. Klant uit de afzender of van de gekoppelde kaart.
7. **Opstelvenster loshalen** (knop met venstericoon onder het opstelblok): eigen venster met velden, tekst en
   bijlagen; sluit na versturen.
8. **iCloud Drive-map Werkbank** (`Shared/Services/WerkbankFolder.swift`, `macOS/PreferencesSync.swift`). Nieuw
   iCloud Documents-recht: de eerste build moet het profiel bijwerken (`-allowProvisioningUpdates` in het script).
   Controleer: verschijnt iCloud Drive/Werkbank in Finder, komt `Voorkeuren.plist` erin, neemt een tweede Mac de
   voorkeuren over (melding in de pil), kloppen agendakleuren en verborgen agenda's daar (vertaald via
   "account|agenda"). Voorkeuren › Overig › iCloud Drive toont de map en de laatste synchronisatie.
9. **Claude-geheugen** (`macOS/ClaudeMemory.swift`): `Claude-geheugen.md` in de map, veld Geheugen onder elke
   analyse, lijst in Voorkeuren › Claude. Gaat via `ClaudeSettings.context` mee in elke vraag aan Claude.
10. **F16 en klanten uit CSV**: tweede sneltoets (Voorkeuren › Overig), klantveld (`Shared/Views/ClientField.swift`)
    zoekt in alle .csv in de map. Na te gaan: werken pijltjes en Tab in het veld (`onKeyPress` op een TextField),
    lezen de CSV's van Excel goed in (UTF-8 of Windows-codering).
11. **Drie timers tegelijk** (`TimerService.maxRunning`): een vierde pauzeert de langst niet herstarte. Na te gaan:
    stapelt de zwevende pil netjes (paneel groeit naar beneden), tonen Tijd schrijven en de menubalk alle lopende.
12. **Logo's per klant** (`ClientDirectory.logoDomains`, `ClientLogo`): naast het klantveld, in de suggesties en in
    Tijd schrijven; bron is de klantenlijst (kolom Domeinnaam), dan de koppeltabel, dan kaarten.
13. **Klantenlijst**: klanten met FAILLIET, GEEN KLANT MEER of NIET GEBRUIKEN worden overal weggelaten.
14. **Duo-vouw** (`macOS/DuoFold.swift`, `macOS/DuoWindowFold.swift`). Eén vlak kantelt om de onderrand naar
    achteren weg, achter matglas: hoe verder naar achteren, hoe waziger (geen donkerte). Openen gaat van plat naar
    rechtop. Geldt voor het hoofdvenster en losse opstelvensters (openen, ⌘W, sluitknop, ⌘Q), mail- en opstelpanelen
    (openen, sluiten, versturen). Vensters en sluitende panelen vouwen als afbeelding in Core Animation (loopt door
    als de app bezig is) met twee vooraf berekende waaslagen; een paneel dat opengaat kantelt zelf, met een matte
    sluier in plaats van waas. Het gesprek komt pas in beeld als de vouw klaar is. Duur per onderdeel in Voorkeuren ›
    Weergave › Animaties. Na te gaan: vloeiend (eerst haperde het); verschijnt het hoofdvenster na het openen altijd
    (het staat ±0,3 s achter de bureaubladachtergrond); geen flits, gat of sprong bij de overgang naar de afbeelding;
    klopt de plek van de afbeelding van een paneel (ook met het Gmail-paneel open en met twee panelen). Lukt de
    afbeelding (`CGWindowListCreateImage`) niet, dan sluit een paneel met zijn eigen kanteling en een venster zonder
    vouw. Een met ⌘W gesloten hoofdvenster hergebruikt macOS bij Dock-klik of menubalk; dat wordt gevolgd
    (`watchForReappearance`) en vouwt dan ook open. Na te gaan: geen flits van het venster vóór de vouw.
15. **Archiveren na versturen** (`macOS/SendFollowUp.swift`). Na een antwoord of doorgestuurde mail telt de pil 2 s af
    (balk naar een archiefdoosje); Enter in die tijd archiveert het gesprek en sluit het mailpaneel. Alleen met een
    testmailbox te testen. Na te gaan: vangt Enter ook als de cursor nog ergens in een tekstveld staat, en doet Enter
    na de 2 s weer gewoon wat het moet doen.
16. **Inspreken** (`macOS/Dictation.swift`, `WerkbankCore/…/DictationParser.swift`). Voorkeuren › Overig › Inspreken
    aanzetten (uit: F17 meldt dat in de pil); de eerste keer downloadt WhisperKit het model (± 630 MB, naar Application
    Support/Whisper) en stemt Core ML het af (± 25 s, opnieuw na elke macOS-update). F17 ingedrukt houden en spreken:
    "klant …, case …, uitgevoerd …, kwartier". Loslaten: omzetten (Nederlands), verdelen op trefwoorden of anders door
    Claude, klant koppelen aan de klantenlijst, snelle invoer ingevuld openen. Ongewijzigd opgeslagen velden krijgen in
    Tijd schrijven een oranje microfoon (`TimeEntry.dictatedRaw`), die verdwijnt als je het veld zelf aanpast. Na te
    gaan: toestemmingsvraag microfoon, downloadvoortgang in Voorkeuren, snelheid na loslaten, kwaliteit van Nederlands
    en klantnamen, werkt het offline na de eerste keer, geheugengebruik met het model geladen.
17. **Opmaak in mails** (`macOS/RichText.swift`, `macOS/ReplyTextView.swift`). Werkbalk onder het onderwerp: vet,
    cursief, onderstreept, doorgehaald (⌘B, ⌘I, ⌘U), lettertype, grootte, tekstkleur, markeren, opsomming, nummering,
    inspringen, link (⌘K), opmaak wissen. Standaard Helvetica 13, net als de verstuurde mail. Bij versturen wordt het
    eenvoudige HTML (`RichHTML`, `ComposedMail.bodyHTML`); de tekstversie blijft. Het lege tekstvak is twee regels hoog,
    de handtekening staat er direct onder. Na te gaan: hoe het eruitziet bij de ontvanger (Gmail, Outlook, Apple Mail),
    lijsten met Return en Backspace, ⌘Z na lijst en inspringen, plakken van opgemaakte tekst uit een website, opmaak na
    loshalen van het opstelvenster.

## Open punten

- Apple-citaten ("Op … schreef:") worden niet altijd ingeklapt in een gesprek (`QuoteSplitter` in
  `WerkbankCore/Sources/WerkbankCore/MailThreading.swift`). Een .eml van zo'n mail helpt; klantmails niet committen.
- Standaardfavicons worden herkend op URL, niet op beeld (`SenderAvatar.swift`, `SiteIcons.swift`).
- Wijzigingen aan herhalende afspraken zijn niet met ⌘Z terug te draaien.
- Na verplaatsen naar een andere mailbox staan eigen antwoorden daar niet onder Verzonden.
- Wacht op klant werkt alleen voor kaarten die sinds `dd37b1d` uit Gmail zijn gemaakt.
- De drempel voor inactiviteit staat vast op 10 minuten; eventueel instelbaar maken in Voorkeuren.
- TestFlight: na de nieuwe velden op `TodoCard` en `TimeEntry` (`dictatedRaw`) moet het CloudKit-schema opnieuw
  naar Production.
- WhisperKit (`argmax-oss-swift` 1.1.1) wordt door Argmax nog niet getest met Xcode 27.1 en niet meer op macOS 14.
- Instellingen die per Mac blijven: mailboxen (inloggen), Claude-sleutel (sleutelhanger), sneltoetsen, vensters.
- `DropInfo.location` gaf in `MailMoveZone` geen bruikbare posities; vandaar per vlak een eigen `onDrop`.

## Ideeën die nog openstaan

Klein: afspraak voorbij → tijd schrijven met één klik; regels per afzender (altijd verplaatsen of archiveren); kaart
uit mail met titel, klant en subtaken van Claude. Middel: klantdossier; ⌘K zoeken en doen; opvolgen en later
versturen; timer op het iPhone-vergrendelscherm. Groot: rechtstreeks boeken in het urensysteem (welk systeem is nog
onbekend); plan mijn dag.

## Waar wat zit

| Onderdeel | Bestanden |
|---|---|
| Hoofdvenster, panelen, blur | `macOS/MainView.swift`, `macOS/PanelHost.swift` |
| Duo-vouw (openen en sluiten) | `macOS/DuoFold.swift` (model, duur, paneel openen), `macOS/DuoWindowFold.swift` (afbeeldingen) |
| Board en slepen | `macOS/BoardView.swift`, `macOS/DragCoordinator.swift`, `Shared/Services/BoardService.swift`, `Shared/Views/CardView.swift` |
| Agenda | `macOS/AgendaView.swift`, `macOS/EventDetailView.swift`, `Shared/Services/CalendarService.swift` |
| Tijd schrijven en timer | `Shared/Views/TimeListView.swift`, `Shared/Services/TimerService.swift`, `macOS/MiniTimer.swift`, `macOS/QuickEntry.swift`, `macOS/Dictation.swift` (inspreken) |
| Gmail | `macOS/GmailSession.swift` (API, mailboxen, verplaatsen), `macOS/GmailPanel.swift`, `macOS/MailWindow.swift`, `macOS/MailThread.swift`, `macOS/ComposeView.swift`, `macOS/SendFollowUp.swift` |
| Claude | `macOS/ClaudeAnalysis.swift` (aanvraag, streaming), `macOS/MailReview.swift`, `macOS/DayClose.swift` |
| Ongedaan maken | `Shared/Services/UndoCenter.swift` |
| Logica met tests | `WerkbankCore/` |

## Valkuilen

- Swift 5-modus; nieuwe UI-code is `@MainActor`.
- Geen `try` of `await` rechts van `? :`; dat compileert niet.
- Een `DropDelegate` kan tijdens één sleepactie verouderde waarden vasthouden. Gebruik `onDrop(isTargeted:)` per
  vlak of een referentiemodel. Geneste dropzones: de binnenste wint.
- Een `layerEffect` of Metal-shader kan geen AppKit-inhoud lezen (WKWebView, `ScrollView`, tekstvelden): die worden
  niet of als vervangend plaatje getekend. Een shader per pixel op een heel venster was bovendien te zwaar (haperde).
  Animaties die vloeiend moeten blijven terwijl de app laadt: Core Animation (`CAKeyframeAnimation`), niet SwiftUI.
- Mail laden tijdens een animatie (WKWebView aanmaken) laat die haperen; zie `MailThreadModel.load(notBefore:)`.
- Kolommen hebben vaste sleutels (`inbox`, `todo`, `doing`, `waiting`); de namen zijn aanpasbaar.
- `GmailSession.api(_:query:method:body:account:)` regelt het token per mailbox en één nieuwe poging bij 401.
