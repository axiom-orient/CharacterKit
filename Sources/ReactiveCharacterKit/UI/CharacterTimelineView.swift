#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  enum CharacterPresentationTime {
    private static let clock = ContinuousClock()
    private static let origin = clock.now

    static var now: Double {
      let components = origin.duration(to: clock.now).components
      return Double(components.seconds)
        + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterTimelineView: View {
    private struct PoseConfiguration: Equatable {
      let projection: CharacterProjection
      let motionProfile: CharacterMotionProfile
      let detailMotionStyle: CharacterDetailMotionStyle
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
        motionProfile: source.motionProfile,
        detailMotionStyle: detailMotionStyle
      )
    }

    private var detailMotionStyle: CharacterDetailMotionStyle {
      source.artDirection?.detailMotionStyle ?? .standard
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
        motionProfile: source.motionProfile,
        detailMotionStyle: source.artDirection?.detailMotionStyle ?? .standard
      )
      _presentation = State(
        initialValue: CharacterPresentationSession(
          state: state,
          at: CharacterPresentationTime.now,
          detailMotionStyle: initialPoseConfiguration.detailMotionStyle
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
          presentation.reconcilePresentationConfigurationChange(
            at: now, detailMotionStyle: input.poseConfiguration.detailMotionStyle)
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
