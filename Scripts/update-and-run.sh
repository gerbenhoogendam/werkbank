#!/bin/zsh
# Haalt de nieuwste versie op, genereert het project, bouwt Werkbank (macOS, Debug) en start de nieuwe build.
# Gebruik vanuit de map werkbank:  ./Scripts/update-and-run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› Ophalen…"
git pull --ff-only origin main

echo "› Project genereren…"
if command -v xcodegen >/dev/null; then
    xcodegen generate --quiet
elif [ -x xcodegen/bin/xcodegen ]; then
    ./xcodegen/bin/xcodegen generate --quiet
else
    echo "XcodeGen ontbreekt: brew install xcodegen" >&2; exit 1
fi

# Draait Werkbank nog, dan eerst netjes afsluiten (en zo nodig hard).
if pgrep -x Werkbank >/dev/null; then
    echo "› Werkbank afsluiten…"
    osascript -e 'tell application "Werkbank" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x Werkbank >/dev/null || break; sleep 0.25; done
    pkill -x Werkbank 2>/dev/null || true
fi

# De Duo-vouw heeft een Metal-shader; in Xcode 26 is de Metal-toolchain een losse download.
if ! xcrun metal --version >/dev/null 2>&1; then
    echo "Metal-toolchain ontbreekt: xcodebuild -downloadComponent MetalToolchain" >&2; exit 1
fi

echo "› Bouwen (dat duurt even)…"
# -allowProvisioningUpdates: Xcode werkt het ondertekeningsprofiel bij als de app nieuwe rechten krijgt (bijv. iCloud Drive).
xcodebuild -project Werkbank.xcodeproj -scheme Werkbank-macOS -configuration Debug \
    -derivedDataPath DerivedData -allowProvisioningUpdates -quiet build

echo "› Starten…"
open DerivedData/Build/Products/Debug/Werkbank.app
echo "Klaar: $(git log --oneline -1)"
