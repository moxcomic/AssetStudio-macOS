#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$ROOT/engine/publish"
dotnet publish "$ROOT/engine/AssetStudio.Engine/AssetStudio.Engine.csproj" \
  -c Release -r osx-arm64 --self-contained -o "$ROOT/engine/publish"
echo "engine published → $ROOT/engine/publish"
