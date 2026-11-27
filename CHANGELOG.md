# Changelog

## 2.1.5

- Keep the felt cat’s torso and tail steady while its paws step, without changing the crayon gait.
- Stabilize live felt and crayon cat rendering on iOS 27.2 and later to prevent intermittent Canvas displacement during walking.

## 2.1.4

- Give the felt cat a shorter, lower companion brow for asymmetric expressions and fade the brow strokes during side turns.
- Show the new Norwegian cat expression immediately when an active expression is replaced under Reduce Motion.
- Keep authored round mascots inside the viewport during large motions while preserving their neutral size.

## 2.1.3

- Keep SVG zero coordinates in floating-point format to avoid Foundation formatting warnings on iOS.
- Add an explicit simulator option that runs the full iOS test suite and simplify the Swift 6 package configuration.

## 2.1.2

- Resolve native PNG aliases with or without the filename extension.
- Load only the textures for the active walking direction and warm the first authored frame for each felt route.
- Share ImageIO PNG encoding across felt and macOS scene export.

## 2.1.1

- Reduce the runtime resource payload with a losslessly compressed felt motion atlas and optimized PNGs.
- Share identical reference eye and mouth masks while retaining their existing asset names.
- Shorten the SDK guides and keep authoring tools in the Git checkout.

## 2.1.0

- Add felt and crayon full-body cats with ten resting poses and six gestures. Both use the shared expression, gaze and speech inputs.
- Use a shared animated envelope for headset appearances so accessory selection preserves the face geometry.
- Pass generated felt frames directly to Canvas to reduce first-draw latency.

## 2.0.1

- Make GIF mouth-mask arithmetic explicitly Double so Swift 6.0/6.1 toolchains compile
  the same rendering calculation without CGFloat overload ambiguity.

## 2.0.0

- Restore the multi-character SDK with shared emotion, speech, gaze and action channels.
- Add the Norwegian GIF renderer, timed speech articulation and neutral-return emotion clips.
- Separate CharacterStudio, speech synthesis, chat interpretation and demo tools into their own repository.
- Remove the unused traced-mouth atlas and raster test fixtures. The live numeric mouth rig
  and agent-output waveform retain their rendering and transition contracts.

### Migration

- The package exports only `ReactiveCharacterKit`. The former `CharacterChat` demo
  adapter now belongs to CharacterStudio. SDK clients supply emotion metadata and
  timed `CharacterSpeechArticulation` values from their own chat/audio provider.
- The four layered Norwegian coats, `CharacterNorwegianVariant`,
  `CharacterReferenceAppearance.norwegianForest`, and `catNorwegianForest` constants
  are removed. Use `ReactiveCharacterGIFView(state:)` for the Norwegian character.
- The default view is Black. Select `.semi` explicitly to preserve the SEMI-only
  development revision's appearance and its `.semiDocumentCat` pose/session defaults.
- Handle `.semi` / `.semiDocumentCat` in exhaustive theme/anatomy switches.
- Image accessory configurations accept at most sixteen entries. Use the validated
  Data-based design/reference decoders for imported JSON.

The `1.0.0` tag remains available for earlier clients.
