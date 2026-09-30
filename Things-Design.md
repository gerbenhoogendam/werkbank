# Things 3 – Ontwerpspecificatie

Referentiedocument met de ontwerpeigenschappen van Things 3 (Cultured Code), bedoeld als basis voor een eigen app in dezelfde geest.

> **Betrouwbaarheid van dit document**
> - **[Bron]** = staat letterlijk of inhoudelijk in een van de bronnen onderaan.
> - **[Waargenomen]** = gangbaar, zichtbaar gedrag van de app, niet expliciet in de bronnen beschreven.
> - **[Benadering]** = maatvoering en kleurwaarden. Cultured Code publiceert géén design tokens, hexcodes of maten. Alle getallen in de hoofdstukken Kleur, Typografie en Maatvoering zijn benaderingen. Controleer ze met een pipet (bijv. macOS *Digital Color Meter*) op de echte app of op de screenshots van Banani voordat je ze vastlegt.

---

## 1. Ontwerpprincipes

| # | Principe | Uitwerking |
|---|----------|-----------|
| 1 | **Papier-metafoor** | Een geopende to-do verandert in een "schoon wit vel papier". Geen omlijsting, geen formulier-uitstraling. [Bron] |
| 2 | **Progressieve onthulling** | Extra velden (tags, checklist, startdatum, deadline) liggen weggestopt in een hoek tot je ze nodig hebt. Een lege to-do toont alleen titel en notitieveld. [Bron] |
| 3 | **Rust boven dichtheid** | Veel witruimte, vlak ontwerp, beperkt kleurenpalet. Kleur is betekenis (lijsttype, deadline, vandaag), geen decoratie. [Bron + Waargenomen] |
| 4 | **Structuur zonder dwang** | De app legt geen methode op (GTD e.d.). Areas, projecten en headings zijn optioneel. [Bron] |
| 5 | **Alles is geanimeerd, met een doel** | Elke actie wordt geanimeerd met een eigen animatietoolkit; animaties houden je positie vast (uitvouwen in plaats van naar een nieuw scherm springen). [Bron] |
| 6 | **Tactiel en snel** | Slepen, vegen, direct invoegen. De app moet net zo snel reageren als je handen bewegen. [Bron] |
| 7 | **Toetsenbord als volwaardige invoer** | Op Mac/iPad is vrijwel alles zonder muis te doen; typen start direct een zoekactie (Type Travel). [Bron] |
| 8 | **Native platformgedrag** | Systeemfont, systeemgebaren, Dark Mode, Dynamic Type, widgets, Shortcuts. De app voelt als een verlengstuk van macOS/iOS. [Bron] |

---

## 2. Informatiearchitectuur

### 2.1 Vaste lijsten (sidebar, bovenaan)

| Lijst | Functie | Icoon | Kleur [Benadering] |
|-------|---------|-------|--------------------|
| **Inbox** | Ongesorteerde invoer, verwerken later | Bak/lade | Blauw `#1A8CFF` |
| **Today** | Wat vandaag gebeurt; agenda-items bovenaan | Ster | Geel `#FFD02B` |
| ↳ **This Evening** | Sectie ónder Today voor taken voor later op de dag | Maan | Donkerblauw/indigo `#5B6CD9` |
| **Upcoming** | Tijdlijn van ingeplande taken, herhalingen, deadlines en agenda-items per dag | Kalender | Rood `#F2463C` |
| **Anytime** | Alles wat nu kan, zonder datum | Gestapelde lagen | Teal `#39B0A6` |
| **Someday** | Ooit/misschien; verborgen tot je het activeert | Doos/archief | Beige/zand `#D9BD7A` |
| **Logbook** | Afgeronde en geannuleerde items | Vinkje in vierkant | Groen `#5BBF5A` |
| **Trash** | Verwijderde items | Prullenbak | Grijs `#8E8E93` |

Bron voor lijsten: [Bron]. Kleurwaarden: [Benadering].

### 2.2 Gebruikersstructuur (sidebar, onder de vaste lijsten)

