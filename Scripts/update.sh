#!/bin/sh
# Haalt de nieuwste versie op, maakt het Xcode-project opnieuw en opent het.
# Gebruik: ./Scripts/update.sh   (vanuit de projectmap)
set -e
cd "$(dirname "$0")/.."

git pull --ff-only

# XcodeGen zonder Homebrew: eenmalig downloaden naast het project.
if [ ! -x xcodegen/bin/xcodegen ]; then
  echo "XcodeGen wordt gedownload..."
  curl -sL -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
  unzip -q -o xcodegen.zip
  rm -f xcodegen.zip
fi

./xcodegen/bin/xcodegen generate
open Werkbank.xcodeproj
