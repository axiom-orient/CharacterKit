#if os(iOS) || os(macOS)
  import SwiftUI

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

#endif
