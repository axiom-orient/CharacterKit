import Foundation

/// Pure presentation data that couples lower-face placement to the final eye pose.
/// It owns no semantic state, clock, renderer, or I/O.
struct CharacterFeaturePlacement: Sendable, Equatable {
  let offsetX: Double
  let offsetY: Double
  let scaleX: Double
  let scaleY: Double

  static let identity = Self(offsetX: 0, offsetY: 0, scaleX: 1, scaleY: 1)
}

struct CharacterFacePose: Sendable, Equatable {
  let gazeX: Double
  let gazeY: Double
  let mouth: CharacterFeaturePlacement
}

private enum CharacterFaceCompositionPolicy {
  static let maximumHorizontalGaze = 0.23
  static let maximumVerticalGaze = 0.24
  static let verticalEyeNormalization = 0.96
  static let mouthHorizontalTravel = 0.12
  static let mouthVerticalTravel = 0.07
  static let perspectiveCompression = 0.10
  static let verticalScaleResponse = 0.035
  static let minimumMouthScaleX = 0.95
  static let minimumMouthScaleY = 0.97
  static let maximumMouthScaleY = 1.03

  static func turnFollow(for emotion: CharacterEmotion?) -> Double {
    switch emotion {
    case nil: 0.40
    case .joy: 0.56
    case .affection: 0.44
    case .gratitude: 0.38
    case .interest: 0.64
    case .surprise: 0.46
    case .calmTrust: 0.40
    case .sadness: 0.34
    case .anxietyFear: 0.38
    case .angerIrritation: 0.40
    case .disgustContempt: 0.30
    case .shameGuilt: 0.30
    case .fatigueBurden: 0.32
    }
  }
}

/// Motion-dependent coefficients sampled with the semantic pose. The final placement is not
/// stored here; it is resolved from the final eyes so interrupted gaze transitions cannot leave
/// the mouth attached to a stale target frame.
struct CharacterFaceDynamics: Sendable, Equatable {
  /// How strongly the lower face follows the resolved gaze direction. This is always non-negative:
  /// emotion owns articulation, not a second face-orientation coordinate system.
  let turnFollow: Double
  let usesPerspective: Bool

  static let neutral = Self(turnFollow: 0.40, usesPerspective: false)

  static func sample(
    emotion: CharacterEmotion?,
    projection: CharacterProjection
  ) -> Self {
    return Self(
      turnFollow: CharacterFaceCompositionPolicy.turnFollow(for: emotion),
      usesPerspective: projection == .softSphere
    )
  }

  func blended(to other: Self, amount: Double) -> Self {
    let t = min(1, max(0, amount))
    return Self(
      turnFollow: turnFollow + (other.turnFollow - turnFollow) * t,
      usesPerspective: t < 0.5 ? usesPerspective : other.usesPerspective
    )
  }
}

enum CharacterFaceComposition {
  static func resolve(
    eyes: CharacterEyePairPose,
    dynamics: CharacterFaceDynamics
  ) -> CharacterFacePose {
    let horizontal = bounded(
      (eyes.left.centerX + eyes.right.centerX) * 0.5 - 0.5,
      lower: -CharacterFaceCompositionPolicy.maximumHorizontalGaze,
      upper: CharacterFaceCompositionPolicy.maximumHorizontalGaze
    )
    let vertical = bounded(
      ((eyes.left.centerY + eyes.right.centerY) * 0.5 - 0.5)
        / CharacterFaceCompositionPolicy.verticalEyeNormalization,
      lower: -CharacterFaceCompositionPolicy.maximumVerticalGaze,
      upper: CharacterFaceCompositionPolicy.maximumVerticalGaze
    )
    let perspective = dynamics.usesPerspective ? abs(horizontal) : 0

    return CharacterFacePose(
      gazeX: horizontal,
      gazeY: vertical,
      mouth: CharacterFeaturePlacement(
        offsetX: horizontal * CharacterFaceCompositionPolicy.mouthHorizontalTravel
          * dynamics.turnFollow,
        offsetY: vertical * CharacterFaceCompositionPolicy.mouthVerticalTravel
          * dynamics.turnFollow,
        scaleX: bounded(
          1 - perspective * CharacterFaceCompositionPolicy.perspectiveCompression,
          lower: CharacterFaceCompositionPolicy.minimumMouthScaleX,
          upper: 1),
        scaleY: bounded(
          1 + vertical * CharacterFaceCompositionPolicy.verticalScaleResponse,
          lower: CharacterFaceCompositionPolicy.minimumMouthScaleY,
          upper: CharacterFaceCompositionPolicy.maximumMouthScaleY)
      )
    )
  }

  private static func bounded(_ value: Double, lower: Double, upper: Double) -> Double {
    min(upper, max(lower, value))
  }
}

extension CharacterPose {
  var face: CharacterFacePose {
    CharacterFaceComposition.resolve(eyes: eyes, dynamics: faceDynamics)
  }
}
