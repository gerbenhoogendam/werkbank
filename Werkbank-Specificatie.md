# Claude Code prompt: Werkbank (macOS-app)

Bouw een native macOS-app, **Werkbank**, in Swift en SwiftUI (macOS 14+). De visuele vormgeving staat in een aparte designprompt. Deze prompt beschrijft alle functionaliteit en het gedrag. Waar deze prompt en de designprompt elkaar tegenspreken over gedrag, geldt deze prompt.

## Techniek

- SwiftUI-app met één hoofdvenster en een `MenuBarExtra` (menubalkknop).
- Opslag lokaal met SwiftData (of Core Data): to-do's, tijdregels, geplande agenda-items en instellingen. Alles blijft bewaard na herstart, inclusief een lopende timer.
- Agenda via **EventKit**.
- Globale sneltoets die ook werkt als de app niet op de voorgrond staat (bijv. via het pakket `KeyboardShortcuts` van Sindre Sorhus, of `RegisterEventHotKey` via Carbon).
- Alle UI-teksten in het Nederlands.
- App draait door als het hoofdvenster gesloten is (de menubalkknop blijft actief).

## Indeling hoofdvenster

- **Boven:** een board in kanbanstijl, over de volle breedte (ca. 45% van de hoogte).
- **Onder links (¾ breedte):** agenda.
- **Onder rechts (¼ breedte):** lijst "Tijd schrijven".
- In de titelbalk een knop "Snelle invoer ⌥⌘T".

## 1. Snelle invoer via sneltoets

- Standaard sneltoets **⌥⌘T**, aanpasbaar in Instellingen.
- Opent een zwevend invoerpaneel (Spotlight-achtig, `NSPanel`, boven alle apps, ook als Werkbank op de achtergrond draait). Focus direct in het invoerveld.
- **Enter** voegt de tekst toe als nieuwe kaart **bovenaan de kolom Inbox**. **Esc** of klikken buiten het paneel sluit het.
- `#woord` in de tekst wordt het klantlabel van de kaart en uit de titel verwijderd. Bijvoorbeeld "SSL vernieuwen #Acme" wordt titel "SSL vernieuwen", label "Acme".
- Nieuwe kaarten krijgen een "nieuw"-indicator (blauwe stip) tot ze uit de Inbox zijn gesleept.
- Invoeranimatie: de kaart schuift van boven in met een korte highlight.

## 2. Board

- Vaste kolommen: **Inbox, Te doen, Bezig, Wacht op klant, Klaar**. Iedere kolom toont het aantal kaarten.
- Kaart: titel, optioneel klantlabel, optioneel klantlogo, optioneel afzenderregel (bij mail), en een timerknop.
- **Slepen tussen en binnen kolommen**, met herschikken:
  - Slepen start na ca. 5 px beweging (anders telt het als klik).
  - De kaart komt los, wordt iets groter (±105%), krijgt een diepere schaduw en **kantelt mee met de horizontale snelheid** (max ±14°, veert terug naar 0 als je stilhoudt).
  - De doelkolom licht op. Op de plek waar de kaart landt verschijnt een gestippelde placeholder met de hoogte van de kaart. De andere kaarten schuiven vloeiend opzij.
  - Bij loslaten vliegt de kaart in ca. 200 ms naar de placeholder (licht doorverende curve), met daarna een kleine "pop" (schaal 1,03 → 0,97 → 1).
  - De doelkolom wordt bepaald op x-positie (de dichtstbijzijnde kolom), de index op de verticale middens van de kaarten.
- **Timerknop op een kaart:** start direct een timer voor die to-do (zie §5). Bestaat er al een niet-afgeronde tijdregel voor die kaart, dan wordt die hervat in plaats van een nieuwe aangemaakt.
- Een kaart op de **agenda** slepen plant hem in (zie §4). De kaart blijft daarna gewoon op het board staan.

## 3. Mail (.eml) op het venster slepen

