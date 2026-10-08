import Foundation

struct CharacterExpressionSample: Sendable, Equatable {
  let gazeX: Double
  let gazeY: Double
  let idleMotionScale: Double
  let eyeWidthScale: Double
  let eyeHeightScale: Double
  let leftEyeScale: Double
  let rightEyeScale: Double
  let leftAngle: Double
  let rightAngle: Double
  let blink: Double
  let mouthCurvature: Double
  let mouthOpenness: Double
  let mouthWidth: Double
  let mouthSkew: Double
  let surface: CharacterSurfacePose
  let trailBoost: Double
  var eyeContours: CharacterEyeContourPair = .neutral

  static let neutral = Self(
    gazeX: 0,
    gazeY: 0,
    idleMotionScale: 1,
    eyeWidthScale: 1,
    eyeHeightScale: 1,
    leftEyeScale: 1,
    rightEyeScale: 1,
    leftAngle: 0,
    rightAngle: 0,
    blink: 0,
    mouthCurvature: 0,
    mouthOpenness: 0,
    mouthWidth: 0.68,
    mouthSkew: 0,
    surface: .identity,
    trailBoost: 0
  )
}
