import Foundation

/// Presentation policy only; it never changes emotion identity or semantic state.
public enum CharacterEmotionMotion: String, Sendable, Equatable, Hashable, CaseIterable {
  /// Preserves the authored choreography used by the standard renderer.
  case authored
  /// Gives each of the twelve emotions its own tempo and motion amplitude.
  case adaptive
  /// Keeps emotional shape while reducing time-varying motion.
  case restrained
  /// Keeps emotional shape while increasing time-varying motion.
  case exaggerated

  func dynamics(for emotion: CharacterEmotion?) -> (tempo: Double, amplitude: Double) {
    guard self != .authored, let emotion else { return (1, 1) }

    let base: (tempo: Double, amplitude: Double)
    switch emotion {
    case .joy: base = (1.05, 1.25)
    case .affection: base = (0.50, 0.35)
    case .gratitude: base = (0.55, 0.50)
    case .interest: base = (0.75, 0.75)
    case .surprise: base = (1.30, 1.30)
    case .calmTrust: base = (0.42, 0.25)
    case .sadness: base = (0.48, 0.35)
    case .anxietyFear: base = (1.0, 1.10)
    case .angerIrritation: base = (1.15, 1.20)
    case .disgustContempt: base = (0.65, 0.65)
    case .shameGuilt: base = (0.45, 0.30)
    case .fatigueBurden: base = (0.38, 0.30)
    }

    switch self {
    case .authored, .adaptive:
      return base
    case .restrained:
      return (base.tempo * 0.8, base.amplitude * 0.55)
    case .exaggerated:
      return (base.tempo, min(1.5, base.amplitude * 1.4))
    }
  }
}
