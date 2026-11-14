# Chat and speech integration

Add the `ReactiveCharacterKit` and optional `CharacterChat` SwiftPM products. The
host supplies messages and audio; the character SDK remains a pure state/presentation
library. No chat-provider key or microphone permission is needed for the bundled demo.

## Run the real app

Run `./script/build_and_run.sh` or use the Codex **Run** action. The native chat studio
opens with the Norwegian GIF cat and a live Simple 2D comparison.

- Enter dialogue and choose **대사 말하기**. Korean and English use the installed system voice.
- Choose a sample to apply one of twelve explicit emotions. **화남 같이 보기** uses
  the same dialogue, emotion and speech input for the Norwegian and Simple 2D cats.
- **12감정 이어서 보기** plays every sample. **시연 저장** additionally captures native
  view frames and an evidence manifest in a new temporary folder shown in the app.
- Change gaze or add an action during playback. A new message replaces the previous
  speech; **중지** cancels synthesis/playback and returns to neutral.
- Turn off **음성 포함** for a silent preview with estimated reading timing.
- Choose any of the thirteen appearances in the character picker. **13종 비교** opens
  the existing SDK showcase; **입력 검사기** exposes low-level host events.

## Message meaning belongs to the host

```swift
import CharacterChat
import ReactiveCharacterKit

// Recommended when your chat service/model already supplies expression metadata.
let plan = try CharacterChatPlan(text: reply, emotion: .emotion(.gratitude))

// Optional local demo policy. Unknown content remains neutral.
let inferred = try CharacterChatPlan(text: reply, emotion: .automatic)
```

Plans contain trimmed sentence text, original UTF-16 ranges, emotion and an optional
one-shot action. The input limit is 512 grapheme clusters. Use `cueIndex(atUTF16Offset:)`
to change expression when playback reaches a sentence. Increment the GIF replay trigger
once per new cue, including repeated emotions. Do not increment it on audio/viseme updates.

The automatic Korean/English rules cover common direct expressions, emoji and several
negations. They do not reliably understand sarcasm, quotation, complex negation or every
language. Production chat should provide validated expression metadata from its own
conversation system; explicit emotion and `.neutral` always bypass local inference.

## Speech timing and mouth geometry

`CharacterSpeechTrack` accepts a message, duration, normalized measured 20ms energy
windows and word timestamps. Word ranges must match complete grapheme boundaries;
invalid samples, out-of-range offsets and tracks over 120 seconds are rejected.

```swift
// Use your audio player's actual timeline, rather than a wall-clock timer.
let frame = track.frame(at: audioPlayer.currentTime)
state = ReactiveCharacter.reduce(state: state, event: .voiceLevelChanged(frame.level)).state

ReactiveCharacterGIFView(state: state, playbackTrigger: cueSequence)
  .characterSpeechArticulation(frame.articulation)

// The same modifier works on ReactiveCharacterView for every basic/human appearance.
```

The host sends `.voiceStarted` before audio playback, `.emotionChanged` and
`.animationStarted` when a cue changes, and `.communicationEnded` plus
`.emotionChanged(nil)` on finish/cancel. Execute reducer effects and feed observed action
completion back through `.animationEnded(id:)`. Keep attention independent so gaze
controls continue working during speech. Clear the articulation input with `nil` on stop.

The SwiftUI modifier smooths mouth retargets over 45ms without resetting emotion/action
clocks. It overrides open amount during speech (silence and closed consonants can close
an otherwise open emotional mouth), retains emotional curvature, and applies only during
chat/voice output. SEMI retains its established closed-line mouth style. Custom scene
consumers can use `pose.applyingSpeechArticulation(frame.articulation)` during output.

The native host generates a temporary PCM file with Apple's
[buffer/marker synthesis API](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:tomarkercallback:)).
It uses measured audio energy and word offsets, then samples using the player's
[actual playback time](https://developer.apple.com/documentation/avfaudio/avaudioplayer/currenttime).
The installed Korean voice provides word markers, not phonemes. Vowel shapes and
within-word character timing are spelling estimates; this is not phoneme-perfect lip sync.
Providers with precise viseme timing can feed `CharacterSpeechArticulation` directly.

The host owns audio lifetime, generation IDs, timeout, cancellation and temporary-file
cleanup. A stale synthesis callback cannot start an old message or end a newer one.
The SDK stores no chat history/audio. The demo retains at most forty messages in memory;
review images are written only when **시연 저장** is selected. Captures prove functional
rendering, not frame performance or exact phoneme alignment.
