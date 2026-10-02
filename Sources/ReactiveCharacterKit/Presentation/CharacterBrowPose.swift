import Foundation

/// Renderer-neutral eyebrow articulation. It is presentation data, not semantic state.
struct CharacterBrowPose: Sendable, Equatable {
  let angle: Double
  let lift: Double
  let bend: Double

  static let neutral = Self(angle: 0, lift: 0, bend: 0)

  func blended(to target: Self, amount: Double) -> Self {
    let t = min(1, max(0, amount))
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
    return Self(
      angle: mix(angle, target.angle),
      lift: mix(lift, target.lift),
      bend: mix(bend, target.bend))
  }
}

struct CharacterBrowPairPose: Sendable, Equatable {
  let left: CharacterBrowPose
  let right: CharacterBrowPose

  static let neutral = Self(left: .neutral, right: .neutral)

  func blended(to target: Self, amount: Double) -> Self {
    Self(
      left: left.blended(to: target.left, amount: amount),
      right: right.blended(to: target.right, amount: amount))
  }
}
