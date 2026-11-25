# Artwork sources

| Group | Source | Maintenance |
|---|---|---|
| Existing character layers | CharacterKit history, baseline `230ed6b9d2a7d76cf50cee0cc33a12453c127689` | Existing attribution is retained; the external reference-layer generator is not included. |
| SEMI | Supplied `CharacterKit-SEMI-commercial-final-20261006-v17` artwork | Registered inputs and the reproducible preparation script are in [SEMI](SEMI/README.md). |
| Norwegian emotion GIFs | Generated at the user's request in [ChatGPT](https://chatgpt.com/c/6af6a4ee-1a5c-83e8-9c3c-b36fa7acc8f3), 2026-11-13 | [Norwegian](Norwegian/README.md) records source hashes and normalization. Twelve final GIFs and one neutral PNG are bundled. |
| Full-body black cat | User-supplied sRGB JPEG character sheet `845996900_17986676232109569_1470082081660408522_n.jpg` (SHA-256 `82c449c8cda29031f4cee1890d3a552026e024cf4d0990f59fe817466667ae51`) | [High-resolution masters](FullBodyCat/HIGH_RESOLUTION.md) records the reference crops, prompts, and master hashes for all ten poses. [FullBodyCat](FullBodyCat/README.md) records joint registration and preparation of the 22 runtime PNGs. |
| Crayon black cat | Original simplified vector shapes developed for CharacterKit | [Crayon geometry](../Sources/ReactiveCharacterKit/Scene/Anatomy/CrayonCat/CharacterCrayonCatGeometry.swift) shares the felt cat's pose and activity vocabulary. |

The repository retains the original Axient Inc. copyright notice. These technical
source records do not add a separate distribution license.
