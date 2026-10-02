import Foundation

/// Tuning for presentation only. It never changes semantic state or reducer behavior.
/// Values are intentionally low-dimensional so custom renderers can share the same motion language.
public struct CharacterMotionProfile: Sendable, Equatable {
  public let expressiveness: Double
  public let trailStrength: Double
  public let accentStrength: Double
  public let idleStrength: Double
  public let emotionMotion: CharacterEmotionMotion

  public init(
    expressiveness: Double = 1,
    trailStrength: Double = 1,
    accentStrength: Double = 1,
    idleStrength: Double = 1,
    emotionMotion: CharacterEmotionMotion = .authored
  ) throws {
    for (field, value) in [
      ("expressiveness", expressiveness),
      ("trailStrength", trailStrength),
      ("accentStrength", accentStrength),
      ("idleStrength", idleStrength),
    ] {
      guard value.isFinite, (0...1.5).contains(value) else {
        throw CharacterPresentationError.invalidMotionProfile(field: field, value: value)
      }
    }
    self.expressiveness = expressiveness
    self.trailStrength = trailStrength
    self.accentStrength = accentStrength
    self.idleStrength = idleStrength
    self.emotionMotion = emotionMotion
  }

  private init(
    uncheckedExpressiveness expressiveness: Double,
    trailStrength: Double,
    accentStrength: Double,
    idleStrength: Double,
    emotionMotion: CharacterEmotionMotion = .authored
  ) {
    self.expressiveness = expressiveness
    self.trailStrength = trailStrength
    self.accentStrength = accentStrength
    self.idleStrength = idleStrength
    self.emotionMotion = emotionMotion
  }

  public static let expressive = Self(
    uncheckedExpressiveness: 1,
    trailStrength: 1,
    accentStrength: 1,
    idleStrength: 1
  )

  /// High-energy 2.5D performance tuned for mascot-style cartoon acting.
  /// This is presentation-only: semantic state, reducer decisions and effect ownership are unchanged.
  public static let cartoon = Self(
    uncheckedExpressiveness: 1.32,
    trailStrength: 0,
    accentStrength: 1.28,
    idleStrength: 0.92
  )

  /// Quiet companion presentation: preserves natural blinking without idle gaze or body drift.
  public static let companion = Self(
    uncheckedExpressiveness: 0.62,
    trailStrength: 0,
    accentStrength: 0,
    idleStrength: 0
  )

  public static let soft = Self(
    uncheckedExpressiveness: 0.62,
    trailStrength: 0.36,
    accentStrength: 0.58,
    idleStrength: 0.68
  )

  public static let minimal = Self(
    uncheckedExpressiveness: 0.34,
    trailStrength: 0,
    accentStrength: 0.28,
    idleStrength: 0.42
  )
}

/// Interruption policy for visual handoffs.
///
/// Any new presentation intent snapshots the current pose, returns through neutral,
/// holds neutral briefly so the reset is readable, then starts the destination motion.
/// `maximumReturnDuration + neutralHoldDuration` is always constrained to <= 1 second.
public struct CharacterTransitionProfile: Sendable, Equatable {
  /// Hard upper bound used by semantic one-shot scheduling.
  public static let maximumAllowedHandoffDuration: Double =
    CharacterAnimationLifecyclePolicy.maximumHandoffDuration

  public let minimumReturnDuration: Double
  public let maximumReturnDuration: Double
  public let neutralHoldDuration: Double
  public let rebound: Double

  public init(
    minimumReturnDuration: Double = 0.16,
    maximumReturnDuration: Double = 0.68,
    neutralHoldDuration: Double = 0.08,
    rebound: Double = 0.045
  ) throws {
    let values = [minimumReturnDuration, maximumReturnDuration, neutralHoldDuration, rebound]
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      throw CharacterPresentationError.invalidTransitionProfile(field: "transition", value: .nan)
    }
    guard minimumReturnDuration <= maximumReturnDuration else {
      throw CharacterPresentationError.invalidTransitionProfile(
        field: "minimumReturnDuration",
        value: minimumReturnDuration
      )
    }
    guard
      maximumReturnDuration + neutralHoldDuration <= Self.maximumAllowedHandoffDuration
    else {
      throw CharacterPresentationError.invalidTransitionProfile(
        field: "transitionTotalDuration",
        value: maximumReturnDuration + neutralHoldDuration
      )
    }
    guard rebound <= 0.12 else {
      throw CharacterPresentationError.invalidTransitionProfile(field: "rebound", value: rebound)
    }
    self.minimumReturnDuration = minimumReturnDuration
    self.maximumReturnDuration = maximumReturnDuration
    self.neutralHoldDuration = neutralHoldDuration
    self.rebound = rebound
  }

  private init(
    uncheckedMinimumReturnDuration minimumReturnDuration: Double,
    maximumReturnDuration: Double,
    neutralHoldDuration: Double,
    rebound: Double
  ) {
    self.minimumReturnDuration = minimumReturnDuration
    self.maximumReturnDuration = maximumReturnDuration
    self.neutralHoldDuration = neutralHoldDuration
    self.rebound = rebound
  }

  public static let expressive = Self(
    uncheckedMinimumReturnDuration: 0.16,
    maximumReturnDuration: 0.68,
    neutralHoldDuration: 0.08,
    rebound: 0.045
  )

  public static let soft = Self(
    uncheckedMinimumReturnDuration: 0.18,
    maximumReturnDuration: 0.52,
    neutralHoldDuration: 0.07,
    rebound: 0.020
  )

  /// Snappier handoff for cartoon performance: readable neutral reset, then a visible rebound.
  public static let cartoon = Self(
    uncheckedMinimumReturnDuration: 0.11,
    maximumReturnDuration: 0.46,
    neutralHoldDuration: 0.045,
    rebound: 0.072
  )

  public static let reducedMotion = Self(
    uncheckedMinimumReturnDuration: 0.10,
    maximumReturnDuration: 0.22,
    neutralHoldDuration: 0.05,
    rebound: 0
  )
}

extension CharacterMotionProfile {
  /// Keeps the selected emotion performance and removes unrelated idle cues and trails.
  public static func focusedEmotion(_ emotionMotion: CharacterEmotionMotion = .adaptive) -> Self {
    Self(
      uncheckedExpressiveness: 1,
      trailStrength: 0,
      accentStrength: 0,
      idleStrength: 0,
      emotionMotion: emotionMotion
    )
  }
}