- Een of meer `.eml`-bestanden (of `message/rfc822`) vanuit Mail of Finder op het venster slepen maakt per mail een kaart bovenaan de Inbox.
- Tijdens het slepen van bestanden verschijnt een overlay over het hele venster: "Laat los om de mail aan de Inbox toe te voegen". Andere bestandstypes geven een melding dat alleen .eml wordt ondersteund.
- Parsen:
  - Headers tot de eerste lege regel, met ondersteuning voor doorlopende (gevouwen) headerregels.
  - `Subject` wordt de kaarttitel. Is die leeg: "(geen onderwerp)".
  - `From` levert weergavenaam en e-mailadres. Decodeer RFC 2047 encoded words (`=?UTF-8?B?…?=` en `?Q?`).
  - Afzenderregel op de kaart: "Naam · adres@domein.nl".
- **Klantnaam** bepalen uit het domein van de afzender:
  1. Eerst een koppeltabel domein → klant (beheerbaar in Instellingen; ook automatisch aangevuld als de gebruiker een label handmatig wijzigt).
  2. Anders het registreerbare domein (`studio-noord.nl` → "Studio Noord"; houd rekening met `co.uk`-achtige extensies): het laatste label vóór de extensie, `-`/`_` als spatie, elk woord met hoofdletter.
  3. Bij freemaildomeinen (gmail.com, outlook.com, hotmail.com, live.nl, icloud.com, me.com, yahoo.com, ziggo.nl, kpnmail.nl, hetnet.nl, planet.nl, xs4all.nl) de weergavenaam van de afzender, zonder logo.
- **Logo:** zoek op basis van het domein van de afzender een logo op via Google Afbeeldingen (Google Custom Search JSON API met `searchType=image`, zoekterm "<domein> logo"; API-sleutel en CX in Instellingen). Neem het eerste bruikbare resultaat. Valt dat terug of is er geen sleutel, gebruik dan `https://www.google.com/s2/favicons?domain=<domein>&sz=128`. Cache het logo per domein op schijf. Kan er niets worden geladen, toon dan de eerste letter van de klantnaam in een klein vierkant.
- Label en logo zijn later per kaart aan te passen.

## 4. Agenda

### Toegang

- Bij de eerste keer toont het agendapaneel uitleg met een knop "Toegang tot agenda's geven…". Die roept `EKEventStore.requestFullAccessToEvents` aan (het echte macOS-toestemmingsvenster). Zet `NSCalendarsFullAccessUsageDescription` in Info.plist.
- Geweigerd: toon uitleg en een knop die Systeeminstellingen › Privacy en beveiliging › Agenda's opent (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`).
- Reageer live op wijzigingen via `EKEventStoreChanged`.

### Weergave

- Werkweek (ma–vr), standaard 08:00–18:00. Weergave, werkdagen en uren zijn instelbaar (instelling: Werkweek / Dag).
- Kop: "Week <ISO-weeknummer> · <ma datum> – <vr datum>". Vandaag is gemarkeerd. Een rode lijn toont de huidige tijd.
- Uurhoogte minimaal ca. 46 pt. Past het niet, dan scrolt het agendalichaam verticaal.
- Afspraken in de kleur van hun agenda. Korter dan 1 uur: alleen de titel. Langer: titel + tijd.
- **Agenda's selecteren:** in de kop staat per EventKit-agenda een aanvinkbare knop (kleur + naam). Uitgevinkte agenda's worden verborgen. De keuze wordt bewaard.
- **Klik op een afspraak:** voegt die afspraak toe als tijdregel in "Tijd schrijven" (bron: Agenda, klant: naam van de agenda), met een bevestigingsmelding.

### Inplannen door een to-do op de agenda te slepen

Een kaart van het board naar de agenda slepen doorloopt drie stappen:

