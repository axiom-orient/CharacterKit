# Artwork provenance

This inventory records the available source evidence. It does not grant a distribution license.

| Group | Available source | Reproduction and rights record |
|---|---|---|
| Original library code and bundled artwork | GitHub `axiom-orient/CharacterKit`, baseline `230ed6b9d2a7d76cf50cee0cc33a12453c127689`; README identifies `Copyright © Axient Inc.` | Source history is retained. The repository supplies no separate LICENSE/NOTICE grant. Distribution terms must be confirmed by the owner. |
| Reference character textures and generated rig catalog | Existing `Resources` and `CharacterReferenceCatalog.generated.swift` | The catalog identifies an externally maintained artwork/rig pipeline. Generator/master sources and per-asset attribution are not included; these cannot be inferred from generated files. |
| SEMI authoring inputs | Supplied `CharacterKit-SEMI-commercial-final-20261006-v17` snapshot | The preview and registered ear inputs required by the generator are retained in [SEMI](SEMI/README.md); unused atlases/sprite sheets were removed. |
| SEMI runtime layers | Six PNGs retained from the supplied snapshot; final registered ears are also stored as explicit authoring inputs | [Asset preparation](../Tools/SEMI/prepare_assets.py) reproduces decoded RGBA pixels using the documented pinned environment. Four PNG encodings can differ by platform. This is technical reproducibility evidence, not a rights determination. |
| SEMI mouth and whisker geometry | Authored scene-vector code in this working tree, informed by the user's closed-mouth references in Desktop/cat and the 11:35:17 whisker reference | Uses the existing live pose and palette. No stock-image bitmap was copied into the runtime resource bundle. The supplied images are visual references, not distribution grants. Open-mouth reference variants are excluded by the user’s latest closed-line requirement. |
| Norwegian emotion GIFs | Generated at the user's request in [ChatGPT](https://chatgpt.com/c/6af6a4ee-1a5c-83e8-9c3c-b36fa7acc8f3), 2026-11-13 | Twelve reviewed expressions; duplicated positive variants are excluded. [Preparation](../Tools/Norwegian/README.md) records the normalization process and original file hashes. Only final GIFs and the canonical neutral PNG are bundled. |
| Review captures and demo output | Generated locally by Preview and the host wrapper | Reproducible development artifacts; omitted from source archives and the library resource bundle. |

Before external distribution, attach the owner's actual distribution terms and any applicable attribution to the release. Confirm the existing reference and supplied SEMI artwork against those terms. Preserve the authored source files and their recorded origin.
