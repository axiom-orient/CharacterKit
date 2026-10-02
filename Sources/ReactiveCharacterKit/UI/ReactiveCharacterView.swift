#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  private enum CharacterRenderSource {
    case design(CharacterDesign, partColors: CharacterPartColors?)
    case artDirection(CharacterArtDirection)

    var components: CharacterComponents {
      switch self {
      case .design(let design, _): design.components
      case .artDirection(let direction): direction.components
      }
    }

    var projection: CharacterProjection {
      switch self {
      case .design(let design, _): design.projection
      case .artDirection(let direction): direction.projection
      }
    }

    var motionProfile: CharacterMotionProfile {
      switch self {
      case .design(let design, _): design.motionProfile
      case .artDirection(let direction): direction.motionProfile
      }
    }

    var transitionProfile: CharacterTransitionProfile {
      switch self {
      case .design(let design, _): design.transitionProfile
      case .artDirection(let direction): direction.transitionProfile
      }
    }

    var designFramesPerSecond: Int? {
      guard case .design(let design, _) = self else { return nil }
      return design.profile.rendering.framesPerSecond
    }

    var artDirection: CharacterArtDirection? {
      guard case .artDirection(let direction) = self else { return nil }
      return direction
    }

    var design: CharacterDesign? {
      guard case .design(let design, _) = self else { return nil }
      return design
    }
  }

  /// Dependency-free SwiftUI renderer for reducer-owned semantic state.
  @available(iOS 16.0, macOS 13.0, *)
  public struct ReactiveCharacterView: View {
    private let source: CharacterRenderSource
    private let state: CharacterState
    private let overlayAccents: [CharacterAccentPose]
    private let accessoryOverlays: [CharacterAccessoryOverlay]
    private let accessibilityLabel: String
    private let hostAccessibilityValue: String?

    /// Profile-driven vector design. Loading/validation belongs to the host, not a frame callback.
    /// Replacing a palette or layout preserves semantic state and presentation clocks.
    public init(
      state: CharacterState,
      design: CharacterDesign,
      partColors: CharacterPartColors? = nil,
      overlayAccents: [CharacterAccentPose] = [],
      accessibilityLabel: String = "Reactive character",
      accessibilityValue: String? = nil,
      accessoryOverlays: [CharacterAccessoryOverlay] = []
    ) {
      self.source = .design(design, partColors: partColors)
      self.state = state
      self.overlayAccents = overlayAccents
      self.accessoryOverlays = accessoryOverlays
      self.accessibilityLabel = accessibilityLabel
      self.hostAccessibilityValue = accessibilityValue
    }

    /// The default view uses the Black built-in appearance.
    public init(state: CharacterState) {
      self.init(state: state, artDirection: .black)
    }

    public init(
      state: CharacterState,
      artDirection: CharacterArtDirection = .black,
      overlayAccents: [CharacterAccentPose] = [],
      accessibilityLabel: String = "Reactive character",
      accessibilityValue: String? = nil,
      accessoryOverlays: [CharacterAccessoryOverlay] = []
    ) {
      self.source = .artDirection(artDirection)
      self.state = state
      self.overlayAccents = overlayAccents
      self.accessoryOverlays = accessoryOverlays
      self.accessibilityLabel = accessibilityLabel
      self.hostAccessibilityValue = accessibilityValue
    }

    /// Atomically swaps the complete visual configuration without resetting semantic state
    /// or introducing a theme-specific presentation session.
    public init(
      state: CharacterState,
      theme: CharacterTheme,
      eyeTreatment: CharacterEyeTreatment? = nil,
      mouthTreatment: CharacterMouthTreatment? = nil,
      partColors: CharacterPartColors? = nil,
      overlayAccents: [CharacterAccentPose] = [],
      accessibilityLabel: String = "Reactive character",
      accessibilityValue: String? = nil,
      accessoryOverlays: [CharacterAccessoryOverlay] = []
    ) {
      let direction = theme.configured(
        eyes: eyeTreatment, mouth: mouthTreatment, partColors: partColors)
      self.init(
        state: state, artDirection: direction, overlayAccents: overlayAccents,
        accessibilityLabel: accessibilityLabel, accessibilityValue: accessibilityValue,
        accessoryOverlays: accessoryOverlays)
    }

    public var body: some View {
      CharacterTimelineView(
        source: source, state: state, overlayAccents: overlayAccents,
        accessoryOverlays: accessoryOverlays
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text(accessibilityLabel))
      .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
      if let hostAccessibilityValue {
        return hostAccessibilityValue
      }
      var values = [activityAccessibilityValue]
      if let emotion = state.emotion {
        values.append("Emotion: \(emotion.rawValue)")
      }
      if let animation = state.animation {
        values.append("Animation: \(animation.animation.rawValue)")
      }
      if source.components.contains(.accessories) {
        for accessory in source.artDirection?.assets.accessories ?? [] where accessory.opacity > 0 {
          if let label = accessory.accessibilityLabel, !label.isEmpty {
            values.append("Accessory: \(label)")
          }
        }
        for accessory in source.design?.accessories ?? [] where accessory.placement.opacity > 0 {
          values.append("Accessory: \(accessory.label)")
        }
        for overlay in accessoryOverlays where overlay.placement.opacity > 0 {
          if let label = overlay.accessibilityLabel, !label.isEmpty {
            values.append("Accessory: \(label)")
          }
        }
      }
      switch state.communication {
      case .silent:
        break
      case .chat:
        values.append("Chatting")
      case .listening(let level):
        values.append("Listening, input level \(Int((level.value * 100).rounded())) percent")
      case .voice:
        values.append("Speaking")
      }
      return values.joined(separator: ", ")
    }

    private var activityAccessibilityValue: String {
      switch state.activity {
      case .idle:
        "Idle"
      case .userWriting:
        "User is writing"
      case .agentThinking:
        "Agent is thinking"
      case .agentWriting(_, let progress):
        "Agent is writing, \(Int((progress.value * 100).rounded())) percent"
      case .agentCancelling:
        "Agent cancellation requested"
      case .success:
        "Completed"
      case .failure(_, let failure):
        "Failed: \(failure.operation), \(failure.cause)"
      case .cancelled:
        "Cancelled"
      }
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  private enum CharacterPresentationTime {
    private static let clock = ContinuousClock()
    private static let origin = clock.now

    static var now: Double {
      let components = origin.duration(to: clock.now).components
      return Double(components.seconds)
        + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  private struct CharacterTimelineView: View {
    private struct PoseConfiguration: Equatable {
      let projection: CharacterProjection
      let motionProfile: CharacterMotionProfile
    }

    private struct SessionInput: Equatable {
      let state: CharacterState
      let poseConfiguration: PoseConfiguration
      let reduceMotion: Bool
      let transitionProfile: CharacterTransitionProfile
    }

    let source: CharacterRenderSource
    let state: CharacterState
    let overlayAccents: [CharacterAccentPose]
    let accessoryOverlays: [CharacterAccessoryOverlay]

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.characterReducedMotion) private var hostReduceMotion
    private var accessibilityReduceMotion: Bool { systemReduceMotion || hostReduceMotion }
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: CharacterPresentationSession
    @State private var appliedPoseConfiguration: PoseConfiguration

    private var poseConfiguration: PoseConfiguration {
      PoseConfiguration(
        projection: source.projection,
        motionProfile: source.motionProfile
      )
    }

    private var sessionInput: SessionInput {
      SessionInput(
        state: state,
        poseConfiguration: poseConfiguration,
        reduceMotion: accessibilityReduceMotion,
        transitionProfile: source.transitionProfile
      )
    }

    init(
      source: CharacterRenderSource,
      state: CharacterState,
      overlayAccents: [CharacterAccentPose],
      accessoryOverlays: [CharacterAccessoryOverlay]
    ) {
      self.source = source
      self.state = state
      self.overlayAccents = overlayAccents
      self.accessoryOverlays = accessoryOverlays
      let initialPoseConfiguration = PoseConfiguration(
        projection: source.projection,
        motionProfile: source.motionProfile
      )
      _presentation = State(
        initialValue: CharacterPresentationSession(
          state: state,
          at: CharacterPresentationTime.now
        )
      )
      _appliedPoseConfiguration = State(initialValue: initialPoseConfiguration)
    }

    var body: some View {
      Group {
        if accessibilityReduceMotion {
          // A paused TimelineView can retain a stale Canvas on iOS 16.
          // Direct rendering still invalidates on semantic/profile changes.
          frame(reduceMotion: true)
        } else {
          TimelineView(
            .animation(
              minimumInterval: source.designFramesPerSecond.map { 1.0 / Double($0) },
              paused: scenePhase != .active
            )
          ) { _ in
            frame(reduceMotion: false)
          }
        }
      }
      .onChange(of: sessionInput) { input in
        let now = CharacterPresentationTime.now
        if input.poseConfiguration != appliedPoseConfiguration {
          presentation.reconcilePresentationConfigurationChange(at: now)
          appliedPoseConfiguration = input.poseConfiguration
        }
        presentation.update(
          state: input.state,
          at: now,
          reduceMotion: input.reduceMotion,
          projection: input.poseConfiguration.projection,
          motionProfile: input.poseConfiguration.motionProfile,
          transitionProfile: input.transitionProfile
        )
      }
    }

    @ViewBuilder
    private func frame(reduceMotion: Bool) -> some View {
      let pose = presentation.pose(
        at: CharacterPresentationTime.now, reduceMotion: reduceMotion,
        projection: source.projection, motionProfile: source.motionProfile
      )
      switch source {
      case .artDirection(let direction):
        CharacterArtFrame(
          pose: pose, direction: direction, overlayAccents: overlayAccents,
          accessoryOverlays: accessoryOverlays
        )
      case .design(let design, let partColors):
        CharacterDesignFrame(
          pose: pose, design: design, partColors: partColors,
          overlayAccents: overlayAccents,
          accessoryOverlays: accessoryOverlays
        )
      }
    }
  }

#endif
