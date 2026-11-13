#if os(iOS) || os(macOS)
  import SwiftUI

  /// A bundled Norwegian Forest Cat that plays each emotion once and returns to neutral.
  /// For live gaze, speech articulation and action events, use `ReactiveCharacterView`.
  @available(iOS 16.0, macOS 13.0, *)
  public struct ReactiveCharacterGIFView: View {
    private let emotion: CharacterEmotion?
    private let playbackTrigger: Int
    private let accessibilityLabel: String
    private let accessibilityValue: String?

    /// Increment `playbackTrigger` to replay an unchanged emotion.
    public init(
      emotion: CharacterEmotion?, playbackTrigger: Int = 0,
      accessibilityLabel: String = "Norwegian Forest Cat", accessibilityValue: String? = nil
    ) {
      self.emotion = emotion
      self.playbackTrigger = playbackTrigger
      self.accessibilityLabel = accessibilityLabel
      self.accessibilityValue = accessibilityValue
    }

    public var body: some View {
      switch CharacterGIFSet.norwegianForest {
      case .success(let gifs):
        CharacterGIFPlayer(emotion: emotion, gifs: gifs,
          accessibilityLabel: accessibilityLabel, accessibilityValue: accessibilityValue,
          playbackTrigger: playbackTrigger)
      case .failure:
        Text("Character artwork unavailable")
          .accessibilityIdentifier("character.gif.resourceError")
      }
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterGIFPlayer: View {
    private let emotion: CharacterEmotion?
    private let gifs: CharacterGIFSet
    private let accessibilityLabel: String
    private let accessibilityValue: String?
    private let playbackTrigger: Int
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.characterReducedMotion) private var hostReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback: CharacterGIFPlayback
    @State private var isAnimating: Bool

    private struct PlaybackIdentity: Equatable {
      let emotion: CharacterEmotion?
      let trigger: Int
    }

    /// Increment `playbackTrigger` to replay an unchanged emotion.
    init(
      emotion: CharacterEmotion?, gifs: CharacterGIFSet,
      accessibilityLabel: String, accessibilityValue: String?, playbackTrigger: Int = 0
    ) {
      self.emotion = emotion
      self.gifs = gifs
      self.accessibilityLabel = accessibilityLabel
      self.accessibilityValue = accessibilityValue
      self.playbackTrigger = playbackTrigger
      _playback = State(initialValue: CharacterGIFPlayback(
        emotion: emotion, at: CharacterPresentationTime.now))
      _isAnimating = State(initialValue: emotion != nil)
    }

    private var reduceMotion: Bool { systemReduceMotion || hostReduceMotion }

    var body: some View {
      Group {
        if isAnimating {
          TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0,
            paused: scenePhase != .active)) { _ in
            frame(at: CharacterPresentationTime.now)
          }
        } else {
          // Direct rendering also avoids a paused TimelineView retaining its last frame on iOS 16.
          imageView(gifs.neutral)
        }
      }
      .onChange(of: emotion) { emotion in
        playback.update(emotion: emotion, at: CharacterPresentationTime.now,
          duration: gifs.duration(for:))
        isAnimating = true
      }
      .onChange(of: playbackTrigger) { _ in
        playback.update(emotion: emotion, at: CharacterPresentationTime.now,
          duration: gifs.duration(for:), force: true)
        isAnimating = true
      }
      .task(id: PlaybackIdentity(emotion: emotion, trigger: playbackTrigger)) {
        // Stop scheduling frames once the one-shot clip and any handoff have ended.
        let seconds = (emotion.map(gifs.duration(for:)) ?? 0) + 0.18
        do {
          try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
          guard !Task.isCancelled else { return }
          isAnimating = false
        } catch {
          // A new emotion replaces this task and schedules its own completion.
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(accessibilityLabel))
      .accessibilityValue(Text(accessibilityValue ?? (isAnimating ? emotion?.rawValue ?? "Neutral" : "Neutral")))
    }

    @ViewBuilder
    private func frame(at time: Double) -> some View {
      let sample = playback.sample(at: time, duration: gifs.duration(for:))
      let result = Result {
        try sample.flatMap { try gifs.image(for: $0.emotion, elapsed: $0.elapsed,
          reduceMotion: reduceMotion) }
      }
      switch result {
      case .success(let image):
        if let image, let sample {
          let opacity = reduceMotion ? 1.0 : sample.opacity
          ZStack {
            imageView(gifs.neutral).opacity(1 - opacity)
            imageView(image).opacity(opacity).blendMode(.plusLighter)
          }
          .compositingGroup()
        } else {
          imageView(gifs.neutral)
        }
      case .failure:
        Text("Character animation unavailable")
          .accessibilityIdentifier("character.gif.error")
      }
    }

    private func imageView(_ image: CGImage) -> some View {
      Image(decorative: image, scale: 1)
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
  }
#endif
