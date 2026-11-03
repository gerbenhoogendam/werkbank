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
    Afbeeldingen in de tekst (`macOS/InlineImages.swift`): een afbeelding slepen of plakken (⌘V, ook een
    schermafbeelding op het klembord) zet hem op die plek in de tekst; andere bestanden worden bijlagen. Klik erop voor
    vier hoekjes, sleep aan een hoekje om te schalen (`InlineImageCell`, verhouding blijft, niet breder dan het
    tekstvak). Bij versturen: `<img src="cid:…" width height>` en een inline-deel in multipart/related
    (`ComposedMail.inlineImages`); PNG/JPEG/GIF blijven, de rest wordt PNG; tot 10 MB per afbeelding. Loshalen gaat via
    RTFD (de afbeelding gaat mee, de geschaalde maat niet). Een antwoord dat in de mailmodus bewaard wordt bij wisselen
    van mail, bewaart alleen de tekst.
18. **Afspraken verslepen** (`macOS/EventDrag.swift`, `WerkbankCore/…/EventDragMath.swift`, `DayColumn`). In de week-
    en dagagenda: het blok optillen en naar een andere tijd of dag slepen (per kwartier, de duur blijft gelijk), de
    boven- of onderrand voor begin of eind, of naar de kop (agendafilters en de rij met de dagen); daar klapt
    "Verplaatsen naar" open met de schrijfbare agenda's die in Voorkeuren aan staan. Loslaten buiten de tijdlijn laat alles staan. Herhalende
    afspraken vragen "alleen deze / ook volgende"; losse afspraken kunnen terug met ⌘Z. Niet in de maandagenda en
    niet voor afspraken van een hele dag. Alleen testen in een testagenda. Na te gaan: optillen en schaduw, scrollen
    bij de rand, grepen bij korte afspraken, uitnodigingen van anderen (EventKit kan weigeren), Exchange/Google-sync.
