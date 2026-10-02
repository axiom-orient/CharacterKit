import Foundation

/// Internal presentation vocabulary; none of these channels is semantic state or an eyebrow.
/// Numeric channels blend continuously; all rendered silhouettes share twelve cubic segments.
struct CharacterEyeContour: Sendable, Equatable {
  let lidCompression: Double
  let innerPinch: Double
  let crescent: Double
  let ellipse: Double
  let chevron: Double
  let heart: Double
  let widthScale: Double
  let heightScale: Double
  let circular: Double

  init(
    lidCompression: Double = 0,
    innerPinch: Double = 0,
    crescent: Double = 0,
    ellipse: Double = 0,
    chevron: Double = 0,
    widthScale: Double = 1,
    heightScale: Double = 1,
    circular: Double = 0,
    heart: Double = 0
  ) {
    precondition(
      [lidCompression, innerPinch, crescent, ellipse, chevron, circular, heart].allSatisfy {
        $0.isFinite && (0...1).contains($0)
      },
      "eye contour channels must be finite unit values")
    self.lidCompression = lidCompression
    self.innerPinch = innerPinch
    precondition(
      [widthScale, heightScale].allSatisfy { $0.isFinite && $0 > 0 && $0 <= 3 },
      "eye contour scales must be finite positive values")
    self.crescent = crescent
    self.ellipse = ellipse
    self.chevron = chevron
    self.heart = heart
    self.widthScale = widthScale
    self.heightScale = heightScale
    self.circular = circular
  }

  static let neutral = Self()

  func blended(to target: Self, amount: Double) -> Self {
    precondition(amount.isFinite)
    // Surface choreography may overshoot; a normalized contour must not.
    let t = min(1, max(0, amount))
    func mix(_ a: Double, _ b: Double) -> Double { a * (1 - t) + b * t }
    return Self(
      lidCompression: mix(lidCompression, target.lidCompression),
      innerPinch: mix(innerPinch, target.innerPinch),
      crescent: mix(crescent, target.crescent),
      ellipse: mix(ellipse, target.ellipse),
      chevron: mix(chevron, target.chevron),
      widthScale: mix(widthScale, target.widthScale),
      heightScale: mix(heightScale, target.heightScale),
      circular: mix(circular, target.circular),
      heart: mix(heart, target.heart))
  }
}

struct CharacterEyeContourPair: Sendable, Equatable {
  let left: CharacterEyeContour
  let right: CharacterEyeContour

  static let neutral = Self(left: .neutral, right: .neutral)

  func blended(to target: Self, amount: Double) -> Self {
    Self(
      left: left.blended(to: target.left, amount: amount),
      right: right.blended(to: target.right, amount: amount))
  }
}
