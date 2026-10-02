import Foundation

public enum CharacterPresentationDirective: Sendable, Equatable {
  case unchanged
  case gazeTransition(maximumDuration: Double)
  case handoffThroughNeutral(maximumDuration: Double)
}

/// Semantic transition evidence with a presentation handoff projection.
/// Reducer disposition is not evidence of external effect completion.
public struct CharacterActionReceipt: Sendable, Equatable {
  public let event: CharacterEvent
  public let stateBefore: CharacterState
  public let stateAfter: CharacterState
  public let effects: [CharacterEffect]
  public let disposition: CharacterDisposition
  public let presentation: CharacterPresentationDirective
}

extension ReactiveCharacter {
  /// Runs the canonical reducer, then projects the transition's visual handoff.
  public static func act(
    state: CharacterState,
    event: CharacterEvent,
    transitionProfile: CharacterTransitionProfile = .expressive
  ) -> CharacterActionReceipt {
    let transition = reduce(state: state, event: event)
    let presentation: CharacterPresentationDirective
    if transition.disposition == .accepted,
      state.performanceIdentity != transition.state.performanceIdentity
    {
      presentation = .handoffThroughNeutral(
        maximumDuration: transitionProfile.maximumReturnDuration
          + transitionProfile.neutralHoldDuration
      )
    } else if transition.disposition == .accepted,
      state.gazeIdentity != transition.state.gazeIdentity
    {
      presentation = .gazeTransition(
        maximumDuration: CharacterPresentationPolicy.maximumGazeTransitionDuration
      )
    } else {
      presentation = .unchanged
    }

    return CharacterActionReceipt(
      event: event,
      stateBefore: state,
      stateAfter: transition.state,
      effects: transition.effects,
      disposition: transition.disposition,
      presentation: presentation
    )
  }
}

extension CharacterActionReceipt {
  public var diagnostic: CharacterActionDiagnostic { disposition.diagnostic }

  /// Commit stateAfter, cancel these registered timers, then execute effects. Cancellation
  /// and effect completion remain host responsibilities, including stale callback guards.
  public func effectPlan<S: Sequence>(scheduledAnimationIDs: S) -> CharacterEffectPlan
  where S.Element == CharacterAnimationID {
    CharacterEffectPlan(
      animationIDsToCancel: Set(scheduledAnimationIDs)
        .filter { $0 != stateAfter.animation?.id }
        .sorted { $0.rawValue < $1.rawValue },
      effects: effects)
  }
}