```
Area (verantwoordelijkheidsgebied, nooit "af")
 ├── Project (heeft een einde, toont voortgangstaartje)
 │    ├── Heading (sectie/mijlpaal binnen project)
 │    │    └── To-do
 │    │         └── Checklist-item
 │    └── To-do
 └── To-do (los binnen area)
```

- **Area**: groepeert projecten en losse to-do's; kan niet worden afgevinkt. Sidebar toont projecten ingesprongen onder hun area. [Bron]
- **Project**: afronden mogelijk; voortgang als *progress pie* (cirkel die vult). [Bron]
- **Heading**: alleen binnen projecten; sleepbaar als groep; archiveerbaar met alle to-do's eronder. [Bron]
- **Checklist**: lichte substructuur binnen één to-do. Plakken van een opsomming uit een andere app wordt automatisch een checklist. [Bron]
- **Tags**: dwarsverbanden (context, persoon, tijdsinschatting). Hiërarchisch mogelijk, app-breed filterbaar. [Bron]

### 2.3 Verborgen/zoekbare lijsten
Via Quick Find bereikbaar: *Tomorrow*, *Deadlines*, *Repeating*, *All Projects*, *Logged Projects*. [Bron]

---

## 3. Datamodel (ontwerprelevant)

| Veld | Type | Zichtbaar in lijstrij als |
|------|------|---------------------------|
| Titel | tekst, één regel | Hoofdtekst |
| Notitie | Markdown | Klein notitie-icoon achter de titel |
| When (startdatum) | Today / This Evening / datum / Anytime / Someday | Gele ster (vandaag) of datumlabel |
| Reminder | tijd, gekoppeld aan When | Klein belletje/tijd |
| Deadline | datum | Vlag + "x dagen over"; rood als vandaag/verlopen |
| Herhaling | schema | Kringpijl-icoon |
| Tags | lijst | Grijze pillen rechts |
| Checklist | lijst van items | Klein checklist-icoon, evt. teller |
| Status | open / afgerond / geannuleerd | Vinkje / kruis in checkbox, titel grijs |
| Bovenliggend | area/project/heading | Grijs label onder titel in overzichtslijsten (Today, Upcoming) |

**Belangrijk onderscheid** [Bron]: *When* = wanneer je eraan wilt beginnen; *Deadline* = wanneer het af moet. Twee aparte velden, twee aparte visuele signalen. Een deadline laat de taak op die dag in Today verschijnen.

---

## 4. Layout

### 4.1 Mac
- **Twee kolommen**: sidebar (links, ± 240–260 px [Benadering]) + inhoud.
- Sidebar: lichtgrijze achtergrond, vaste lijsten bovenaan, daaronder areas met ingesprongen projecten; onderaan knoppen *New List* en *Settings*.
- **Slim Mode**: sidebar inklappen met twee-vinger-veeg of `⌘ /`; wisselen van lijst via klik op de venstertitel of Type Travel. [Bron]
- **Meerdere vensters**: lijsten/projecten in eigen vensters; to-do's tussen vensters slepen. [Bron]
- Inhoudskolom: gecentreerde leeskolom met royale marges (max. ± 700 px breed [Benadering]), grote lijsttitel met icoon linksboven, onderaan een subtiele werkbalk (nieuwe to-do, When, verplaatsen, zoeken).

### 4.2 iPhone
- Startscherm = de sidebar als lijst (vaste lijsten + areas/projecten) met zoekveld bovenaan.
- Lijstscherm: grote titel (large title-stijl), to-do's eronder, **Magic Plus**-knop rechtsonder zwevend.
- To-do openen gebeurt **inline**: de rij vouwt uit tot een kaart in de lijst, geen push naar een nieuw scherm. [Bron + Waargenomen]

### 4.3 iPad
- Sidebar + inhoud zoals Mac; sidebar wegveegbaar in staand en liggend. [Bron]
- Volledige toetsenbord- en trackpadondersteuning. [Bron]

### 4.4 Maatvoering [Benadering]

