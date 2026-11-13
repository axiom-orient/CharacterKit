# CharacterKit

CharacterKit is a Swift SDK for presenting host-observed work, emotion, communication, attention, and animation through an expressive character. The host owns application state, timers, external effects, persistence, and localized status text; the SDK reduces input events and renders the resulting state.

Repository: [github.com/axiom-orient/CharacterKit](https://github.com/axiom-orient/CharacterKit). The Swift package is named `CharacterKit`; its library product and import module are `ReactiveCharacterKit`.

## Requirements and integration

The package uses Swift tools and language mode 6. Its declared deployment targets are iOS 16 and macOS 13. The library has no third-party runtime package dependencies. Python and FFmpeg are only used by optional artwork preparation tools.

Add the current development branch to a Swift package:

```swift
dependencies: [
  .package(url: "https://github.com/axiom-orient/CharacterKit.git", branch: "main"),
],
targets: [
  .target(
    name: "MyApp",
    dependencies: [.product(name: "ReactiveCharacterKit", package: "CharacterKit")]
  ),
]
```

`main` can change; pin a tested revision for reproducible builds. The existing `1.0.0`
tag predates SEMI and does not contain the functionality described on this branch.
No newer version tag is implied by these instructions.

Alternatively, clone the repository and add its checkout as a local Swift package:

```sh
git clone https://github.com/axiom-orient/CharacterKit.git
```

For a host repository beside the `CharacterKit` checkout, its `Package.swift` can use:

```swift
// Add these entries inside Package(...).
dependencies: [
  .package(path: "../CharacterKit"),
],
targets: [
  .target(
    name: "MyApp",
    dependencies: [
      .product(name: "ReactiveCharacterKit", package: "CharacterKit"),
    ]
  ),
]
```

The host commits each receipt's `stateAfter`, cancels the listed obsolete animation timers, executes requested effects, and sends later observations back as events. An accepted reducer receipt does not mean an external operation has completed.

```swift
import ReactiveCharacterKit

let taskID = try CharacterTaskID(validating: "summary-42")
var state = CharacterState.idle
let receipt = ReactiveCharacter.act(
  state: state,
  event: .agentStarted(taskID: taskID)
)
state = receipt.stateAfter
let scheduledIDs: [CharacterAnimationID] = []
let plan = receipt.effectPlan(scheduledAnimationIDs: scheduledIDs)
// The host cancels plan.animationIDsToCancel, performs plan.effects,
// and turns observed results into the next CharacterEvent.
```

For an Apple UI, `ReactiveCharacterView` consumes the same host state. Supply a localized status value from the host so the character's appearance does not stand in for the task result.

```swift
import SwiftUI
import ReactiveCharacterKit

struct CharacterBadge: View {
  let state: CharacterState
  let statusText: String

  var body: some View {
    ReactiveCharacterView(
      state: state,
      theme: .semi,
      accessibilityLabel: "세미",
      accessibilityValue: statusText
    )
    .frame(width: 200, height: 200)
  }
}
```

Public API additions and input-budget changes are listed in [client migration](CHANGELOG.md).

`CharacterTheme` provides `.black`, `.white`, `.arcade`, `.cat`, and `.semi`.
Additional art directions include `.catSimple2D`, `.catNorwegianForest`, and portrait
styles. The host can replace the theme without replacing its semantic state. For SEMI,
pass `.semi` explicitly; the default `ReactiveCharacterView(state:)` uses Black.

For the Norwegian Forest Cat's twelve authored emotion animations, use the bundled
GIF view. It consumes the same host-owned state as the procedural renderer:

```swift
ReactiveCharacterGIFView(
  state: state,
  playbackTrigger: expressionSequence,
  accessibilityLabel: "숲냥이",
  accessibilityValue: localizedStatus
)
.frame(width: 160, height: 160)
```

`expressionSequence` is a host-owned integer; increment it to replay the same emotion.
Changing emotion starts a new clip through the shared neutral pose. Reduce Motion
shows a still expression for the clip's duration and then returns to neutral.
Speech levels articulate the mouth, attention steers the irises, and action events
use the shared pose session. These live channels continue after an emotion returns
to neutral; ordinary voice or gaze updates never restart the GIF. Listening input
does not articulate the mouth. The `emotion:` initializer remains available for
emotion-only callers. `ReactiveCharacterView` remains the renderer for basic and human characters.
See [GIF asset preparation](Tools/Norwegian/README.md) for the source and build contract.

The older Norwegian reference coats retain their authored eye textures and use restrained
motion. Their current source art has no closed-eye layers, so blink events do not
visually close those eyes. The hero source is 431×373 pixels and the other coats are
about 220×232 pixels. See [appearance boundaries](docs/ARCHITECTURE.md#appearance-and-motion-boundaries).

The short-lived SEMI-only `main` revision used SEMI as its implicit view and pose
configuration. When moving from that revision, select `theme: .semi` in the view and
use the `artDirection: .semiDocumentCat` pose or session overload to preserve SEMI's
idle motion. `CharacterSceneBuilder.scene(pose:width:height:)` remains available as
a SEMI convenience; pass an art direction to render a different appearance.

## Build and review

From the package root, run the shared test suite and release build with a Swift 6 toolchain:

```sh
# Use when `swift` resolves to the intended Swift 6 toolchain (for example, portable checks on Linux).
swift test --jobs 4
swift build -c release --jobs 4

# On Apple platforms, select the full Xcode toolchain for SwiftUI and native-renderer checks.
# A standalone Command Line Tools Swift may select a different SwiftUI macro/toolchain environment.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --jobs 4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --jobs 4
```

The local preview consumes the public package API and exports real SDK frames. Give it a new or empty output directory whose parent already exists. It rejects a nonempty directory, attempts to remove only files tracked by a failed export, and never recursively deletes an output directory.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run \
  --package-path Tools/Preview CharacterPreview --output /tmp/characterkit-review
python3 Tools/Preview/make_gallery.py /tmp/characterkit-review
```

Open the resulting `index.html` in a permitted local browser. The gallery lets reviewers compare appearances and captured motion samples. Its frame replay does not measure native performance or validate VoiceOver behavior. For native PNG export, run Preview on macOS:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run \
  --package-path Tools/Preview CharacterPreview \
  --output /tmp/characterkit-native --native-png
```

For a native macOS consumer with emotion, speech, task lifecycle, animation, and Reduce Motion controls, use the project's Run action or:

```sh
./script/build_and_run.sh
./script/build_and_run.sh --build-only
```

The demo exposes the bundled appearances, including the four Norwegian coats and
portrait variants, through the public art-direction API. It injects observed events
into the SDK; it does not run an agent or a network operation. Its host owns semantic
state and animation-end tasks, cancels obsolete tasks, and sends completion
observations back through the reducer.

The separate benchmark measures warm release-build pose/scene computation and offline SVG/PNG export:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run \
  -c release --package-path Tools/Benchmarks CharacterBenchmark --iterations 1000
```

See [architecture](docs/ARCHITECTURE.md) for ownership and input boundaries, and [client migration](CHANGELOG.md) for public contract changes.

## SEMI expression review

SEMI uses closed line art for the mouth, including speech and surprise. The nose and lip branches stay connected. At rest, three short, nearly straight whiskers fan from each cheek; the upper strand is shorter and each has a tiny gravity curve. Ordinary emotion and communication animate these extended shafts through direction, reach and staggered sway. Strong distress and explicit recoil/bounce/shake cues may retract or ripple them. Laughs, curious leans and surprise do not trigger crumpling. Reduce Motion and zero expressiveness stop secondary motion.

The typed `ReactiveCharacter.pose(state:elapsed:artDirection:)` sampler and `CharacterPresentationSession(state:at:artDirection:)` select SEMI's gentle idle sway. Existing sampler and session overloads preserve the standard neutral hold. SwiftUI's artDirection path selects the same style and pauses with an inactive scene. [Cat face research](docs/CAT_BODY_LANGUAGE.md) separates observed feline cues from the chosen cartoon acting.

Review images are generated locally by Preview and excluded from source archives. The current SEMI is a document-holding mascot; a quadruped body, joints and foot-contact motion are not implemented. The [behavior guide](docs/CAT_BODY_LANGUAGE.md) defines the intended next scope.

## SEMI artwork authoring

The runtime SEMI textures are six registered 512×512 PNG layers. The preview image is the authoring input for the head, paws, and tail. The two final registered ear layers are retained as explicit authoring sources because their original mask and color-processing recipe is unavailable. The tool copies those PNGs directly. See [Artwork/SEMI/README.md](Artwork/SEMI/README.md).

Install the pinned Python authoring dependencies in a virtual environment before regenerating resources:

```sh
python3 -m venv /tmp/characterkit-artwork
/tmp/characterkit-artwork/bin/python -m pip install -r Tools/SEMI/requirements.txt
/tmp/characterkit-artwork/bin/python Tools/SEMI/prepare_assets.py \
  --output /tmp/characterkit-semi-review
```

The pinned authoring environment is recorded in [Artwork/SEMI/README.md](Artwork/SEMI/README.md). Use an explicit review output directory; the default writes to the bundled SEMI resources.

## Validation and distribution

CI is configured in [.github/workflows/ci.yml](.github/workflows/ci.yml). Check its
result for the revision being used. Minimum-OS runtime, physical iOS, VoiceOver and
interactive frame/energy performance require separate verification; simulator
compilation and generated frames do not establish those results.

The repository has no separate distribution LICENSE grant. Retained artwork origins and authoring inputs are recorded in [Artwork/PROVENANCE.md](Artwork/PROVENANCE.md).

Copyright © Axient Inc.
