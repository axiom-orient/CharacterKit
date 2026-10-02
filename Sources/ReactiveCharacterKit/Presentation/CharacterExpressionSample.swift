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
  var brows: CharacterBrowPairPose = .neutral

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

extension CharacterExpressionSample {
  /// Preserve readable emotional shape while scaling only time-varying deviation.
  /// Blink closure remains complete; task, speech and one-shot clocks are untouched.
  func scalingMotion(around rest: Self, by amount: Double) -> Self {
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
    return Self(
      gazeX: mix(rest.gazeX, gazeX), gazeY: mix(rest.gazeY, gazeY),
      idleMotionScale: idleMotionScale,
      eyeWidthScale: mix(rest.eyeWidthScale, eyeWidthScale),
      eyeHeightScale: mix(rest.eyeHeightScale, eyeHeightScale),
      leftEyeScale: mix(rest.leftEyeScale, leftEyeScale),
      rightEyeScale: mix(rest.rightEyeScale, rightEyeScale),
      leftAngle: mix(rest.leftAngle, leftAngle), rightAngle: mix(rest.rightAngle, rightAngle),
      blink: blink,
      mouthCurvature: mix(rest.mouthCurvature, mouthCurvature),
      mouthOpenness: max(0, min(1, mix(rest.mouthOpenness, mouthOpenness))),
      mouthWidth: mix(rest.mouthWidth, mouthWidth), mouthSkew: mix(rest.mouthSkew, mouthSkew),
      surface: .init(
        offsetX: mix(rest.surface.offsetX, surface.offsetX),
        offsetY: mix(rest.surface.offsetY, surface.offsetY),
        scaleX: mix(rest.surface.scaleX, surface.scaleX),
        scaleY: mix(rest.surface.scaleY, surface.scaleY),
        angle: mix(rest.surface.angle, surface.angle)),
      trailBoost: trailBoost * amount)
  }
}
