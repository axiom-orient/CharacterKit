# Changelog

## Unreleased · next major candidate

This working tree is a release candidate under development. The existing `1.0.0` tag is unchanged.

### Client migration

- Remove the four layered Norwegian coats, `CharacterNorwegianVariant`,
  `CharacterReferenceAppearance.norwegianForest`, and the obsolete
  `catNorwegianForest` art-direction/style constants. Use
  `ReactiveCharacterGIFView(state:)` for the single Norwegian character. Old
  reference documents with kind `norwegianForest` now fail explicitly; select the
  GIF view in the host instead of importing a coat. This is an intentional major-version break.

- The SEMI-only development revision's `CharacterSceneBuilder.scene(pose:width:height:)`
  remains available. Select `.semi` explicitly for SwiftUI and use the SEMI art-direction
  pose/session overloads to retain that revision's SEMI defaults; the multi-character
  API's default view remains Black.
- Handle `CharacterTheme.semi` and `CharacterAnatomy.semiDocumentCat` in exhaustive switches. Existing theme raw values and the CharacterDesign schema are unchanged.
- Validated `CharacterArtDirection` configurations accept at most 16 image accessories, exposed as `maximumAccessoryCount`. Larger packs throw the existing `invalidValue` error with field `assets.accessories.count`.
- Use `CharacterDesign.decode(_:)` and `CharacterReferenceDocument(data:)` for untrusted JSON. Generic Codable decoding is for trusted model exchange and does not enforce raw byte, depth or duplicate-member limits.

### Character and runtime

- Add the optional `CharacterChat` product with bounded sentence cues, explicit/local
  emotion selection, Unicode-safe speech ranges and audio/text-preview timelines.
- Add `CharacterSpeechArticulation`, `CharacterPose.applyingSpeechArticulation` and
  `.characterSpeechArticulation(_:)` for timed open/wide/rounded/closed mouths across
  vector, layered and GIF renderers. Existing semantic events and state are unchanged.
- Open the native demo in a chat studio with real Korean/English audio, shared
  Norwegian/Simple 2D presentation, twelve-expression tour, interruptible playback,
  gaze/action controls and actual native capture. Reuse the capture surface in the
  existing all-character showcase.

- Make compact-cat anger legible with a wide inward-slanted eye silhouette and
  downturned mouth corners. Reuse the shared compact-eye contour and preserve blink,
  gaze and continuous expression transitions.

- Give the single Norwegian GIF cat expression-aware speech: preserve angry fangs,
  round surprise/yawn openings and distressed mouth shapes, with a shared neutral
  speech pose at every clip boundary. Reuse existing textures with a bounded cache.

- Add `ReactiveCharacterGIFView(state:playbackTrigger:accessibilityLabel:accessibilityValue:)`
  with twelve bundled Norwegian emotion clips plus live speech, gaze, blink and action
  composition. Clips play once and return to shared neutral pixels while live input
  continues. Voice/gaze updates preserve emotion time. Texture articulation reuses
  existing authored frames and adds no image files. The emotion-only initializer remains.
- Resolve secondary motion through the same active visual owner as the eyes after a
  one-shot expires, including when the host sends its completion event late.
- Added SEMI as an anatomy within the existing pose/scene pipeline, with six registered textures and live vector face features.
- Rebuilt SEMI mouth as closed line art only: rounded lip branches and a connected philtrum, including voice and surprise. No cavity or tongue is rendered.
- Added six short animated whiskers: ordinary poses stay extended while angle, reach and staggered sway vary; strong distress or explicit impact/tremor may retract and ripple. Laugh/body energy no longer masquerades as impact. Reduce Motion and retarget continuity remain supported.
- Corrected ear attachment registration and reviewed the visible seam in native captures.
- Removed redundant gray internal eye curves; retained aperture expression, correctly clipped pupils and glints. Surprise has a rounder aperture and gentler head/ear lift.
- Refined neutral whiskers to three independently angled, nearly straight short strands per cheek, with a shorter upper strand and a tiny gravity curve; blink preserves this local shape while following head movement.
- Added typed artDirection pose/session configuration for gentle SEMI idle motion; legacy overloads retain standard neutral hold and existing clocks own all motion.
- Coordinated eye/body cues distinguish joy, gratitude, sadness, anxiety, calm trust and fatigue, including sadness upper-lid articulation.
- Preserved host-owned semantic state and raw pose sampling while presentation retargeting smooths abrupt voice amplitude and task-progress gaze changes.
- Saturated presentation elapsed-time overflow and consolidated scene painter-order validation.

### Development and validation

- Added regression coverage, native PNG checks, safe preview export, reproducible artwork inputs, and pinned authoring dependencies.
- Added a minimum/current Xcode CI matrix, a public native host consumer, and a release-build CPU benchmark. The benchmark measures SDK computation and offline export, not display FPS.
- Distribution terms and platform validation conditions are documented in README.md and Artwork/PROVENANCE.md.

## 1.0.0

Initial tagged release (`939a9d2`).
