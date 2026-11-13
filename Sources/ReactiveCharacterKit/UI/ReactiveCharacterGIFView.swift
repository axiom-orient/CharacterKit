#if os(iOS) || os(macOS)
  import SwiftUI

  /// Authored Norwegian emotion clips composed with live speech, gaze and action poses.
  @available(iOS 16.0, macOS 13.0, *)
  public struct ReactiveCharacterGIFView: View {
    private let state: CharacterState
    private let playbackTrigger: Int
    private let accessibilityLabel: String
    private let accessibilityValue: String?

    public init(state: CharacterState, playbackTrigger: Int = 0,
      accessibilityLabel: String = "Norwegian Forest Cat", accessibilityValue: String? = nil) {
      self.state = state; self.playbackTrigger = playbackTrigger
      self.accessibilityLabel = accessibilityLabel; self.accessibilityValue = accessibilityValue
    }

    /// Compatibility convenience for callers that only need authored emotions.
    public init(emotion: CharacterEmotion?, playbackTrigger: Int = 0,
      accessibilityLabel: String = "Norwegian Forest Cat", accessibilityValue: String? = nil) {
      self.init(state: ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state,
        playbackTrigger: playbackTrigger, accessibilityLabel: accessibilityLabel,
        accessibilityValue: accessibilityValue)
    }

    public var body: some View {
      switch CharacterGIFSet.norwegianForest {
      case .success(let gifs):
        CharacterGIFPlayer(state: state, gifs: gifs, accessibilityLabel: accessibilityLabel,
          accessibilityValue: accessibilityValue, playbackTrigger: playbackTrigger)
      case .failure:
        Text("Character artwork unavailable").accessibilityIdentifier("character.gif.resourceError")
      }
    }
  }

  @MainActor
  private final class CharacterGIFRenderResources: ObservableObject {
    let rig: Result<CharacterGIFRig, Error>
    let frames = CharacterGIFFrameCache()
    init(gifs: CharacterGIFSet) { rig = Result { try CharacterGIFRig(gifs: gifs) } }
  }

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterGIFPlayer: View {
    private struct Input: Equatable {
      let state: CharacterState
      let trigger: Int
      let reduceMotion: Bool
    }
    private struct EmotionInput: Equatable {
      let emotion: CharacterEmotion?
      let trigger: Int
    }
    let state: CharacterState
    let gifs: CharacterGIFSet
    let accessibilityLabel: String
    let accessibilityValue: String?
    let playbackTrigger: Int
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.characterReducedMotion) private var hostReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: CharacterGIFPresentation
    @StateObject private var resources: CharacterGIFRenderResources
    @State private var reducedSampleTime: Double
    @State private var previousTrigger: Int

    init(state: CharacterState, gifs: CharacterGIFSet, accessibilityLabel: String,
      accessibilityValue: String?, playbackTrigger: Int = 0) {
      self.state = state; self.gifs = gifs; self.accessibilityLabel = accessibilityLabel
      self.accessibilityValue = accessibilityValue; self.playbackTrigger = playbackTrigger
      let now = CharacterPresentationTime.now
      _presentation = State(initialValue: CharacterGIFPresentation(state: state, at: now))
      _resources = StateObject(wrappedValue: CharacterGIFRenderResources(gifs: gifs))
      _reducedSampleTime = State(initialValue: now)
      _previousTrigger = State(initialValue: playbackTrigger)
    }

    private var reduceMotion: Bool { systemReduceMotion || hostReduceMotion }

    var body: some View {
      Group {
        if reduceMotion {
          frame(at: reducedSampleTime)
        } else {
          TimelineView(.animation(minimumInterval: 1.0 / 24, paused: scenePhase != .active)) { _ in
            frame(at: CharacterPresentationTime.now)
          }
        }
      }
      .onChange(of: Input(state: state, trigger: playbackTrigger, reduceMotion: reduceMotion)) { input in
        let now = CharacterPresentationTime.now
        presentation.update(state: input.state, at: now, reduceMotion: input.reduceMotion,
          replay: input.trigger != previousTrigger, duration: gifs.duration(for:))
        previousTrigger = input.trigger
        reducedSampleTime = now
      }
      .task(id: EmotionInput(emotion: state.emotion, trigger: playbackTrigger)) {
        do {
          try await Task.sleep(nanoseconds: UInt64(((state.emotion.map(gifs.duration(for:)) ?? 0)
            + 0.2) * 1_000_000_000))
          guard !Task.isCancelled else { return }
          reducedSampleTime = CharacterPresentationTime.now
        } catch {}
      }
      .task(id: state.animation) {
        guard let animation = state.animation else { return }
        do {
          let delay = animation.animation.duration
            + CharacterTransitionProfile.soft.maximumReturnDuration
            + CharacterTransitionProfile.soft.neutralHoldDuration
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          guard !Task.isCancelled else { return }
          reducedSampleTime = CharacterPresentationTime.now
        } catch {}
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(accessibilityLabel))
      .accessibilityValue(Text(accessibilityValue ?? status))
    }

    private var status: String {
      var parts: [String] = []
      if let emotion = state.emotion { parts.append(emotion.rawValue) }
      switch state.communication {
      case .voice: parts.append("Speaking")
      case .chat: parts.append("Chatting")
      case .listening: parts.append("Listening")
      case .silent: break
      }
      if let animation = state.animation { parts.append(animation.animation.rawValue) }
      return parts.isEmpty ? "Neutral" : parts.joined(separator: ", ")
    }

    @ViewBuilder private func frame(at time: Double) -> some View {
      let sample = presentation.sample(at: time, reduceMotion: reduceMotion, duration: gifs.duration(for:))
      let result = Result {
        let renderer = try resources.rig.get()
        let image: CGImage
        if let clip = sample.emotion,
          let authored = try gifs.image(for: clip.emotion, elapsed: clip.elapsed,
            reduceMotion: reduceMotion, cache: resources.frames) {
          image = reduceMotion ? authored : blend(authored, opacity: clip.opacity)
        } else { image = gifs.neutral }
        return renderer.render(image, pose: sample.pose, speechWeight: sample.speechWeight)
      }
      switch result {
      case .success(let image):
        GeometryReader { geometry in
          let side = min(geometry.size.width, geometry.size.height)
          let surface = sample.pose.surface
          Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .scaleEffect(x: surface.scaleX, y: surface.scaleY)
            .rotationEffect(.radians(surface.angle))
            .offset(x: surface.offsetX * side, y: surface.offsetY * side)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
      case .failure:
        Text("Character animation unavailable").accessibilityIdentifier("character.gif.error")
      }
    }

    private func blend(_ image: CGImage, opacity: Double) -> CGImage {
      guard opacity < 0.999 else { return image }
      guard opacity > 0.001 else { return gifs.neutral }
      let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      context.setAlpha(1 - opacity); context.draw(gifs.neutral, in: rect)
      context.setBlendMode(.plusLighter); context.setAlpha(opacity); context.draw(image, in: rect)
      return context.makeImage()!
    }
  }
#endif
