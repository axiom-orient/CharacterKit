import Foundation

/// Highest-level visual authority selected by the reducer-owned visual channel.
/// The latest meaningful semantic transition owns large presentation motion.
public enum CharacterVisualAuthority: Sendable, Equatable {
  case neutral
  case activity
  case emotion(CharacterEmotion)
  case communication
  case animation(CharacterAnimationState)
}

public struct CharacterInspection: Sendable, Equatable {
  public let state: CharacterState
  public let visualAuthority: CharacterVisualAuthority
  public let attention: CharacterAttention
  public let activeTaskID: CharacterTaskID?
  public let canCancelTask: Bool
  public let activeAnimation: CharacterAnimationState?
  public let mouthRequested: Bool
}

extension ReactiveCharacter {
  /// Reads the compact semantic state needed by a human adapter or agent caller.
  public static func inspect(state: CharacterState) -> CharacterInspection {
    let authority: CharacterVisualAuthority
    switch state.visualChannel {
    case .neutral:
      authority = .neutral
    case .activity:
      authority = .activity
    case .emotion:
      authority = state.emotion.map(CharacterVisualAuthority.emotion) ?? .neutral
    case .communication:
      authority = state.communication == .silent ? .neutral : .communication
    case .animation:
      authority = state.animation.map(CharacterVisualAuthority.animation) ?? .neutral
    }

    return CharacterInspection(
      state: state,
      visualAuthority: authority,
      attention: state.attention,
      activeTaskID: state.activity.activeTaskID,
      canCancelTask: state.activity.canRequestCancellation,
      activeAnimation: state.animation,
      mouthRequested: state.mouthRequested
    )
  }
}

/// Host work requested by a receipt. This value owns no timers, tasks, or clock.
public struct CharacterEffectPlan: Sendable, Equatable {
  /// Unique obsolete timer IDs, sorted by rawValue for deterministic execution/logging.
  public let animationIDsToCancel: [CharacterAnimationID]
  /// Original reducer effects, in their original order.
  public let effects: [CharacterEffect]
}
