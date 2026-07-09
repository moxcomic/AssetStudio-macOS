#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-engine.sh"
command -v xcodegen >/dev/null || brew install xcodegen
(cd "$ROOT/app" && xcodegen generate)
xcodebuild -project "$ROOT/app/AssetStudio.xcodeproj" -scheme AssetStudio \
  -configuration Release -derivedDataPath "$ROOT/app/build" build
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/AssetStudio.app"
cp -R "$ROOT/app/build/Build/Products/Release/AssetStudio.app" "$ROOT/dist/"
echo "→ $ROOT/dist/AssetStudio.app"
