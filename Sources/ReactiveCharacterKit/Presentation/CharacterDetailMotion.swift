import Foundation

enum CharacterDetailMotionStyle: Sendable, Equatable {
  case semi
}

/// Bounded secondary-motion channels for renderer-owned fine detail.
///
/// The phases come from an existing semantic presentation clock. Handoffs blend these
/// sampled vectors instead of interpolating angles, so crossing a cycle boundary stays
/// continuous.
struct CharacterDetailMotion: Sendable, Equatable {
  let sway: Double
  let swayQuadrature: Double
  let quiver: Double
  let quiverQuadrature: Double
  let impulse: Double
  let amount: Double

  static let still = Self(
    sway: 0,
    swayQuadrature: 0,
    quiver: 0,
    quiverQuadrature: 0,
    impulse: 0,
    amount: 0
  )

  static func sample(time: Double, impulse: Double, amount: Double) -> Self {
    guard time.isFinite, time >= 0, amount.isFinite, impulse.isFinite else { return .still }
    let strength = clamp(amount, lower: 0, upper: 1)
    guard strength > 0 else { return .still }

    // Rates are radians per second: 0.7Hz for broad sway and 7Hz for fine electric quiver.
    let slowRate = 2 * Double.pi * 0.7
    let quiverRate = 2 * Double.pi * 7.0
    return Self(
      sway: clamp(CharacterPeriodicArithmetic.sine(time: time, rate: slowRate), lower: -1, upper: 1),
      swayQuadrature: clamp(
        CharacterPeriodicArithmetic.sine(time: time, rate: slowRate, offset: .pi / 2),
        lower: -1, upper: 1),
      quiver: clamp(CharacterPeriodicArithmetic.sine(time: time, rate: quiverRate), lower: -1, upper: 1),
      quiverQuadrature: clamp(
        CharacterPeriodicArithmetic.sine(time: time, rate: quiverRate, offset: .pi / 2),
        lower: -1, upper: 1),
      impulse: clamp(impulse, lower: 0, upper: 1),
      amount: strength
    )
  }

  func blended(to other: Self, amount: Double) -> Self {
    let progress = Self.clamp(amount, lower: 0, upper: 1)
    return Self(
      sway: Self.mix(sway, other.sway, amount: progress),
      swayQuadrature: Self.mix(swayQuadrature, other.swayQuadrature, amount: progress),
      quiver: Self.mix(quiver, other.quiver, amount: progress),
      quiverQuadrature: Self.mix(quiverQuadrature, other.quiverQuadrature, amount: progress),
      impulse: Self.clamp(Self.mix(impulse, other.impulse, amount: progress), lower: 0, upper: 1),
      amount: Self.clamp(Self.mix(self.amount, other.amount, amount: progress), lower: 0, upper: 1)
    )
  }

  private static func mix(_ start: Double, _ end: Double, amount: Double) -> Double {
    start + (end - start) * amount
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(upper, max(lower, value))
  }
}
