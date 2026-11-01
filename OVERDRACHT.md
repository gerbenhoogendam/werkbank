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
- Logica-tests: `cd WerkbankCore && swift test` (120 tests).
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
    Sinds de klantenlijst in de app: de lijst staat in de database (`Client`, via iCloud ook op de iPhone) en wordt
    beheerd in Voorkeuren › Overig › Klanten (`ClientsEditor`): zoeken, toevoegen, naam en domein aanpassen,
    verwijderen, een .csv importeren. Bij het inlezen (`ClientList.parseCSV`) blijft van e-mailadressen alleen het
    eigen domein over (kolom "E mail" e.d., anders de kolom met de meeste @), freemail en providers vallen weg,
    dubbele namen worden één klant, en failliet/falliet staat ook midden of achteraan de naam. Bestaande .csv's in
    iCloud Drive/Werkbank en het vroeger aangewezen bestand worden één keer overgenomen. De Mac haalt van alle
    klanten vooraf het logo op (`LogoService.prefetch`, website of favicon, niet de zoekdienst met dagquotum).
    `*.csv` staat in `.gitignore`. Voor TestFlight moet het CloudKit-schema (nieuw type `Client`) naar Production.
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
15. **Archiveren na versturen** (`macOS/SendFollowUp.swift`). Na een antwoord of doorgestuurde mail telt de pil 4 s af
    (balk naar een archiefdoosje); Enter in die tijd archiveert het gesprek en sluit het mailpaneel. Alleen met een
    testmailbox te testen. Na te gaan: vangt Enter ook als de cursor nog ergens in een tekstveld staat, en doet Enter
    na de 4 s weer gewoon wat het moet doen.
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
18. **Afspraken verslepen** (`macOS/EventDrag.swift`, `WerkbankCore/…/EventDragMath.swift`, `DayColumn`). In de week-
    en dagagenda: het blok optillen en naar een andere tijd of dag slepen (per kwartier, de duur blijft gelijk), de
    boven- of onderrand voor begin of eind, of naar de kop (agendafilters en de rij met de dagen); daar klapt
    "Verplaatsen naar" open met de schrijfbare agenda's die in Voorkeuren aan staan. Loslaten buiten de tijdlijn laat alles staan. Herhalende
    afspraken vragen "alleen deze / ook volgende"; losse afspraken kunnen terug met ⌘Z. Niet in de maandagenda en
    niet voor afspraken van een hele dag. Alleen testen in een testagenda. Na te gaan: optillen en schaduw, scrollen
    bij de rand, grepen bij korte afspraken, uitnodigingen van anderen (EventKit kan weigeren), Exchange/Google-sync.
