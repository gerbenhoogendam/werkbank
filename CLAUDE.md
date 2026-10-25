# Werkbank – afspraken voor wijzigingen

Lees eerst `OVERDRACHT.md`: werkwijze, testregels voor echte gegevens, wat nog getest moet worden en open punten.

- De app is alleen voor persoonlijk gebruik. Geen helpteksten, uitleg, footers of voorbeeld-placeholders in de UI;
  alleen labels, gegevens en foutmeldingen.
- Labels van invoervelden: `Color.fieldLabel` (themarol "Veldlabel"; in Standaard #1A8CFF), semibold.
- Kleuren via `ThingsColor` (uit het gekozen thema, `Shared/Design/Theme.swift`), letters via `.font(.werk(size:))` of
  `thingsFont`, nooit `.system(size:)` of vaste hexkleuren voor gewone onderdelen.
- Meldingen na een handeling (verzonden, gelogd, ongedaan) via `AppState.announce` (de zwevende pil).
- Na elke wijziging: CI moet groen zijn (WerkbankCore-tests, macOS- en iOS-build). Bijwerken op de Mac:
  `./Scripts/update-and-run.sh`.