| Token | Waarde |
|-------|--------|
| Basisraster | 4 pt |
| Buitenmarge inhoud (iPhone) | 20 pt |
| Buitenmarge inhoud (Mac) | 32–40 pt |
| Hoogte to-do-rij | 32–36 pt (Mac), 44 pt (iOS, minimale tikgrootte) |
| Checkbox | 14–16 pt vierkant, hoekradius 3–4 pt |
| Afstand checkbox ↔ titel | 10–12 pt |
| Hoekradius geopende to-do-kaart | 8–10 pt |
| Hoekradius tag-pil | 4 pt (licht afgerond, geen volle capsule) |
| Magic Plus-knop | 56 pt rond, 20 pt van rechter- en onderrand |
| Afstand tussen heading en eerste item | 8 pt; boven heading 24 pt |

---

## 5. Kleur [Benadering]

### 5.1 Basispalet

| Token | Licht | Donker | Gebruik |
|-------|-------|--------|---------|
| `bg.content` | `#FFFFFF` | `#1E1F22` | Inhoudskolom, geopende to-do |
| `bg.sidebar` | `#F4F5F7` | `#252629` | Sidebar |
| `bg.card.shadow` | `rgba(0,0,0,0.10)` | `rgba(0,0,0,0.45)` | Schaduw geopende to-do |
| `text.primary` | `#1C1C1E` | `#F2F2F4` | Titels to-do's |
| `text.secondary` | `#8A8A8F` | `#8E8E93` | Metadata, bovenliggend project, notitie-indicator |
| `text.tertiary` | `#B8B8BD` | `#5C5C61` | Placeholder ("New To-Do", "Notes") |
| `separator` | `#E6E6EA` | `#34353A` | Lijn onder headings, scheidingen |
| `accent` | `#1A7CF9` | `#3D8EFF` | Selectie, links, Magic Plus, headings, afgevinkte checkbox |
| `selection.bg` | `#D8E7FE` | `#27416B` | Geselecteerde rij |
| `checkbox.stroke` | `#C4C4C9` | `#5E5F64` | Lege checkbox |
| `deadline` | `#F2463C` | `#FF5A50` | Deadline vandaag/verlopen, Upcoming-icoon |
| `today` | `#FFD02B` | `#FFD02B` | Ster |
| `evening` | `#5B6CD9` | `#7E8CF0` | Maan |
| `tag.bg` | `#EDEDF0` | `#38393E` | Tag-pil |
| `tag.text` | `#6E6E73` | `#B0B0B5` | Tag-tekst |

### 5.2 Regels
- Kleur alleen als **betekenisdrager**: lijsttype-iconen, ster (vandaag), maan (avond), rood (deadline), blauw (accent/interactie).
- Geen gekleurde achtergronden achter lijsten of projecten; projecten en areas hebben géén eigen kleur. [Waargenomen]
- Afgeronde items: checkbox gevuld met accentkleur + wit vinkje, titel naar `text.secondary`. Blijft zichtbaar tot het naar het Logbook gaat (direct/dagelijks/handmatig, instelbaar). [Waargenomen]
- Dark Mode is een volwaardig thema, niet een geïnverteerde versie. [Bron: Dark Mode aanwezig]

---

## 6. Typografie

- **Lettertype**: systeemfont (San Francisco: SF Pro Display/Text) op alle Apple-platformen. [Waargenomen]
- **Dynamic Type** wordt ondersteund op iOS. [Bron]

| Stijl [Benadering] | iOS | Mac | Gewicht |
|--------------------|-----|-----|---------|
| Lijsttitel | 28 pt | 24 pt | Bold |
| Heading in project | 15 pt | 13 pt | Semibold, `accent`, met `separator`-lijn eronder |
| To-do-titel | 17 pt | 14 pt | Regular |
| Geopende to-do titel | 17 pt | 15 pt | Medium |
| Notities | 15 pt | 13 pt | Regular, `text.secondary` |
| Metadata (project, datum) | 13 pt | 11–12 pt | Regular, `text.secondary` |
| Tag-tekst | 12 pt | 11 pt | Medium |
| Sidebar-items | 17 pt | 13–14 pt | Regular; area-namen Semibold |
| Upcoming-dagnummer | 28 pt | 22 pt | Bold |
| Upcoming-weekdag | 15 pt | 13 pt | Regular, `text.secondary` |

- Notities ondersteunen Markdown: H1/H2, cursief, vet, opsomming, genummerd, takenlijst, citaat, highlight (`::tekst::`), link, doorhalen, code en codeblok. [Bron]