1. **Starttijd.** Boven de agenda krimpt de gesleepte kaart (±80%). In de dagkolom onder de cursor verschijnt een gestippeld voorbeeldblok van 1 uur met het label "09:15–10:15". De starttijd volgt de cursor en rondt af op **15 minuten** (naar beneden). Bij de boven- of onderrand scrolt de agenda automatisch mee. Loslaten legt de starttijd vast. De kaart vliegt kleiner wordend in het blok en verdwijnt.
2. **Eindtijd.** Er staat een concept-afspraak van standaard **1 uur** (maximaal tot het einde van de dag), gemarkeerd met een blauwe rand. Aan de onderkant zit een sleepgreep: slepen past de eindtijd aan in stappen van 15 minuten (minimaal 15 minuten na de start). Onder de afspraak staat een labeltje "Eind 10:15 [Volgende]". Loslaten van de greep of klikken op Volgende gaat naar stap 3.
3. **Prefix en bevestigen.** Naast de afspraak verschijnt een popover (rechts van de kolom, of links bij do/vr; boven- of onderaan verankerd zodat hij binnen beeld blijft) met:
   - Datum en tijd ("di 29 sep · 09:15–10:15").
   - Een live voorbeeld van de titel.
   - Een keuze voor wat er na **"GH:"** komt: **de starttijd** (bijv. "8:30", zonder voorloopnul) **of "vdm" of "ndm"**. Standaard staat **vdm** geselecteerd als de start tussen 08:00 en 13:00 ligt, en **ndm** vanaf 13:00. Kies je de tijd, dan komt er geen vdm/ndm bij.
   - Een keuze voor de doelagenda (standaard de agenda "Werk" of de eerste zichtbare, schrijfbare agenda).
   - Knoppen Annuleer en Inplannen.

   De titel wordt **"GH: <prefix> <titel van de to-do>"**, bijvoorbeeld "GH: vdm Offerte nieuwe website De Vries" of "GH: 8:30 Offerte nieuwe website De Vries". Inplannen maakt een echt `EKEvent` aan in de gekozen agenda. **Esc** of Annuleer in stap 2 of 3 verwijdert de concept-afspraak. Een nieuwe sleep tijdens een lopend concept vervangt dat concept.

## 5. Tijd schrijven (timers)

Lijst rechtsonder, nieuwste bovenaan. Iedere tijdregel heeft: titel, klant, bron (To-do / Support / Agenda), status, gemeten tijd, omschrijving, "geschreven"-vinkje, gekoppelde kaart (optioneel), eerste starttijd, laatste starttijd, pauzetijd en aantal onderbrekingen.

### Statussen en knoppen

- **Nog niet gestart:** Start.
- **Loopt:** Pauze, Stop.
- **Pauze:** Hervat, Stop. Het aantal onderbrekingen wordt bijgehouden ("Pauze · 2× onderbroken").
- **Afgerond:** geen knoppen. Toont de te factureren tijd. De omschrijving staat in de tooltip.
- Er loopt maximaal **één timer tegelijk**. Een andere starten zet de lopende op pauze.
- Timers blijven kloppen na slaapstand en herstart (reken met tijdstempels, niet met een tikkende teller).

### Weergave

- De lopende timer staat bovenaan in een compacte, iets geaccentueerde regel: pulserende groene stip, titel met klant eronder, tijd (u:mm:ss), en kleine knoppen voor pauze en stop.
- Overige regels nemen twee regels hoogte: het vinkje, de titel met daaronder "klant · bron", rechts de tijd (u:mm) of de te factureren uren, en de knoppen.
- De kop toont "Nog te factureren: X,XX u" (de som van afgeronde, niet-geschreven regels).
- Een "+"-knop in de kop opent de snelle support-invoer uit de menubalk (§6).

### Stoppen (verplicht)

Stop opent een sheet "Werkzaamheden omschrijven". De timer staat bevroren zolang de sheet open is.

- **Eindtijd controleren**, zodat je ziet of je de timer per ongeluk hebt laten doorlopen:
  - Een tijdveld (uu:mm), standaard "nu", of het pauzemoment als de timer al gepauzeerd was.
  - Een knop om terug te zetten naar die standaard.
  - Een infotekst: "Eerste start 09:12 · laatst gestart 10:40 · daarna 1:07 onafgebroken".
  - Een waarschuwing als de timer langer dan 60 minuten zonder pauze liep en de eindtijd niet is aangepast: "De timer liep 1:07 u zonder pauze. Pas de eindtijd aan als je al met iets anders bezig was."
  - De eindtijd mag alleen liggen tussen de laatste start en de standaard-eindtijd. Daarbuiten wordt het veld rood gemarkeerd met een melding, en wordt de waarde begrensd.
  - Het verschil met de standaard-eindtijd wordt van de gemeten tijd afgetrokken ("28 min afgetrokken van de gemeten tijd"). Verschillen onder 1 minuut tellen niet.
