# Werkbank – afspraken voor wijzigingen

Lees eerst `OVERDRACHT.md`: werkwijze, testregels voor echte gegevens, wat nog getest moet worden en open punten.

- De app is alleen voor persoonlijk gebruik. Geen helpteksten, uitleg, footers of voorbeeld-placeholders in de UI;
  alleen labels, gegevens en foutmeldingen.
- Labels van invoervelden: `Color.fieldLabel` (themarol "Veldlabel"; in Standaard #1A8CFF), semibold.
- Kleuren via `ThingsColor` (uit het gekozen thema, `Shared/Design/Theme.swift`), letters via `.font(.werk(size:))` of
  `thingsFont`, nooit `.system(size:)` of vaste hexkleuren voor gewone onderdelen.
- Meldingen na een handeling (verzonden, gelogd, ongedaan) via `AppState.announce` (de zwevende pil).
- Een mail (lezen en opstellen) heeft in de lichte weergave altijd een witte achtergrond, in elk thema
  (`ThingsColor.mailPaper`); thema's stylen alleen wat eromheen staat.
- Mail werkt met archiveren: verwerkt, beantwoord of een taak van gemaakt is archiveren. Mappen (Gmail-labels) zijn
  er om te bekijken (de kolom in de mailmodus); bouw geen handelingen om mappen heen.
- Mailmodus (`macOS/MailMode/`): elke handeling heeft een toets (`MailModeAction`, aan te passen in Voorkeuren) en
  eindigt in archiveren en de volgende mail.
- Na elke wijziging: CI moet groen zijn (WerkbankCore-tests, macOS- en iOS-build). Bijwerken op de Mac:
  `./Scripts/update-and-run.sh`.
