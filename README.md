# AssetStudio for macOS

A native macOS app for exploring, previewing, and extracting assets from Unity
games — the first-class Mac experience that [AssetStudio](https://github.com/Perfare/AssetStudio)
never had. SwiftUI + Liquid Glass front end, driving the **unmodified**
[aelurum/AssetStudioMod](https://github.com/aelurum/AssetStudio) core (Unity
1.7–6000.x) as a .NET engine sidecar over JSON-RPC.

Built for Apple Silicon / macOS 26 (Tahoe).

## What works

- Load `.unity3d` / `.ab` / asset-bundle files and folders (⌘O, **drag-and-drop**,
  or Finder/Dock open)
- Browse a searchable, sortable asset table with a type-filtered sidebar
- Preview Texture2D / Sprite (zoom, pan, RGBA channel toggles), text,
  MonoBehaviour JSON dumps, and a metadata inspector
- Export **convert / raw / dump** with grouping options, a progress HUD, and
  cancellation — textures (PNG/TGA/JPEG/BMP/WebP), audio (FMOD FSB→WAV), meshes
  (OBJ), fonts, shaders
- Verified end-to-end against real iOS Unity 2022.3 game bundles (ASTC decode included)

Deferred to later milestones: Animator→FBX export UI, audio waveform preview,
3D mesh viewport, Live2D, and the scene-hierarchy / classes sidebar modes.

## Build

```bash
./scripts/build.sh      # → dist/AssetStudio.app (self-contained, ad-hoc signed)
```

Requires Xcode 26, the .NET 10 SDK, and `xcodegen` (`brew install xcodegen`).
The script publishes the engine, embeds it in the `.app`, and produces a
double-clickable standalone bundle.

Tests: `dotnet test engine/AssetStudio.Engine.Tests -c Release` (engine) and
`cd app && xcodegen generate && xcodebuild -scheme AssetStudio test` (app).

## Architecture

The Unity-format engine is the vendored AssetStudioMod core, kept byte-for-byte
pristine under `engine/external/`. A thin .NET 10 `AssetStudioEngine` process
wraps it and speaks JSON-RPC on stdio; the SwiftUI app owns only view state and
talks to that sidecar.

## Licensing

The macOS port (`app/`, `engine/AssetStudio.Engine/`, `scripts/`) and the
vendored AssetStudioMod core are MIT-licensed — see the upstream projects for
their terms. **Third-party native binaries** bundled under
`engine/external/.../Libraries/` (FMOD, and the FBX-SDK-based wrapper) retain
their own licenses, which restrict redistribution; anyone repackaging or
publicly distributing this project should review and comply with those terms
separately. This repository is a personal build.