- De sheet toont live "Gewerkt u:mm:ss · te factureren X,XX u".
- **Omschrijving is verplicht** (minimaal 3 tekens). Opslaan zonder omschrijving geeft een foutmelding, een rode rand en een korte schudanimatie.
- **⌘Enter** slaat op, **Esc** annuleert. Na annuleren blijft de regel gepauzeerd.

### Facturatie

- Te factureren tijd = gemeten tijd, **naar boven afgerond** op de ingestelde eenheid: 1, 6 of 15 minuten (standaard 15). Weergave in uren met komma ("0,25 u").
- Het **vinkje "geschreven"** is alleen beschikbaar voor afgeronde regels (anders met tooltip "Stop eerst de timer"). Aangevinkte regels worden doorgestreept en gedimd. Opnieuw klikken zet het vinkje weer uit.
- Maak een export van de afgeronde regels (CSV: datum, klant, titel, omschrijving, minuten, afgeronde uren, bron) als voorbereiding op een latere koppeling met het facturatiesysteem. Houd een protocol `BillingExporter` aan, zodat een echte koppeling later eenvoudig toe te voegen is.

## 6. Menubalkknop

- Een `MenuBarExtra` met een klokicoon. Loopt er een timer, dan staat de verstreken tijd naast het icoon.
- Het paneel bevat:
  - **Lopende timer** (als die er is): titel, tijd, pauze en stop. Stop opent de stopsheet in het hoofdvenster en brengt dat venster naar voren.
  - Een segmentkeuze **"Bestaande to-do" / "Snelle support"**.
  - **Bestaande to-do:** een lijst met alle kaarten die niet in Klaar staan (titel + kolomnaam). Selecteer er één en klik "Start timer". Dat werkt zoals de timerknop op een kaart.
  - **Snelle support:**
    - Veld "Klant" (optioneel; leeg wordt "Geen klant"). Suggereer eerder gebruikte klanten.
    - Veld "Omschrijving" (verplicht, minimaal 3 tekens, anders foutmelding "Vul een omschrijving in.").
    - Duur: een **invoerveld voor een eigen aantal minuten** (alleen cijfers, max. 3), gevolgd door de snelkeuzes **10m, 15m, 30m, 60m**. Er is geen 5-minutenoptie. Een eigen invoer heeft voorrang op de snelkeuzes en wordt gemarkeerd.
    - Knoppen: **Start timer** (maakt een lopende support-regel met de omschrijving als titel) en **"Log X min"** (maakt direct een afgeronde regel met die duur; de omschrijving wordt zowel titel als werkomschrijving).
  - Een voettekst met de sneltoets voor snelle invoer.
- Na een actie sluit het paneel, de velden worden leeggemaakt en er verschijnt een korte bevestiging.

## 7. Meldingen en overige interactie

- Korte toastmeldingen onderin het venster (ca. 2 s), bijvoorbeeld: "Timer gestart: …", "Mail van Acme toegevoegd aan Inbox", "Ingepland: GH: vdm …", "Tijd vastgelegd, klaar om te factureren", "15 min support gelogd".
- **Esc** sluit open panelen en popovers, en annuleert een lopend concept op de agenda.
- Popovers en sheets verschijnen met een korte animatie (schaal of schuiven, ca. 160–240 ms).

## 8. Instellingen

- Sneltoets voor snelle invoer.
- Afronding voor facturatie: 1, 6 of 15 minuten.
- Agendaweergave (Werkweek / Dag), begin- en einduur, standaard doelagenda voor inplannen.
- Koppeltabel domein → klant.
- Google API-sleutel en Search Engine ID voor het zoeken naar logo's.
- Drempel voor de "timer liep lang"-waarschuwing (standaard 60 min).

## Oplevering

- Xcode-project dat direct bouwt, met Info.plist-teksten voor agendatoegang, sandbox-entitlements (agenda's, uitgaand netwerk, door de gebruiker gekozen bestanden lezen).
- Unit tests voor: het parsen van .eml (inclusief encoded words en gevouwen headers), het afleiden van de klantnaam uit het domein, de afronding, het berekenen van de eindtijdcorrectie, het afronden op 15 minuten bij inplannen, de prefixregel (vdm/ndm/tijd) en de GH-titelopbouw.
