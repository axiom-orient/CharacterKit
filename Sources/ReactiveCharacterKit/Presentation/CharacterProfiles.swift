import Foundation

/// Fixed presentation policy owned by SEMI. Hosts provide semantic state, not motion tuning.
struct CharacterMotionProfile: Sendable, Equatable {
  let expressiveness: Double
  let idleStrength: Double

  static let semi = Self(expressiveness: 1.32, idleStrength: 0.92)
}

/// Fixed interruption policy owned by SEMI.
struct CharacterTransitionProfile: Sendable, Equatable {
  static let maximumAllowedHandoffDuration: Double =
    CharacterAnimationLifecyclePolicy.maximumHandoffDuration

  let minimumReturnDuration: Double
  let maximumReturnDuration: Double
  let neutralHoldDuration: Double
  let rebound: Double

  static let semi = Self(
    minimumReturnDuration: 0.11,
    maximumReturnDuration: 0.46,
    neutralHoldDuration: 0.045,
    rebound: 0.072
  )
}
