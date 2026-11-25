# CharacterKit

Swift 6 character rendering for iOS 16+ and macOS 13+. The host owns character
state and supplies emotion, gaze, speech and action input. The interactive demo
is a separate project. [CharacterStudio](https://github.com/axiom-orient/CharacterStudio)

## Install

```swift
.package(url: "https://github.com/axiom-orient/CharacterKit.git", from: "2.1.2")
```

Add the `ReactiveCharacterKit` library product to your target.

## Display and update

```swift
import ReactiveCharacterKit
import SwiftUI

struct Companion: View {
  @State private var state = CharacterState.idle

  var body: some View {
    ReactiveCharacterView(state: state, theme: .semi)
      .frame(width: 200, height: 200)
      .onTapGesture {
        state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.joy)).state
      }
  }
}
```

Keep the returned state and execute the effects. Feed observed results such as
`.animationEnded(id:)` back through the reducer. The SDK rejects stale identities.

## Choose an appearance

- `CharacterTheme` includes the Black, White and Arcade headset palettes, Cat and SEMI. Black is the default. `CharacterArtDirection` and `CharacterPortraitStyle` expose additional variations.
- `ReactiveCharacterGIFView(state:playbackTrigger:)` plays Norwegian emotion clips. Increment the trigger once per new expression cue.
- `ReactiveCharacterView(state:fullBodyCat:)` takes a felt or crayon style, a resting pose and an optional one-shot gesture. Increment `actionTrigger` to replay a gesture. Clear the action to cancel. [Full-body cat guide](docs/FULL_BODY_CAT_2D_PLAN.md)

For timed speech, send `.voiceStarted` and `.voiceLevelChanged`, then pass measured
`CharacterSpeechArticulation` to `.characterSpeechArticulation(frame)`. Clear the
modifier value and send `.communicationEnded` when playback ends. The host supplies
the dialogue and audio timing. [State and rendering architecture](docs/ARCHITECTURE.md)

## Render and export

Use `CharacterSceneBuilder` to construct a scene for `CharacterSceneCanvas`,
`CharacterSVGRenderer` or `CharacterScenePNGRenderer`. Custom renderers can use
`ReactiveCharacter.pose` and `CharacterPresentationSession`. Use
`.characterReduceMotion(true)` for a host motion preference and
`.characterIncludesBackground(false)` for a transparent stage.

Use `CharacterDesign.decode(_:)` and `CharacterReferenceDocument(data:)` for
untrusted JSON. They validate the raw input before decoding.

## Verify

```sh
./script/verify.sh --ios
```

[Artwork sources](Artwork/PROVENANCE.md) · [Changelog and migration](CHANGELOG.md)

Copyright © Axient Inc.