---

## 7. Iconografie

- Eigen, **eenvoudige vlakke iconen**, gevuld met lijstkleur; consistente lijndikte, geen verlopen. [Bron: vlak ontwerp; Waargenomen: stijl]
- **Checkbox-vormen dragen betekenis** [Waargenomen]:
  - To-do: **afgerond vierkant**.
  - Project: **cirkel** die zich als taartdiagram vult met voortgang (progress pie).
  - Checklist-item: **kleine cirkel**.
  - Area: kubus/doosje.
- Kleine status-iconen achter titel (grijs, ± 11–12 pt): notitie, checklist, herhaling, reminder, deadline-vlag.
- Buiten een Today-lijst krijgt een to-do die vandaag gepland staat een **gele ster** vóór de titel.

> Gebruik voor een eigen app zelfgemaakte iconen of SF Symbols. De iconen, naam en het logo van Things zijn eigendom van Cultured Code; namaken is prima voor privégebruik, niet voor publicatie.

---

## 8. Componenten

### 8.1 To-do-rij (gesloten)
```
[□]  Titel van de taak             [tag] [tag]   ⚑ 3 dagen over
     Projectnaam · 📝 · ☑
```
- Checkbox links, titel, rechts tags en deadline.
- Tweede regel (alleen in overzichtslijsten als Today/Upcoming/Anytime): bovenliggend project/area in `text.secondary`.
- Hover (Mac): kalenderknopje verschijnt vóór de to-do → opent Jump Start. [Bron]
- Selectie: `selection.bg`, afgeronde hoeken.

### 8.2 To-do (geopend)
- Rij **vouwt uit** tot een witte kaart met zachte schaduw; omliggende items schuiven weg. [Bron + Waargenomen]
- Inhoud: titel → notities (placeholder "Notes") → evt. checklist → onderrand met datum/tags/deadline zodra ingevuld.
- Rechtsonder een rij van kleine iconen: **Tags**, **Checklist**, **When**, **Deadline**. Klikken voegt het betreffende veld toe. [Bron]
- Sluiten: klik buiten de kaart, `Esc` of `⌘ Return`; kaart klapt terug in de rij.

### 8.3 Checkbox-gedrag
- Klik: vult met accentkleur + vinkje, korte "pop"-animatie. [Waargenomen]
- `⌥`-klik: annuleren (kruis in plaats van vinkje). [Bron]
- Item blijft even staan en verdwijnt later naar Logbook, zodat je een misklik kunt herstellen.

### 8.4 Heading
- Tekst in `accent`, Semibold, met dunne scheidingslijn eronder over de volle breedte.
- Contextmenu (…) rechts: archiveren, omzetten naar project, verplaatsen.
- Slepen verplaatst heading **inclusief** alle onderliggende to-do's. [Bron]

### 8.5 Project-kop
- Progress pie + grote titel + notitieveld eronder + evt. deadline en tags.
- Projectnotities ondersteunen Markdown. [Bron]

### 8.6 Tags
- Kleine, licht afgeronde grijze pillen (geen felle kleuren).
- Tagfilterbalk bovenaan een lijst: klik op een tag filtert de lijst; meerdere tags combineerbaar (`⌘`-klik). [Bron]

### 8.7 Today-lijst
1. Agenda-afspraken bovenaan, compact gegroepeerd (tijd + titel, kleurstip van de agenda). [Bron]
2. To-do's voor vandaag.
3. Sectie **This Evening** met maan-icoon, visueel gescheiden. [Bron]

### 8.8 Upcoming
- Verticale tijdlijn: per dag een groot dagnummer + weekdag, daaronder to-do's, herhalingen, deadlines en afspraken. Verder in de toekomst gegroepeerd per week/maand. [Bron + Waargenomen]
- Herplannen door slepen naar een andere dag. [Bron]