19. **Thema's** (`Shared/Design/Theme.swift`, `Shared/Views/ThemePreferences.swift`). Voorkeuren › Thema: Standaard
    (de oude kleuren), Wandklok, Tischsuper, Principes, Sneeuwwitje, Rekenmachine, Drukproef, Spark, Karmijn, Telemetrie en
    Viertakt. Elk onderdeel
    heeft een rol (venster, mail, kop van mail, bord, kolom, kaart, agenda, tijdlijst, tekst, accent, …) met een kleur
    voor licht en donker; per thema kun je elke rol zelf kiezen en terugzetten. Lettertype, cijferletter en
    basisgrootte (11–17) gelden overal waar `Font.werk`/`thingsFont` staat. Tischsuper tekent het mailpaneel altijd
    donker, Spark de kop van het mailpaneel; Karmijn tekent de agenda altijd donker (`darkAgenda`: zwart in licht,
    warm donkerbruin in donker; de achtergrond volgt de rol Agenda, tekst en lijnen de donkere weergave). De schetsen staan in de Claude-canvas "Werkbank thema's". De vorm per
    thema (`ThemeLook`, `ThemeParts.swift`, `AgendaTheme.swift`, `MailTheme.swift`, `CardSurface`, `ColumnSurface`,
    `TimeTotalFooter`, `PillTheme`): kolomkoppen en -vlakken, kaarten en "loopt", agendakop, filters, dagkoppen,
    uurliniaal, afspraken, lijn van nu, mailkop/tabs/rijen, totaal in Tijd schrijven, timerpil, losse vlakken bij
    Drukproef. Michroma, Anton, Playfair Display en DSEG7 (SIL OFL, `Shared/Fonts`) worden bij het starten geregistreerd;
    Karmijn gebruikt Anton voor koppen en cijfers (`Font.werkDisplay`, `displayTight`) en Playfair voor accenten
    (`Font.werkSerif`). Standaard ziet er uit als
    voorheen. Afspraken houden de kleuren van je agenda's. Na te gaan: of het donkere mailpaneel in de lichte weergave
    goed leesbaar is, lettertypes met gewichten (Avenir Next), contrast van accentknoppen met witte tekst in donker,
    smalle kolommen met de grotere titels (Drukproef, Karmijn), meldingen en inspreken in de pil (nog donker in elk
    thema), of de meegeleverde letters op beide platformen echt laden (anders valt het terug op de systeemletter).
    Verfijning per thema (canvas, borden 1–7 met hun lijst "Verfijningen"; onderdelen in `ThemeParts.swift` en
    `AgendaTheme.swift`): Wandklok `ClockFace`, `DateWindow`, `DashLabel`, minutenring en gouden seconden; Tischsuper
    `PianoKey`, `SuperscriptTitle`, `labelValue`, `counter`, `AgendaNeedle` en teak links en rechts; Principes
    `RuledHeading`, `PosterGrille`, `MiniToggle`, regels van 2 pt; Sneeuwwitje `DialKnob`, `TuningScaleCell`, `TuningBar`,
    `LidSheen`, houten uiteinden; Rekenmachine `LCDDigits` (DSEG7, met zwakke 8-en eronder) en `CalcKey`; Drukproef
    `Waveform`, koppen in drie kleuren (`DutchNumber`) en grote telcijfers; Spark Week/Dag-tabjes, persoon/bel
    (`MailLook.isNotification`), kopregel boven de lijst en de lege envelop.
    Telemetrie en Viertakt (naar twee screenshots van de eigenaar, geen schets in de canvas): Telemetrie is een
    besturingsscherm met losse panelen met een afgesneden hoek (`ChamferedRect`, `themePanel`), zoekerhoekjes
    (`CornerBrackets`), blokjesbalken (`SegmentBar`), het ruitje (`HUDDiamond`) en smalle kapitalen (`HUDLabel`, Barlow
    Semi Condensed voor tekst en Barlow Condensed voor koppen en cijfers, SIL OFL); Viertakt is een technische
    tekening met een rood streepje boven de koppen, grote vette rode cijfers, de toerenteller (`RevGauge`), zwarte en
    rode knopjes (`EngineChip`), rondjes van de ontstekingsvolgorde voor de dagnummers (`FiringDot`), legendastreepjes
    bij agenda's en afspraken (`EngineLabel`), in Helvetica Neue. Na te gaan: of Barlow met de gewichten echt laadt,
    leesbaarheid van de smalle letter in de maillijst, de afgesneden hoeken bij smalle panelen.
20. **Logo's in de maillijst** (`MailSenderIcon` in `MailTheme.swift`, Voorkeuren › Weergave › Mail › "Logo's bij
    afzenders", standaard aan, in elk thema). Het logo komt via `SenderLogoService` van de website achter het domein
    van de afzender; freemail en sites zonder bruikbaar icoon tonen de initialen in de vorm van het thema.
21. **iOS eenvoudiger** (`iOS/RootView.swift`, `iOS/TimeEntrySheet.swift`, `iOS/PhoneDictation.swift`,
    `iOS/WerkbankApp.swift`). Geen agenda en geen inplannen meer op iOS (ook niet in Voorkeuren); twee tabs. Kaarten
    zijn op iOS één regel (`CardView.compactCard`). De Magic Plus opent `TimeEntrySheet` met eerst de keuze
    Inspreken/Typen; de snelle acties op het beginscherm "Tijd inspreken" en "Tijd typen" (`UIApplicationShortcutItems`,
    `QuickAction`, `AppState.timeEntry`) kiezen al. Inspreken zet zo nodig inspreken aan en wacht op de download; de
    microfoon neemt één keer op en knipt per veld (`SpeechRecorder.takeSegment`); elk stuk gaat los door Whisper
    (`DictationParser.field`, klant gekoppeld aan de klantenlijst) terwijl je het volgende inspreekt; daarna
    `SupportEntryView` ingevuld. Model: hetzelfde als op de Mac als het toestel het aankan (A16+), anders small/base
    (`PhoneDictation.variant`). Het model laadt bij gebruik en gaat bij de achtergrond uit het geheugen. Gedeeld met de
    Mac: `Shared/Services/Speech.swift` (`WhisperModel`, `SpeechRecorder`). Nieuwe kaart: plus in de kolomkop.
    Later: kolommen onder elkaar in één `List` (secties, inklappen per apparaat in `board.collapsedColumns`); ruime
    velden (`entryField()`); tijdens inspreken staat in het actieve veld een golfvorm (`VoiceWave`) met een gloeiende
    Siri-rand (`VoiceGlow`, `Shared/Design/VoiceVisuals.swift`). Opnieuw gedaan met de skills in `.claude/skills`
    (find-animation-opportunities, animate): het stemniveau loopt via een veer (`VoiceMotion`, `ThingsMotion.alive`),
    stroming en gloed volgen je stem, tekst verschijnt uit een lichte waas (`ThingsMotion.materialize`), knoppen geven
    mee (`PressScaleButtonStyle`); alle waarden staan in `ThingsMotion`, met verminderde beweging.
