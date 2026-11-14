# SDK architecture

CharacterKit exports one library: `ReactiveCharacterKit`. CharacterStudio is a
separate application and consumes a published SDK version; it owns chat, audio,
application state and native file output.

## Data flow

```text
host event → reducer → next state + effects
                    ↓
           presentation session → pose → anatomy → scene → renderer
```

The host retains the complete opaque `CharacterState`. Every semantic change enters
through `ReactiveCharacter.reduce` or `act`. Effects request host work; observed results
return as events. Identity checks prevent stale tasks/actions from replacing newer work.

`CharacterPresentationSession` owns display continuity and independent layer clocks.
Palette/layout changes and parameter-only voice/gaze input preserve those clocks.
Reduce Motion applies explicit targets without autonomous travel. SwiftUI adapters
pause their timeline when the scene is inactive.

## Rendering boundaries

- Contract/Decision: validated input, state transition, disposition and effects.
- Presentation: deterministic pose sampling, interruption, gaze and mouth retargeting.
- Appearance/Scene: artwork geometry, palette, painter order and scene validation.
- ResourceIO/Rendering: resource decoding and SVG/Apple output.
- UI: SwiftUI environment and timeline adapters; no text interpretation or audio engine.

All anatomies consume the same numeric pose without forcing the same geometry.
Minimal/portrait characters use vectors; SEMI combines registered layers and vectors;
reference mascots use layered artwork. The mouth is one numeric rig. Its optional
agent-output waveform keeps its own presentation timing without a parallel contour atlas.

## Norwegian emotion clips

`CharacterGIFPresentation` coordinates one-shot GIF playback and the existing pose
session on one monotonic time source. The clip owns emotion geometry; communication,
attention, activity and action remain independent. Interruptions return through neutral.
The twelve bundled files have the same canvas and identical first/last neutral pixels.

A per-view rig tracks eye/nose landmarks, warps eye interiors for gaze and registers
mouth/closed-eye patches from existing frames. Speech uses expression-appropriate
mouth textures. Each view retains a bounded current speech pair and one-clip frame
cache; no additional facial image atlas is bundled.

## Timed speech

`CharacterSpeechArticulation` is normalized host input containing openness/width.
The shared SwiftUI modifier retargets over 45ms during chat/voice output, preserving
emotion curvature and all gaze, body and action channels. Nil restores ordinary
articulation. Custom renderers can apply the value to a sampled pose. The SDK does
not infer sentiment, estimate phonemes or create audio.

## SEMI

The SEMI renderer uses connected closed mouth strokes and three whiskers per cheek.
Ordinary acting changes their direction/reach without crumpling; strong distress or
explicit recoil/shake may retract them. Unblinked eye geometry prevents blink from
moving the whiskers. Artwork preparation and registered inputs are owned by
[Artwork/SEMI](../Artwork/SEMI/README.md).

## Input and resource validation

`CharacterDesign.decode` and `CharacterReferenceDocument(data:)` validate byte limits,
JSON structure and schema. Generic Codable exchange cannot enforce raw-document
constraints. Scene compilation checks finite geometry, identities and painter order.
Resource failures stay explicit; rendering never substitutes hidden artwork or writes files.