19. **Thema's** (`Shared/Design/Theme.swift`, `Shared/Views/ThemePreferences.swift`). Voorkeuren › Thema: Standaard
    (de oude kleuren), Wandklok, Tischsuper, Principes, Sneeuwwitje, Rekenmachine, Drukproef, Spark, Karmijn, Telemetrie,
    Viertakt en Puls. Elk onderdeel
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
    **Puls** (1 nov, naar screenshots van een fitnessapp; concept in de Claude-canvas "Werkbank thema Puls"): zwart met
    grijze tegels (#1C1C1E, kaarten #2C2C2E; licht #F2F2F7 met witte tegels en #F2F2F7-kaarten), losse vlakken met 10 pt
    tussenruimte en hoek 18. Felle kleuren met één betekenis (`Puls` in `Shared/Design/PulsParts.swift`): groen werk en
    hoofdknop, geel loopt nu, rood nu, vandaag en klanten (de klantenkolom was paars/fuchsia; op verzoek rood),
    blauw mail, cyaan agenda, paars alleen nog in de kolomkleuren van het bord (licht fuchsia), oranje te laat. Per kleur een vlak, tekstinkt (4,5:1), inkt voor grote cijfers (3:1) en een label (licht
    een vol vlak, donker een tint). Cijfers rond (`.system(design: .rounded)` via `werkNumbers`) met de eenheid erachter
    in hoofdletters (`PulsValue`: "5 KAARTEN", "6:15 /8 U", "7 ONGELEZEN"). Gloed: het licht valt op de achtergrond
    (`PulsGlow`); in de agenda staat het op de lijn van nu in de kolom van vandaag (`PulsAgendaGlow`), onder Tijd
    schrijven groen. Onderdelen: `PulsRing` (ring met pijltje), `PulsDayBars` (staven op een stippellijn), kolomkop met
    het aantal in de kleur van de kolom (`Puls.columnHue`), lopende kaart met gele ring en gloed, afspraak die nu bezig is
    vol met zwarte letters en een gloed (voorbij op halve kracht), dagnummer van vandaag op een rode cirkel, mailboxen als
    gesegmenteerde keuze, mailmodus in tegels (`pulsTile`), knoppen als glazen capsules, hoofdknop felgroen met zwarte
    letters (`ThingsColor.onAccent`). Na te gaan: de ronde cijfers, de gloed in de agenda (valt hij over de dagen links
    heen?), leesbaarheid van felgroen en geel in licht, en of tekst op het accent overal zwart is.
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
25. **Alles in Tijd schrijven aanpassen met dubbelklik** (3 nov, `TimeEntryRow`, `BookingDetails`, `OpenGestures` in
    `TimeListView.swift`). Dubbelklik op de klant, de datum, de case of de uren in een regel klapt hem open en zet dat
    veld in bewerkmodus; een klik klapt open of dicht, ook op de uren. Opengeklapt: Klant, Case, Uitgevoerd, Uren en
    Datum, elk met dubbelklik (Return bewaart, Esc annuleert, ⌘Z draait terug). De datum leest `EntryDateText` in
    WerkbankCore ("di 3-11-2026 16:27", "4-11", "4 nov 10:00", "9:30", "gisteren 14:00"); een andere datum schuift
    start en einde even ver mee (`TimerService.move`), zodat de week, de dagafsluiting en de export hem op de nieuwe dag
    tellen. Ook gepauzeerde en niet gestarte regels klappen nu open (zonder Uren). Niet aan te passen: een lopende
    timer (`RunningTimerRow`), het totaal en de staafjes (uitgerekend). Na te gaan: dubbelklik op een veld wint van de
    klik op de hele regel, en een ongeldige datum of uren geven de melding "niet herkend".

## Mailmodus (gebouwd 31 okt, nog niet in de app gezien)

Dubbelklik op de titel van het Mail-paneel (of rechtermuisknop op een mail › Openen in mailmodus) maakt van het hele
venster een mailclient; Esc, de knop Werkbank of dubbelklik op de titel gaat terug. Dubbelklik op een mail in het
paneel opent nog steeds het gesprek in het paneel (zoals eerder). Uitgangspunt van de eigenaar: een verwerkte,
beantwoorde of tot taak gemaakte mail wordt gearchiveerd; mappen doen er niet toe. Klikbaar concept: Claude-canvas
"Werkbank mailmodus".

- **Schil** (`macOS/MailMode/MailModeView.swift`, `MailModeStore.swift`): lijst links met zoeken in de Gmail-zoektaal
  en filters (met bijlage, ongelezen, zonder taak, wacht op antwoord), de bundel nieuwsbrieven en meldingen, de mail in
  het midden (`MailWindowView` met `embedded`), klanten rechts op volgorde van mail in dertig dagen
  (`MailActivityStore`, `ClientActivity` in WerkbankCore). Tab wisselt mailbox › combinatie › alle mail. ⌘-klik op
  een mailbox zet hem erbij of haalt hem eruit (`MailModeStore.toggleInScope`), net als in het Mail-paneel; de
  mailboxen van de combinatie staan dan aan, zonder aparte knop.
- **Toetsen** (`MailModeKeys.swift`): E archiveren, T taak, S tijd schrijven, P inplannen, R beantwoorden, F opvolgen,
  C concept, Tab bereik, / zoeken, J/K volgende/vorige. Aan te passen in Voorkeuren › Mail, ook als combinatie
  (⌃⌥⇧⌘ voor de toets, bijvoorbeeld "⇧⌘R"; ⇧ alleen naast een andere); combinaties die van macOS of de app zijn
  (`MailModeKeys.reserved`) kunnen niet. Een losse toets werkt niet in een tekstveld, een combinatie met ⌘/⌃/⌥ wel.
  De toetsen staan niet meer naast de knoppen (alleen in de tooltip). Per knop in de mail een vinkje in dezelfde lijst
  (`MailModeKeys.hiddenButtonsKey`); uit = geen knop, de sneltoets werkt wel. Gaat mee naar je andere Macs. Versturen
  vanuit de mailmodus archiveert meteen en opent de volgende mail.
- **Concepten** (`MailFolder.drafts`, label DRAFT): een map in de mailmodus. Een concept openen (ook als het het
  nieuwste in Alle mail is) zet het in het antwoordblok: bij een gesprek als antwoord op de nieuwste mail (ontvangers,
  onderwerp en tekst uit het concept, het citaat komt bij versturen weer uit die mail), anders als nieuwe mail vanaf
  de mailbox van het concept (`MailWindowView.openDraft`, `ComposeRef.fromAccount`). Bijlagen gaan mee, afbeeldingen
  in de tekst en opmaak van het concept niet (de tekst komt uit `QuoteSplitter.mainText`).
  Elk opstelblok bewaart zichzelf als Gmail-concept, vier seconden na de laatste wijziging (`ComposeView.saveDraft`,
  `GmailSession.saveDraft`: drafts.create of drafts.update; ook in het Mail-paneel en in losse vensters). Het concept
  hoort bij het id van de `ComposeRef` (`GmailDrafts`), zodat het hetzelfde blijft na wisselen van mail en loshalen.
  Versturen of de prullenbak haalt het concept weg (`deleteDraft`); een ander afzenderadres verhuist het. Een paneel
  sluiten zonder versturen laat het concept staan, zoals in Gmail.
- **Open antwoord**: met tekst of een bijlage in het antwoord archiveren Archiveren, Tijd schrijven, Inplannen,
  Opvolgen en Taak maken het gesprek niet (melding "niet gearchiveerd: je antwoord staat nog open"); versturen
  archiveert daarna wel. Ga je naar een andere mail of sluit je de mailmodus, dan wordt het antwoord per gesprek
  bewaard (`MailModeStore.keptReplies`, alleen in het geheugen, tekst zonder opmaak) en staat het er weer als je
  terugkomt.
- **Meer mails tegelijk** (2 nov): ⌘-klik zet een mail erbij of haalt hem eraf, ⇧-klik kiest alles vanaf de vorige
  klik (`MailModeStore.click`, `markedIDs`; ⌃-klik is op de Mac het contextmenu en doet hier niets). Boven de lijst
  staat dan "N geselecteerd" met Verwijderen (prullenbak, niet in de map Prullenbak), Archiveren, Naar map (de labels
  van de mailboxen van de gekozen mails, op naam; Postvak IN en de open map eraf) en Naar postvak (`moveThreads`, één
  gesprek tegelijk zoals `moveThread`). Alles met één keer ⌘Z terug (`trashBulk`, `relabelBulk`, `moveThreads` in
  `GmailSession`). E archiveert de gekozen mails, Esc heft de selectie op, j/k gaat terug naar één mail; bladen en R
  werken niet zolang er meer gekozen zijn. Het leesvlak toont dan alleen het aantal.
- **Onderste regel van een antwoord vast** (2 nov): in een gesprek (paneel en mailmodus) staat de regel met Bijlage,
  Controleer, Opvolgen en Verstuur vast onder in het venster in plaats van onder de tekst (`ComposeView.pinsFooter`,
  `ComposeFooterKey`, neergezet met `overlayPreferenceValue` in `MailWindowView.conversation`; daaronder blijft zoveel
  ruimte vrij als de regel hoog is). Losse opstelvensters hadden hem al vast.
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
bij versturen; elke map en een label met submappen; meer mails kiezen met ⌘ en ⇧ en elke knop in de balk (met ⌘Z,
ook over twee mailboxen); de onderste regel van een antwoord bij scrollen in een lang gesprek; Werkbank als standaard instellen en een mailto-link klikken, ook
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
- **Slepen uit de mailmodus**: zodra je een mail sleept (uit de lijst of uit een mailvenster) zwiept de mailmodus naar
  beneden weg en staat de werkbank erachter (board, agenda, Tijd schrijven). `MailDragState.begin` start het, één
  runloop later (`MailModeStore.recede`), zodat het niet midden in het opbouwen van de sleepactie gebeurt.
  - Animatie (`MainView.swoop`): klein optillen, dan versnellend omlaag (0,32 s); terug een veer (0,42 s). Een
    schaduw boven de bovenrand van de mail en de werkbank die oplicht (`mailShade`). Alleen verschuiven: schalen,
    kantelen en vervagen werken niet op de webweergave van de mail.
  - De werkbank blijft daarom ook in de mailmodus bestaan, achter de mail (`disabled`, verborgen voor VoiceOver);
    eerst werd hij pas bij het slepen opgebouwd, en dat at de hele animatie op.
  - Esc: een eigen toetsmonitor van `MailModeStore` zolang de mail weg is (elk venster; een blad en de aanwijsmodus
    gaan voor), plus de verborgen Esc-knop in `MainView`. Een half ingepland concept op de agenda vervalt dan.
  - Afgebroken slepen: Esc tijdens het slepen komt niet bij de app aan (macOS breekt het slepen af), dus
    `MailDragState` leest de toets zelf (`CGEventSource.keyState`) en haalt de mail meteen terug. Loslaten zonder dat
    een doel de mail aannam (buiten het venster, op het Gmail-paneel) doet hetzelfde; doelen melden een drop met
    `MailDragState.noteDropped()` (`GmailDrop.handle`, agenda, Claude/contact, andere mailbox). Opgelichte kolom en
    plek op de agenda gaan weg. Neergezet: de werkbank blijft tot Esc.
  - Een gesleepte mail draagt alleen het eigen type (`UTType.gmailMessage`), dus de webweergave vangt niets op.
- **Tischsuper op het board**: de balk achter de kolomkoppen is notenhoutfineer met een oranje rand eronder (was
  oranje), de kolomnamen licht.
- **Tischsuper in de mailmodus**: kop van notenhoutfineer (`Veneer` in `ThemeParts.swift`) met lichte tekst, houten
  zijkanten links en rechts, mailboxen als leesbare knopjes (gekozen oranje) direct naast de titel. De kop van de
  mailmodus volgt nu ook `darkMail` (bij Tischsuper stond donkere tekst op de donkere kop).
- Bladen in de stijl van het concept: titel met grijze toelichting, gegroepeerde lijsten (`SheetList`), Annuleren als
  tekst en de handeling als donkere knop (`SheetButtonStyle`).
- **Klanten in de mailmodus** (alle thema's): de weekstaafjes en de balk naar aantal zijn vervangen door één balkje van
  de afgelopen dertig dagen, oud links en vandaag rechts: gevuld op een dag met mail, leeg bij stilte
  (`ClientActivity.Rank.recentDays`, `PulsMonthStrip`). Het aantal mails over drie maanden staat ernaast.
- **Knoppen Mail en Werkbank**: in de werkbalk van het venster, direct naast de vensterknopjes (eerste item van
  `.navigation` in `MainView`): op de werkbank "Mail ›", in de mailmodus "‹ Werkbank" (`MailModeButtonStyle`). De
  knop Werkbank staat niet meer in de eigen werkbalk van de mailmodus; het knopje voor het Mail-paneel is weg zolang de
  mailmodus open staat (het paneel hoort bij de werkbank).

## Snelheid (nacht van 1 op 2 nov)

- **Mailmodus openen**: een lijst toont meteen wat er de vorige keer stond (`MailListCache`, laatste twaalf lijsten in
  `MailModeLists.json`); zonder bewaarde lijst komt wat binnen is per mailbox erbij. Mailboxen worden tegelijk
  opgehaald (`MailModeStore.fetchAll`), de kopjes per mailbox met steeds acht tegelijk onderweg (glijdend venster in
  `GmailSession.mailItems(ids:)`, binnen wat Gmail per seconde toestaat). Mappen laden tegelijk met de lijst; de
  klanten pas daarna (die halen soms veel op bij dezelfde mailboxen). Elke twee minuten ververst de lijst vanzelf.
- **Bladeren**: na het kiezen van een mail worden de volgende twee alvast opgehaald en klaargezet (`MailPrefetch` in
  `MailThread.swift`); een vooruit opgehaald gesprek wordt één keer en binnen een minuut gebruikt.
- **Starten**: klantactiviteit en bewaarde lijsten worden buiten de hoofdthread ingelezen (`preload()` in
  `applicationDidFinishLaunching`); het Mail-paneel toont de inbox van de vorige keer (`GmailInbox.json`) tot Gmail
  is bijgewerkt. Bewaren gebeurt even later en buiten de hoofdthread.
- Klant per mail en de eigen adressen worden onthouden (werden per mail per weergave opnieuw bepaald).
- Mailboxknoppen: de naam reserveert de vette breedte (kiezen verschuift niets); in Puls zijn ze zo breed als hun
  naam met vaste marge (`SegmentRow` in `MailTheme.swift`).
- Ook tegelijk in plaats van na elkaar: dagafsluiting (`sentMails`), Wacht op klant (`waitingItems`), het
  concept-antwoord (`MailConcept.loadThread`), ⌘Z na bulk-archiveren (`restoreBulk`) en het bijwerken van
  klantcontact per mailbox (`MailActivityStore.sync`).
- Gmail-limiet: een 429 of een 403 met `rateLimitExceeded`/`userRateLimitExceeded` wordt tot drie keer opnieuw
  geprobeerd met oplopende wachttijd (`GmailSession.api`); eerder viel zo'n mail stil uit de lijst.
- Hertekenen: de maillijst rekent lijst, bundel en groepen één keer per weergave uit; het bord verdeelt de kaarten in
  één doorgang over de kolommen; bewaarde analyses per gesprek staan in het geheugen (`ThreadAnalysisStore`); de
  klantenlijst wijst alleen toe als er iets veranderde; de klantenkolom wordt buiten de hoofdthread uitgerekend.
- Logo's: eenmaal ontleed bewaard in `DecodedLogos` (`LogoService.swift`), zodat een rij die terug in beeld komt
  meteen het logo toont.
- Wisselen van mailbox, map of klant en het openen van de mailmodus zetten de bewaarde lijst en de eerste mail
  meteen neer (`MailModeStore.switchList`/`showStoredList`). Mislukt bijwerken helemaal, dan blijft de lijst staan
  met één melding (`reportedFailure`).
- WebKit wordt drie seconden na het starten voorverwarmd met een leeg, verborgen vlak (`WebKitWarmup` in
  `MailWindow.swift`); losgelaten tien seconden nadat een mail een eigen vlak heeft.
- Agenda: de dagkolom leest in zijn GeometryReader alleen de breedte (de plek komt uit een apart achtergrondje), en
  `CalendarService` haalt de periode ervoor en erna alvast op (`prefetchNeighbors`).
- Tijdlijst: de hoofdvraag haalt alleen open regels op; `WrittenTimeEntries` (met eigen `@Query`) alleen als Al
  geschreven open staat, dicht alleen `fetchCount`.
- Kaarten per kolom: `BoardService.grouped` (Mac en iPhone). Mailmodus, klantlogo's, Wacht op klant en het menubalk-
  paneel vragen alleen de kaarten op die ze nodig hebben (niet het archief).
- Inspreken: `VoiceWave`/`VoiceGlow` krijgen het niveau als functie en lezen het pas in hun animatie;
  `DictationLevel` leest het zelf.
- Inplannen (P): de afspraken rond het gekozen moment staan in `window` (één vraag aan EventKit); `CalendarService`
  haalt buurperiodes alleen op met `prefetchNeighbors: true` (week- en maandagenda).
- Dag afsluiten wacht 600 ms na een wijziging in het datumveld; het handtekeningvoorbeeld 300 ms na typen.
- `QuoteSplitter.split` zoekt na de eerste vondst alleen het stuk ervoor (met 4000 tekens marge) en kijkt eerst naar
  `<img`; `SiteIconFinder` haalt de icoonkandidaten tegelijk op (de eerste bruikbare in volgorde wint).
- `PreferencesSync.push` leest het iCloud-bestand niet als geen gedeelde instelling veranderde.
- Bewust niet gedaan (risico zonder te kunnen kijken, of weinig winst): de agenda tekent tijdens het slepen nog alle
  dagkolommen opnieuw (voorvertoning naar eigen kindviews halen); `AgendaEvent` haalt nog deelnemers, notities en
  organisator op voor elke afspraak (ook de dagafsluiting gebruikt die); de opvolgcontrole (elke vijf minuten) haalt
  gesprekken na elkaar op; alle kaarten luisteren naar één gedeelde subtakenlijst; de mailmodus haalt bij verversen
  nog alle koppen opnieuw op (daar veranderen labels wel: archiveren, mappen; de history-API van Gmail zou alleen
  wijzigingen geven).
- Mail-paneel verversen (`GmailSession.reload(key:)`): naast de inboxlijst één lijst van ongelezen inboxmails; alleen
  nieuwe mails krijgen hun kop, bekende houden hun gegevens en krijgen alleen gelezen/ongelezen bij. Lukt de lijst
  van ongelezen niet, dan alles opnieuw zoals eerst.
- Na te gaan op de Mac: of de lijst echt direct staat, of Gmail geen "rate limit" geeft bij vijf mailboxen tegelijk
  (dan `8` in `mailItems(ids:)` verlagen), en of de bewaarde lijst na archiveren niet even de oude mail toont.

## Open punten

- Citaten in de weergave per niveau gekleurd en ingesprongen zoals in Apple Mail (blauw, groen, rood;
  `MailWebView.quoteLevels`, voor `blockquote type="cite"` en `blockquote.gmail_quote`, ook over de grijze streep van de
  afzender heen). Platte tekst met ">" wordt eerst geneste citaatblokken (`QuoteLevels.nestPlainQuotes`). Outlook zet
  een doorgestuurd gesprek niet in citaatblokken maar plat onder elkaar: dat blijft zonder kleur.
- Handtekeningafbeeldingen: een afbeelding telt als "in de tekst" bij cid, Content-Location of bestandsnaam
  (`MailContentParser.imageReferences`/`isReferenced`, `inlineNamedImages` zet hem op zijn plek); een ingesloten
  afbeelding met cid tot 100 KB waar de tekst niet naar verwijst, is geen bijlage (`embeddedImageLimit`). In de
  bijlagen wordt een afbeelding nooit groter getoond dan hij is.
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