22. **Bewegende GIF's één keer** (`WerkbankCore/…/GIFLoop.swift`, `macOS/MailImageLoader.swift`). In de weergave
    van mails (ook de eigen handtekening) verdwijnt de herhaalinstructie (NETSCAPE2.0) uit elke GIF; WebKit speelt hem
    dan één keer en blijft op het laatste beeld staan. Ingesloten GIF's (data-URL's) worden in `MailWebView.document`
    aangepast; afbeeldingen van het web lopen via het schema `werkbank-img:` en `URLSession`. Niet aangepast: GIF's in
    `srcset` of als CSS-achtergrond.
23. **Afzender naar Contacten** (`macOS/ContactCapture.swift`, `WerkbankCore/…/ContactCard.swift`). Naast de
    Claude-cirkel onder de maillijst staat tijdens het slepen een tweede (`ContactDropTarget`). Loslaten opent het
    paneel `.contact`: naam en adres uit het van-veld, de rest haalt Claude (gekozen model, lage inspanning, vast
    JSON-formaat) uit de eigen tekst van de mail zonder citaat; velden met een vonkje komen uit de handtekening.
    Bewaren maakt een contact, of vult een bestaand contact met hetzelfde e-mailadres aan (alleen lege velden en nieuwe
    nummers, website en adres). Recht `personal-information.addressbook` en `NSContactsUsageDescription`.

24. **Themakeuze in de werkbalk, witte mail, klikbare links.** Rechtsboven staat een palet-menu met alle thema's
    (`MainView`). Een mail (`ThreadMailCard`) en het opstelvenster (`ComposeView`) zijn in de lichte weergave altijd wit
    (`ThingsColor.mailPaper`). Losse webadressen in de tekst van een mail worden links (`MailLinks` in WerkbankCore,
    zowel in platte tekst als in HTML, niet in tags, bestaande links, stijlen of scripts), zoals Spark.

## Mailmodus (gebouwd 31 okt, nog niet in de app gezien)

Dubbelklik op de titel van het Mail-paneel (of rechtermuisknop op een mail › Openen in mailmodus) maakt van het hele
venster een mailclient; Esc, de knop Werkbank of dubbelklik op de titel gaat terug. Dubbelklik op een mail in het
paneel opent nog steeds het gesprek in het paneel (zoals eerder). Uitgangspunt van de eigenaar: een verwerkte,
beantwoorde of tot taak gemaakte mail wordt gearchiveerd; mappen doen er niet toe. Klikbaar concept: Claude-canvas
"Werkbank mailmodus".

- **Schil** (`macOS/MailMode/MailModeView.swift`, `MailModeStore.swift`): lijst links met zoeken in de Gmail-zoektaal
  en filters (met bijlage, ongelezen, zonder taak, wacht op antwoord), de bundel nieuwsbrieven en meldingen, de mail in
  het midden (`MailWindowView` met `embedded`), klanten rechts op volgorde van mail in dertig dagen
  (`MailActivityStore`, `ClientActivity` in WerkbankCore). Tab wisselt mailbox › combinatie › alle mail.
- **Toetsen** (`MailModeKeys.swift`): E archiveren, T taak, S tijd schrijven, P inplannen, R beantwoorden, F opvolgen,
  C concept, Tab bereik, / zoeken, J/K volgende/vorige. Aan te passen in Voorkeuren › Mail; gaan mee naar je andere
  Macs. Versturen vanuit de mailmodus archiveert meteen en opent de volgende mail.
