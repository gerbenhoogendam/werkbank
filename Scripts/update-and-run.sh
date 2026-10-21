#!/bin/zsh
# Haalt de nieuwste versie op, genereert het project, bouwt Werkbank (macOS, Debug) en start de nieuwe build.
# Gebruik vanuit de map werkbank:  ./Scripts/update-and-run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› Ophalen…"
git pull --ff-only origin main

echo "› Project genereren…"
xcodegen generate --quiet

# Draait Werkbank nog, dan eerst netjes afsluiten (en zo nodig hard).
if pgrep -x Werkbank >/dev/null; then
    echo "› Werkbank afsluiten…"
    osascript -e 'tell application "Werkbank" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x Werkbank >/dev/null || break; sleep 0.25; done
    pkill -x Werkbank 2>/dev/null || true
fi

echo "› Bouwen (dat duurt even)…"
xcodebuild -project Werkbank.xcodeproj -scheme Werkbank-macOS -configuration Debug \
    -derivedDataPath DerivedData -quiet build

echo "› Starten…"
open DerivedData/Build/Products/Debug/Werkbank.app
echo "Klaar: $(git log --oneline -1)"
