# Changelog

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