- **Bladen** (`MailModeSheets.swift`): taak, tijd schrijven, inplannen (datums uit de mail via `DateProposals`, vrije
  momenten via `FreeSlots`, de week met overlap; uitnodiging als .ics-bijlage in een antwoord dat je zelf verstuurt),
  opvolgen (`FollowUps.swift`: terug als er geen antwoord kwam, eventueel met een kaart in Wacht op klant, of later
  terug; controle elke vijf minuten), Claude-concept (`MailConcept.swift`), nieuwsbrieven en meldingen in één keer
  archiveren (uitsluiten per afzender, domein of soort; `MailBulk` in WerkbankCore; uitgesloten mail staat in de lijst).
- **Opstellen** (`AddressField.swift`, `AddressBook.swift`, `AddressSuggestions` in WerkbankCore): adressen aanvullen
  uit wie je mailde, Contacten en de klantenlijst; menu Opvolgen naast Verstuur.
- **Mappen** (`MailModeFolders` in `MailModeView.swift`, `MailFolders.swift` in WerkbankCore): kolom links (aan/uit in
  de werkbalk) met Postvak IN, Met ster, Verstuurd, Alle mail, Spam, Prullenbak en per mailbox de eigen labels.
  Zoeken in Postvak IN zoekt in alle mail, in een andere map in die map. Archiveren buiten de inbox laat de mail in de
  lijst staan en gaat naar de volgende. Concepten staan er bewust niet in (de gespreksweergave toont geen concepten).
- **Standaard mailprogramma** (`macOS/DefaultMailApp.swift`, `MailtoLink` in WerkbankCore): het mailto-schema staat in
  `project.yml`; een link opent het hoofdvenster met een ingevulde nieuwe mail (Apple Event `kAEGetURL` in
  `AppDelegate`). Voorkeuren › Mail toont welk programma mailto opent, met een knop om Werkbank te kiezen.
- Niet gebouwd (bewust): automatische tijdregistratie tijdens mailen, contextpaneel naast de mail, teller en dag
  afsluiten.

Te testen (alleen met een testmailbox en testagenda, of met toestemming; vrijwel elke handeling archiveert):
openen en sluiten; elk thema (de mail zelf wit); Tab door de bereiken; zoeken en filters; klik op een klant; elke toets
en het aanpassen ervan; taak met en zonder archiveren; tijd schrijven; inplannen met en zonder uitnodiging (komt de
.ics bij de ontvanger als uitnodiging binnen, verschijnt de afspraak in je agenda); vrije momenten in een antwoord;
opvolgen (komt het gesprek terug, verdwijnt het bij een antwoord); concept (stijl, gebruikte context, korter en
uitgebreider); bulk met uitvinken, uitsluiten en ⌘Z; aanvullen in Aan/Cc/Bcc (vraagt macOS om Contacten); opvolgen
bij versturen; elke map en een label met submappen; Werkbank als standaard instellen en een mailto-link klikken, ook
als Werkbank nog niet draait.

Bekende beperkingen: de afspraak in je eigen agenda en de uitnodiging zijn niet gekoppeld (EventKit kan geen
genodigden toevoegen), dus een acceptatie van de ontvanger werkt je afspraak niet bij. "Met bijlage" in de lijst is een
schatting op `multipart/mixed`. Klantenranglijst en aanvullen kijken de eerste keer een maand terug (hooguit 400 mails
per mailbox) en groeien daarna aan.

## Verbeteringen inspreken (gebouwd 31 okt, nog niet in de app gezien)

Verbeteringen voor een volgende build verzamelen en als één prompt aan Claude geven.
- **Mac**: F18 ingedrukt houden (aan te passen in Voorkeuren › Verbeteringen of › Overig), inspreken, loslaten. Het
  lokale Whisper-model van Inspreken (WhisperKit) zet het om; de pil toont een lampje. Meerdere verbeteringen in één
  keer worden gesplitst (`FeatureRequestSplitter` in WerkbankCore: zinnen met "daarnaast", "ook", "ten tweede",
  "punt twee", "1." … beginnen een nieuwe). Meteen bewaard, ⌘Z haalt ze weg (`macOS/Dictation.swift`, `Purpose`).
- **iPhone**: knop Verbetering linksonder (`iOS/FeedbackDictation.swift`): neemt meteen op, toont de herkende
  verbeteringen om na te lopen (tekst, desktop/mobiel, weg) en bewaart ze.
