# Changelog

## Unreleased · next major candidate

This working tree is a release candidate under development. The existing `1.0.0` tag is unchanged.

### Client migration

- The SEMI-only development revision's `CharacterSceneBuilder.scene(pose:width:height:)`
  remains available. Select `.semi` explicitly for SwiftUI and use the SEMI art-direction
  pose/session overloads to retain that revision's SEMI defaults; the multi-character
  API's default view remains Black.
- Handle `CharacterTheme.semi` and `CharacterAnatomy.semiDocumentCat` in exhaustive switches. Existing raw values and serialized design schemas are unchanged.
- Validated `CharacterArtDirection` configurations accept at most 16 image accessories, exposed as `maximumAccessoryCount`. Larger packs throw the existing `invalidValue` error with field `assets.accessories.count`.
- Use `CharacterDesign.decode(_:)` and `CharacterReferenceDocument(data:)` for untrusted JSON. Generic Codable decoding is for trusted model exchange and does not enforce raw byte, depth or duplicate-member limits.

### Character and runtime

- Add `ReactiveCharacterGIFView(emotion:playbackTrigger:accessibilityLabel:accessibilityValue:)`
  with twelve bundled Norwegian Forest Cat emotion clips. Each plays once and returns
  to identical neutral pixels; interruptions pass through neutral and repeated emotions
  can be explicitly replayed. Reduce Motion uses a still expression. Live gaze, speech
  and action events remain the responsibility of `ReactiveCharacterView`.
- Resolve secondary motion through the same active visual owner as the eyes after a
  one-shot expires, including when the host sends its completion event late.
- Correct the reference Norwegian cat's mouth curvature so sad corners fall and happy
  corners lift in scene coordinates; connect the open-mouth shape to the lip line.
- Preserve authored Norwegian eye sockets rather than exposing unfinished underlying
  artwork through cartoon-shaped clips. This family now uses restrained default motion;
  until registered eyelids are available, blink does not visibly close its eyes.
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