### 8.9 Magic Plus (iOS)
- Ronde knop in `accent`, rechtsonder, met wit plusteken en schaduw.
- **Tik**: nieuwe to-do onderaan/bovenaan de huidige lijst.
- **Oppakken en slepen**: nieuwe to-do precies op de losplek (tussen items, onder een heading, op een dag in Upcoming).
- Slepen naar de **linkermarge** in een project: nieuwe heading.
- Slepen naar het **Inbox-doel** dat links verschijnt: to-do naar Inbox zonder de lijst te verlaten. [Bron]

### 8.10 Jump Start (When-popover)
- Één popover met: **Today**, **This Evening**, kalender voor latere datum, **Someday**, **Add Reminder**, en invoerveld voor natuurlijke taal. [Bron]
- Mac: via hover-knop of `⌘ S`. iOS: via vegen op de rij. [Bron]
- Tijd kiezen op iOS met een draaiwiel ("barrel"). [Bron]

### 8.11 Quick Find / Type Travel
- Mac: gewoon beginnen met typen → zoekveld verschijnt, resultaten direct. [Bron]
- Doorzoekt lijsten, projecten, to-do's en tags; herkent tags en biedt een app-breed tagfilter. [Bron]
- Resultaten gegroepeerd per type, eerste resultaat voorgeselecteerd, `Return` = springen.

### 8.12 Quick Entry (Mac)
- Systeembreed venster via `⌃ Space`; compacte versie van de geopende to-do. Variant "Autofill" neemt link/selectie uit de actieve app over (`⌃ ⌥ Space`). [Bron]

### 8.13 Quick Move
- Popover met doellijsten, filterbaar door te typen (`⇧ ⌘ M`). [Bron]

### 8.14 Lege staten
- Lege lijst toont het grote, lichtgrijze lijsticoon gecentreerd, zonder tekstballast. [Waargenomen]

---

## 9. Interactie en gebaren

| Gebaar (iOS) | Resultaat | |
|--------------|-----------|---|
| Veeg to-do naar rechts | Opent Jump Start (When) | [Bron: "just a swipe away"] |
| Veeg to-do naar links | Acties + direct multi-selectmodus | [Bron] |
| In selectiemodus omhoog/omlaag vegen langs de cirkels rechts | Hele groep selecteren | [Bron] |
| Vasthouden op selectie | Items verzamelen zich onder je vinger; slepen naar nieuwe plek | [Bron] |
| Magic Plus slepen | Invoegen op exacte positie | [Bron] |
| Omlaag trekken in lijst | Zoeken (Quick Find) | [Waargenomen] |
| Plakken van meerregelige tekst | Eén to-do per regel; opsomming in to-do → checklist | [Bron] |
| Haptische feedback | Bij oppakken, loslaten, afvinken | [Bron: Haptic Feedback] |

Mac: slepen en neerzetten tussen lijsten, sidebar en vensters; hover-knoppen; volledige toetsenbordbediening (zie §11).

---

## 10. Beweging en animatie

- Eigen animatietoolkit; alles wat je doet is geanimeerd. [Bron]
- **Uitvouwen i.p.v. navigeren**: een to-do opent op zijn plek, zodat je je positie in de lijst niet kwijtraakt. [Bron]
- **Samenvoegen bij slepen**: meerdere geselecteerde items schuiven samen onder de vinger en "vallen" op hun plek bij loslaten. [Bron]
- Richtlijnen voor eigen implementatie [Benadering]:
  - Uitvouwen/inklappen to-do: 250–300 ms, spring (damping ± 0.85).
  - Afvinken: checkbox schaalt kort naar ± 1,15 en terug in 150 ms.
  - Herordenen: overige rijen schuiven met 200 ms ease-out.
  - Respecteer *Reduce Motion*: vervang door crossfades.

---

## 11. Toetsenbord (Mac/iPad) [Bron]

**Aanmaken**
| Actie | Toets |
|---|---|
| Nieuwe to-do | `⌘ N` |
| Nieuwe to-do onder selectie | `Space` |
| To-do's uit klembord (één per regel) | `⌘ V` |
| Nieuwe checklist in open to-do | `⇧ ⌘ C` |
| Nieuw project | `⌥ ⌘ N` |
| Nieuwe heading | `⇧ ⌘ N` |
| Quick Entry | `⌃ Space` |
| Quick Entry met Autofill | `⌃ ⌥ Space` |

