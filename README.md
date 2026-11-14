# CharacterKit

A Swift 6 character-rendering SDK for iOS 16+ and macOS 13+. It combines host-owned
state, independent emotion/speech/gaze/action channels, and vector or authored artwork.

The interactive macOS app is maintained separately in
[CharacterStudio](https://github.com/axiom-orient/CharacterStudio).

## Install

```swift
.package(url: "https://github.com/axiom-orient/CharacterKit.git", from: "2.0.1")
```

Add the `ReactiveCharacterKit` product to your target.

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

The host stores state and executes returned effects. Feed observed completion back
through the reducer, including `.animationEnded(id:)` and task-result events. The SDK
rejects stale identities; it never starts a chat request, audio recording or agent task.

## Appearances and speech

`CharacterTheme` includes `.black`, `.white`, `.arcade`, `.cat` and `.semi`. Black, White and Arcade configure the same headset anatomy; they are palette choices,
not separate characters. Additional art directions include `.catSimple2D` and portrait
styles. `CharacterPortraitStyle` configures hair, accessories, eyewear and supported
viewpoints on the shared portrait system. The default view uses Black.

Use `ReactiveCharacterGIFView(state:playbackTrigger:)` for the single Norwegian cat.
Its twelve emotion clips start/end on identical neutral pixels. Increment the trigger
once per expression cue to replay the same emotion. Voice, gaze and action updates
continue independently without restarting a clip.

For timed speech, send `.voiceStarted` and measured `.voiceLevelChanged` events, then
apply `.characterSpeechArticulation(frame)` to either view. `frame` is a validated
`CharacterSpeechArticulation` containing openness/width. Clear it with `nil` and send
`.communicationEnded` when output ends. The host owns speech synthesis, text analysis
and timing; CharacterStudio demonstrates those adapters.

`.characterReduceMotion(true)` adds a host preference to the system preference.
`.characterIncludesBackground(false)` selects a transparent stage. SEMI deliberately
uses closed-line mouth artwork, including speech and surprise.

## Rendering and contracts

`ReactiveCharacter.pose` and `CharacterPresentationSession` support custom renderers.
`CharacterSceneBuilder`, `CharacterSVGRenderer` and `CharacterScenePNGRenderer` export
the same scene representation. File storage belongs to the caller.

Use `CharacterDesign.decode(_:)` and `CharacterReferenceDocument(data:)` for untrusted
JSON; these enforce raw-input budgets that generic Codable decoding cannot provide.
See [architecture](docs/ARCHITECTURE.md) and [migration notes](CHANGELOG.md).

## Validate and maintain

```sh
./script/verify.sh
./script/verify.sh --ios
```

[Artwork](Artwork/PROVENANCE.md) records sources and the SEMI/Norwegian preparation
pipelines. Only runtime resources belong to the library bundle.

Copyright © Axient Inc.
