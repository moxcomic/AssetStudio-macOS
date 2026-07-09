# Test fixtures

Unity asset bundles from UnityPy's test suite:
https://github.com/K0lb3/UnityPy/tree/9a7c0ab9655bacd716e2af36fb950a92ec5109a5/tests/samples
Downloaded via media.githubusercontent.com (LFS-resolved) on 2026-07-09, pinned to
UnityPy commit `9a7c0ab9655bacd716e2af36fb950a92ec5109a5` (provenance ref; the
committed bytes are pinned independently by the SHA-256 list below).

Licensing: the MIT license covers UnityPy's own code and test suite. The asset
payloads are third-party game assets redistributed by that suite and used here
solely as read-only test data.

| File | Notes |
|---|---|
| char_118_yuki.ab | UnityFS, Unity 5.6.7f1 — 35 AudioClip assets (verified via AssetStudioModCLI). Exact-contents fixture: **704951 bytes**. |
| xinzexi_2_n_tex | UnityFS bundle, Unity 2017.4.37f1 — Texture2D + Mesh (`xinzexi_2_n-mesh`) + Sprite + AssetBundle. Contains the mesh that `xinzexi_2_n_tex_mesh` is the exported reference for; "texture bundle" undersells it. *(inventory as reported by quality review via UnityPy parse)* |
| xinzexi_2_n_tex_mesh | Wavefront OBJ (ASCII, CRLF) — golden mesh-export reference for `xinzexi_2_n_tex`. **NOT a UnityFS bundle** (see note). |
| atlas_test | UnityFS bundle, Unity 2018.4.11f1 — SpriteAtlas + 7 Sprites + Texture2D. *(inventory as reported by quality review via UnityPy parse)* |
| banner_1 | UnityFS bundle, Unity 2018.4.4f1 — Sprite + Texture2D. *(inventory as reported by quality review via UnityPy parse)* |
| corrupt.bin | 4 KB of /dev/urandom — must fail to parse without crashing. (libmagic / `file(1)` may mislabel it as an "OpenPGP Secret Key" because the random first byte happens to be 0x94; it is pure random noise, not a secret.) |

> **Note on `xinzexi_2_n_tex_mesh`:** In UnityPy's sample set this file is the
> exported OBJ mesh paired with the `xinzexi_2_n_tex` bundle — the *expected
> output* for mesh-export validation, not a bundle to be parsed. It begins with
> the OBJ group line `g xinzexi_2_n-mesh` (verified via hex dump + `file(1)`),
> whereas the other four bundles carry the `UnityFS` magic. Engine tests should
> treat it as a golden mesh-export reference and must not assert UnityFS parsing
> on it. The upstream `tests/samples` directory contains exactly these five
> files, so no UnityFS mesh bundle was substituted — this is the real upstream
> artifact at its original name.

SHA-256:
```
6198cb71c7a820256208332bbd375d21b18ed1a36a12ad04be1eef2111b014a1  char_118_yuki.ab
a9f6e6bba7110cce647ef752d66655d13ce5850b013a60d80d4e8b08953e02ea  xinzexi_2_n_tex
8bb2082b9586b3f8f3bad2d22d33346ec0492053f2a76323aa8b4b4047368ca8  xinzexi_2_n_tex_mesh
61ee5afb5f5c64f0a4f65f039d09b2509198363e713423289c895067ac215177  atlas_test
6bd0c3bc36c97e5f1cd2de71bb58477b6c32ac2c254a5705884306c56b94417f  banner_1
f5e80727c8dccf04dbbc8cf75fe1e6f8da2793364b86c40c63f8ce0600b63e4f  corrupt.bin
```
