# Architecture

CharacterKit is a Swift package that turns host-observed semantic state into a time-sampled pose and a validated scene. The host owns application state, external work, timers, persistence, and status wording. The package owns event reduction, presentation sampling, appearance resolution, and rendering.

## Package layout

The root [Package.swift](../Package.swift) declares the `ReactiveCharacterKit` library and its test target, with Swift 6 language mode and iOS 16/macOS 13 deployment targets. It has no third-party Swift package dependencies. [Preview](../Tools/Preview/Package.swift), [HostDemo](../Tools/HostDemo/Package.swift), and [Benchmarks](../Tools/Benchmarks/Package.swift) are separate local consumers of the root product; none is part of the library product.

## Data flow and ownership

```text
host event
  → validated contract value
  → ReactiveCharacter.reduce / act
  → receipt: stateAfter + effects + disposition
  → host commits state and runs effects
  → observed result event
  → presentation session samples CharacterPose
  → appearance/anatomy builds a Scene
  → SVG or Apple renderer consumes the Scene
```

| Boundary | Owner | Source |
|---|---|---|
| Semantic state and event transition | Host stores state; reducer computes the next value and requested effects | [Contract](../Sources/ReactiveCharacterKit/Contract/CharacterContract.swift), [Reducer](../Sources/ReactiveCharacterKit/Decision/CharacterReducer.swift), [Action receipt](../Sources/ReactiveCharacterKit/Presentation/CharacterActionPresentation.swift) |
| Timers and external effects | Host schedules and cancels work and applies effects; the reducer rejects stale callbacks by identity | [Effect plan](../Sources/ReactiveCharacterKit/Decision/CharacterControl.swift), [Reducer](../Sources/ReactiveCharacterKit/Decision/CharacterReducer.swift) |
| Presentation time and handoff | `CharacterPresentationSession` samples pose from state, clock values, and presentation configuration | [Presentation session](../Sources/ReactiveCharacterKit/Presentation/CharacterPresentation.swift), [Pose](../Sources/ReactiveCharacterKit/Presentation/CharacterPresentationPolicy.swift) |
| Appearance and anatomy | A theme or art direction selects shared pose projections, parts, colors, and registered assets | [Theme](../Sources/ReactiveCharacterKit/Appearance/CharacterTheme.swift), [Anatomy selection](../Sources/ReactiveCharacterKit/Appearance/CharacterAnatomy.swift) |
| Scene order and validation | Scene compilation publishes ordered nodes after geometry and identity checks | [Scene compiler](../Sources/ReactiveCharacterKit/Scene/Compilation/CharacterSceneCompiler.swift), [Scene validation](../Sources/ReactiveCharacterKit/Scene/Compilation/CharacterSceneValidation.swift) |
| Output | SVG and Apple renderers consume the compiled scene; caller owns file output and sharing | [SVG renderer](../Sources/ReactiveCharacterKit/Rendering/SVG/CharacterSVGRenderer.swift), [Canvas renderer](../Sources/ReactiveCharacterKit/Rendering/Apple/CharacterSceneCanvas.swift), [PNG renderer](../Sources/ReactiveCharacterKit/Rendering/Apple/CharacterScenePNGRenderer.swift) |

Scene construction does not run host effects or write files. Rendering does not change semantic state. The SwiftUI wrapper owns a presentation session for display sampling, while the host continues to own the state passed to the view; system and host Reduce Motion preferences are combined in the timeline adapter ([view](../Sources/ReactiveCharacterKit/UI/ReactiveCharacterView.swift), [timeline](../Sources/ReactiveCharacterKit/UI/CharacterTimelineView.swift)).

## Appearance and motion boundaries

An appearance chooses art, colors, components and default motion; it does not own
events, task state or a second clock. Shared pose and scene types allow renderers to
reuse behavior without forcing every artwork family to use the same geometry. The
minimal and portrait families use vector geometry; SEMI combines registered textures
with vector features; reference mascots use authored image layers.
The single Norwegian cat uses the GIF pipeline described below.

The session keeps layer clocks across parameter-only updates. Voice amplitude retargets over 100 ms from the currently presented value. Task-progress gaze uses the existing gaze transition identity; explicit attention keeps ownership until its existing deadline. These display transitions do not delay semantic state or create a second task state. A semantic performance handoff samples the visible pose before clearing the prior scalar transition, so the newest voice state can take over. Reduce Motion applies the target immediately. Raw `ReactiveCharacter.pose` sampling remains deterministic and unsmoothed.

## Authored emotion clips