- **Opslag**: SwiftData-model `FeatureRequest` (`Shared/Models/FeatureRequest.swift`), via iCloud gesynchroniseerd.
  Desktop of mobiel: wat de tekst zegt (iPhone, iOS, Mac …), anders het apparaat waarop je het insprak.
- **Voorkeuren › Verbeteringen** (`Shared/Views/FeatureRequestsView.swift`, Mac en iPhone): verzameld (aanpassen,
  toevoegen, weg), de prompt (desktop en mobiel apart, `FeaturePrompt`) kopiëren, markeren als doorgegeven, en
  terugzetten uit Doorgegeven.
- **Screenshot bij elke invoer** (`macOS/FeedbackScreenshot.swift`, `iOS/FeedbackScreenshot.swift`): Mac het
  hoofdvenster via ScreenCaptureKit op het moment van F18 of typen (toestemming voor schermopname; zonder: wat het
  venster zelf tekent, mails blijven dan leeg); iPhone het scherm op het moment van de knop. Opgeslagen in
  `FeatureRequest.screenshot` (externalStorage, via iCloud) met `capturedAt`.
- **Knop Verbetering** in de werkbalk (lampje, `Dictation.toggleFeedbackMode`): zet de aanwijsmodus aan zoals F18 kort
  tikken. Staat inspreken uit, dan gaat het aan en downloadt het spraakmodel; opnemen begint meteen, omzetten wacht tot
  het model klaar is (`modelPhase` naast `phase`). Microfoon en schermopname worden zo nodig gevraagd; de laag toont
  de stand van het model en een knop Schermopname toestaan. Op de iPhone zet de knop Verbetering inspreken zelf aan.
- **Aanwijsmodus** (`macOS/FeedbackOverlay.swift`): tijdens het inspreken ligt over het hoofdvenster een laag met de
  Siri-rand (`VoiceGlow`, nu in `Shared/Design/VoiceVisuals.swift`). Klik = genummerde stip, slepen = kader; de app
  eronder reageert niet. F18 kort tikken: aan tot de volgende tik, Klaar of ⏎; vasthouden: loslaten rondt af. Esc of
  Annuleren gooit weg, ⌘Z haalt de laatste markering weg. Whisper geeft woordtijden (`transcribeWords`); [n] komt achter
  het woord dat je zei toen je klikte (`FeedbackTranscript` in WerkbankCore). Markeringen in `marksData`.
- **PDF voor Claude** (`Shared/Services/FeatureExport.swift`): eerst de prompt (D1, M1 … met datum, tijd, apparaat
  en aangewezen plekken), dan per verbetering een pagina met de screenshot, de markeringen en uitsneden rond elke klik
  of elk kader. Mac: iCloud Drive › Werkbank/Verbeteringen; iPhone: delen.
- Nieuw model en nieuwe velden: het CloudKit-schema moet naar Production voordat een TestFlight-build het
  synchroniseert.

## Panelen in de breedte (D1, 31 okt)

- De panelen die midden over het board openen (mail, opstellen, Claude; `PanelOverlay` in `macOS/PanelHost.swift`)
  zijn in de breedte te verslepen: één paneel aan zijn randen (breder of smaller aan beide kanten,
  `panels.singleWidth`, standaard 60%), twee panelen aan de lijn ertussen (`panels.split`). Dubbelklik zet terug.
- `SplitDivider` (`macOS/MainView.swift`) heeft een greepje in het midden, ook in thema's met losse vlakken waar de lijn
  zelf onzichtbaar is. Het Mail-paneel links mag tot 720 pt breed (was 480).

## Klanten en zoeken in de mailmodus (D2 en ⌘F, 1 nov)

- **Klanten rechts** (`MailModeStore.refreshRanking`, `MailActivityStore`, `ClientActivity` in WerkbankCore): drie
  maanden, 13 weekstaafjes. Alleen mail uit de gekozen mailboxen (`MailClientSettings`, Voorkeuren › Mail; zolang er
  niets gekozen is: de mailboxen met de naam GH, Support en Info, anders alle). Adressen op een eigen domein (de
  domeinen van je mailboxen, behalve gmail.com en dergelijke) tellen niet: het eigen bedrijf is geen klant.
  Rechtermuisknop "Geen klant" zet een klant weg (terug in Voorkeuren › Mail). De mailactiviteit staat per mailbox in
  Application Support/Werkbank/MailActivity.json, gaat 92 dagen terug en wordt hooguit één keer per dag bijgewerkt
  (`syncIfStale`); een oud bestand zonder mailbox per mail wordt één keer opnieuw opgehaald.