**Bewerken en datums**
| Actie | Toets |
|---|---|
| Openen / opslaan en sluiten | `Return` / `⌘ Return` |
| Afronden / annuleren | `⌘ K` / `⌥ ⌘ K` |
| When tonen | `⌘ S` |
| Today / This Evening / Anytime / Someday | `⌘ T` / `⌘ E` / `⌘ R` / `⌘ O` |
| Startdatum ±1 dag / ±1 week | `⌃ ]` `⌃ [` / `⌃ ⇧ ]` `⌃ ⇧ [` |
| Deadline toevoegen | `⇧ ⌘ D` |
| Deadline ±1 dag / ±1 week | `⌃ .` `⌃ ,` / `⌃ ⇧ .` `⌃ ⇧ ,` |
| Herhaling | `⇧ ⌘ R` |
| Verplaatsen naar lijst | `⇧ ⌘ M` |
| Omhoog/omlaag, naar top/bodem | `⌘ ↑/↓`, `⌥ ⌘ ↑/↓` |

**Navigeren**
| Actie | Toets |
|---|---|
| Inbox, Today, Upcoming, Anytime, Someday, Logbook | `⌘ 1` t/m `⌘ 6` |
| Zoeken | `⌘ F` of gewoon typen |
| Terug / project in | `⌘ ←` / `⌘ →` of `Return` |
| Toon in bovenliggende lijst | `⌘ L` |
| Sidebar tonen/verbergen | `⌘ /` |
| Nieuw venster | `⌃ ⌘ N` |
| Tags bewerken | `⇧ ⌘ T` |
| Filter wissen | `⌃ Esc` |

---

## 12. Natuurlijke taal
Datuminvoer herkent afkortingen en tijden, bijv. "tom" → morgen, "sat" → zaterdag, "in 4 days", "aug 1", "wed 8pm". [Bron]
Voor een Nederlandstalige versie: "morg", "za", "over 4 dagen", "1 aug", "wo 20:00" als equivalent opnemen.

---

## 13. Platformintegratie [Bron]
Agenda-integratie (Today/Upcoming), reminders met directe push naar alle apparaten, widgets, Control Center- en Lock Screen-knoppen, Siri & Shortcuts, Mail to Things, Handoff, Split View, Home Screen Quick Actions, URL-scheme, Writing Tools, Apple Watch (incl. checklists en headings), Vision Pro.

---

## 14. Toegankelijkheid
- Dynamic Type en Dark Mode ondersteund. [Bron]
- Aanbevolen voor eigen implementatie: minimaal 44 × 44 pt tikdoelen, kleur nooit als enige signaal (deadline ook met vlag-icoon + tekst), contrast ≥ 4,5:1 voor `text.secondary`, VoiceOver-labels op checkbox ("Taak afronden: …") en Reduce Motion.

---

## 15. Samenvatting in één oogopslag
- Wit, vlak, systeemfont, kleur alleen voor betekenis.
- Vaste lijsten: Inbox · Today (+ This Evening) · Upcoming · Anytime · Someday · Logbook.
- Structuur: Area → Project → Heading → To-do → Checklist; tags dwars erdoorheen.
- To-do opent inline als "wit vel papier"; extra velden pas op verzoek.
- Vorm = type: vierkant (to-do), cirkel/taart (project), kleine cirkel (checklist).
- When ≠ Deadline: gele ster vs. rode vlag.
- Magic Plus (slepen = invoegen), Jump Start (datum), Quick Find/Type Travel (navigatie).
- Alles geanimeerd, alles met toetsenbord bedienbaar.

---

## Bronnen
- Banani – Things 3 UI-schermen: https://www.banani.co/references/apps/things-3
- Alex Sanchez-Olvera – *How I Organize My Life (and Business) with Things 3*: https://alexsanchezdesigns.medium.com/how-i-organize-my-life-and-business-with-things-3-9f3bef8f3efd
- Cultured Code – Things: https://culturedcode.com/things/
- Cultured Code – Features (aanvullend geraadpleegd): https://culturedcode.com/things/features/
- Cultured Code – Keyboard Shortcuts (aanvullend geraadpleegd): https://culturedcode.com/things/support/articles/2785159/