`ReactiveCharacterGIFView(state:)` composes authored emotion clips and live input.
The existing reducer remains the only semantic state writer. `CharacterGIFPresentation`
coordinates `CharacterGIFPlayback` and the existing `CharacterPresentationSession`
using one monotonic time provider. Its live pose projection omits emotion geometry
because the authored GIF owns that geometry. Communication, attention, activity and
action clocks remain intact. Voice/gaze updates do not restart the authored clip;
a finished clip returns to neutral while ongoing live input continues.

`CharacterGIFRig` performs bounded texture articulation: it tracks the green iris and
pink nose landmarks in each frame, warps only the eye interiors for gaze, and registers
mouth patches from the existing emotion clips and per-eye blink patches from calm trust.
Anger keeps its fangs, surprise and fatigue use round openings, and distressed
expressions use the frowning source instead of a joyful mouth. A view retains only
the currently selected speech texture pair. Speech styling eases through the common
neutral boundary; it does not change the GIF clock or add semantic state. Mouth activation
crossfades over 120 ms; the shared pose session smooths amplitude changes. Listening
is silent. Whole-character action transforms reuse the shared pose. The host still
executes animation completion effects and supplies observed lifecycle events.

`CharacterGIFSet` holds immutable compressed sources. Each view lazily retains its
own rig and one-clip frame cache, so several characters do not evict one another's
frames. No extra raster assets are required. Reduce Motion uses a static authored
expression, suppresses action travel and ambient motion, and still responds to explicit
input and completion deadlines. Inactive scenes pause rendering. Resource tests retain
the common canvas and exact neutral boundary contract for all twelve files.

## SEMI within the shared pipeline

`CharacterTheme.semi` selects `CharacterAnatomy.semiDocumentCat`. The SEMI drawing consumes the existing `CharacterPose` channels for emotion, gaze, blink, communication, writing, and one-shot motion. It adds no separate semantic state or animation clock. The six registered textures are loaded through the package resource boundary; face features and document articulation remain scene geometry ([SEMI drawing](../Sources/ReactiveCharacterKit/Scene/Anatomy/SEMI/CharacterSEMIDrawing.swift), [resource lookup](../Sources/ReactiveCharacterKit/ResourceIO/CharacterImageResources.swift), [asset notes](../Artwork/SEMI/README.md)).

The internal expression rig resolves coordinated eye, mouth, ear, paw, and body cues once for each frame. The mouth is exclusively unfilled stroke paths: a connected philtrum and two rounded lip branches. SEMI never renders a cavity, tongue or filled muzzle, including voice and surprise. At rest, three short shafts per cheek retain a distinct fan, a shorter upper strand and tiny gravity curves. Ordinary acting changes direction, reach and staggered sway while the shafts stay extended. Strong distress and explicit recoil/bounce/shake impulses may compress or ripple them; generic body energy and circular surprise cannot trigger that branch.

The sampled detail payload uses existing presentation clocks and vector handoff blending. Typed artDirection pose/session configuration enables gentle SEMI idle sway; legacy overloads retain the standard neutral hold. Reduce Motion, zero expressiveness and inactive SwiftUI scenes stop the appropriate motion. Anatomy owns geometry projection, not clocks or semantic events. Ordinary collision fitting translates, tilts or shortens the complete shaft against sampled eye contours and the document, preserving connected tangents rather than pushing individual controls into hooks. Regions and samples are reused within the frame. Special curved acting retains hull guards. Unblinked eye geometry prevents blink from moving whiskers. Textures remain separate from live facial geometry.

## Input and resource budgets

Untrusted design JSON enters through `CharacterDesign.decode(_:)` and reference JSON through `CharacterReferenceDocument(data:)`. Those Data routes validate raw byte limits, nesting, duplicate members, and schema values. Generic `Codable` decoding is intended for trusted model exchange and cannot enforce all raw-document rules. Callers must choose the Data factories when importing user files.

Validated art directions accept at most 16 image accessories, including programmatically constructed packs. Overlay accent counts and render dimensions have their own existing limits. The SwiftUI `CharacterAccessoryOverlay` array contains caller-owned `Image` values; the host owns its count and decoded image-memory budget. It is a distinct boundary from scene image accessories and is documented rather than silently truncated.

Scene compilation validates geometry, node identities, and painter order. Renderers consume the published order; they do not reorder the semantic scene. Resource I/O stays in the resource/renderer boundary and preserves lookup or decode errors. No automatic fallback artwork or hidden file write is added to scene construction.

## Platform boundary

The root manifest declares iOS 16 and macOS 13. Pure state, presentation, geometry, scene, and SVG code is separate from SwiftUI Canvas and ImageIO-backed PNG code. Apple SDK compilation is required to validate those platform-specific paths; a portable scene or SVG check does not establish VoiceOver behavior, pixel identity between renderers, or native performance.