- **Uitgebreid zoeken** (⌘F of het schuifjes-icoon naast het zoekveld; `MailSearchSheet`, `MailSearchForm` in
  WerkbankCore): woorden, zonder woorden, van, aan/cc (namen of adressen, komma's), onderwerp, bijlage en
  bestandsnaam, ongelezen, ster, ook spam en prullenbak, periode en mailboxen (kleine vinkjes, standaard gh@,
  support@ en info@: `MailClientSettings.preferred`). De resultaten staan onderaan in het venster
  (`searchPreview`, verandert de lijst niet): vinkjes, periode en mailboxen zoeken meteen opnieuw, tekstvelden bij
  Enter. Een klik op een resultaat zet de zoekopdracht in de lijst en opent die mail; "Toon in de lijst" doet hetzelfde
  zonder mail te kiezen. Een eigen keuze van mailboxen staat als knopje onder het zoekveld.
- **Kolommen van de mailmodus** (mappen, lijst, klanten) zijn in de breedte te verslepen aan de lijn ertussen
  (`ColumnResizer` in `MailModeView.swift`, bewaard in `mailMode.foldersWidth`/`listWidth`/`clientsWidth`); dubbelklik
  zet terug. De mail in het midden neemt de rest (minstens 320 pt).
- `MailboxTab(fitsContent:)`: in de werkbalk van de mailmodus zo breed als de naam met ruimte ernaast (Calculator,
  Wandklok, Sneeuwwitje en Tischsuper deelden anders de breedte en kwamen tegen de tekst aan).
- Bladen in de stijl van het concept: titel met grijze toelichting, gegroepeerde lijsten (`SheetList`), Annuleren als
  tekst en de handeling als donkere knop (`SheetButtonStyle`).

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
- iPhone-inspreken is niet op een toestel uitgevoerd: geheugen van het grote model (geen
  `increased-memory-limit`-recht), hoe lang het eerste laden duurt, de drempel voor stilte (`SpeechRecorder.hasSpeech`)
  en of de snelle actie bij een koude start het blad opent.
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
| Mailmodus | `macOS/MailMode/` (schil, toetsen, bladen, opvolgen, concept, aanvullen), `WerkbankCore/…/MailMode.swift`, `DateProposals.swift`, `AddressSuggestions.swift`, `MailBulk.swift` |
| Claude | `macOS/ClaudeAnalysis.swift` (aanvraag, streaming), `macOS/MailReview.swift`, `macOS/DayClose.swift` |
| Ongedaan maken | `Shared/Services/UndoCenter.swift` |
| Logica met tests | `WerkbankCore/` |

## Valkuilen

- Swift 5-modus; nieuwe UI-code is `@MainActor`.
- `ThemeStore` is bewust niet `@MainActor`: `ThingsColor` en `Font.werk` worden ook buiten views gelezen. Het is
  `@Observable`, dus views die een kleur lezen tekenen opnieuw bij een themawissel; AppKit-delen (opstelveld,
  vouwanimatie) niet.
- Een `PreferenceKey` met `reduce { value = nextValue() }` krijgt van views zonder eigen waarde `.zero` (de
  standaardwaarde) en verliest zo het echte frame. Frames meten met `reportFrame(in:)` (direct doorgeven) of met een
  woordenboek dat samenvoegt (`DayFrameKey`).
- Geen `try` of `await` rechts van `? :`; dat compileert niet.
- Een `DropDelegate` kan tijdens één sleepactie verouderde waarden vasthouden. Gebruik `onDrop(isTargeted:)` per
  vlak of een referentiemodel. Geneste dropzones: de binnenste wint.
- Een `layerEffect` of Metal-shader kan geen AppKit-inhoud lezen (WKWebView, `ScrollView`, tekstvelden): die worden
  niet of als vervangend plaatje getekend. Een shader per pixel op een heel venster was bovendien te zwaar (haperde).
  Animaties die vloeiend moeten blijven terwijl de app laadt: Core Animation (`CAKeyframeAnimation`), niet SwiftUI.
- Mail laden tijdens een animatie (WKWebView aanmaken) laat die haperen; zie `MailThreadModel.load(notBefore:)`.
- Kolommen hebben vaste sleutels (`inbox`, `todo`, `doing`, `waiting`); de namen zijn aanpasbaar.
- `GmailSession.api(_:query:method:body:account:)` regelt het token per mailbox en één nieuwe poging bij 401.
