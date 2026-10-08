import Foundation

/// Continuous, SEMI-specific projection of the shared pose into face and body cues.
/// It owns no clock or semantic state; one immutable instance is resolved per scene frame.
struct CharacterSEMIExpressionRig {
  private static let neutralMouthWidth = 0.68

  let mouthArticulation: Double
  let mouthCurvature: Double
  let mouthOpenness: Double
  let mouthWidth: Double
  let mouthSkew: Double
  let warmth: Double
  let alert: Double
  let surprise: Double
  let anxiety: Double
  let tension: Double
  let fatigue: Double
  let calmTrust: Double
  let affection: Double
  let tenderness: Double
  let gratitude: Double
  let gratitudeCourtesy: Double
  let gratitudeFondness: Double
  let sadness: Double
  let joy: Double
  let heaviness: Double
  let communication: Double
  let energy: Double

  init(pose: CharacterPose) {
    func bounded(_ value: Double, lower: Double = 0, upper: Double = 1) -> Double {
      min(upper, max(lower, value.isFinite ? value : lower))
    }
    func average(_ keyPath: KeyPath<CharacterEyeContour, Double>) -> Double {
      let values = [pose.eyeContours.left, pose.eyeContours.right].map { $0[keyPath: keyPath] }
      return values.reduce(0, +) / Double(values.count)
    }

    let articulation = pose.mouth.visible
      ? bounded(pose.mouth.opacity)
      : 0
    let curvature = bounded(pose.mouth.curvature, lower: -1, upper: 1) * articulation
    let openness = bounded(pose.mouth.openness) * articulation
    let sourceWidth = bounded(pose.mouth.width, lower: 0.24, upper: 1.35)
    let width = Self.neutralMouthWidth + (sourceWidth - Self.neutralMouthWidth) * articulation
    let skew = bounded(pose.mouth.skew, lower: -1, upper: 1) * articulation

    let crescent = average(\.crescent)
    let pinch = average(\.innerPinch)
    let compression = average(\.lidCompression)
    let ellipse = average(\.ellipse)
    let circular = average(\.circular)
    let heart = average(\.heart)
    let mouthSmile = max(0, curvature)
    let mouthNegative = max(0, -curvature)
    let warmth = bounded(max(crescent, mouthSmile * 0.92 + heart * 0.22))
    let alert = bounded(max(circular, openness * 0.92 + ellipse * 0.18))
    let surprise = bounded(circular * alert)
    let tension = bounded(pinch * 0.78 + mouthNegative * 0.32)
    let fatigue = bounded(max(0, compression * 1.08 + pinch * 0.10 - circular * 0.28))
    let affection = bounded(heart)
    let downwardGaze = bounded(max(0, pose.face.gazeY))
    let tenderness = bounded(warmth * downwardGaze * 1.65 + affection * 0.20)
    let gratitude = bounded(
      affection * 0.58 + tenderness * 0.82 + warmth * 0.18 - alert * 0.16 - tension * 0.10)
    let gratitudeCourtesy = bounded(gratitude * (downwardGaze * 0.64 + tenderness * 0.42))
    let gratitudeFondness = bounded(
      gratitude * (warmth * 0.56 + affection * 0.70 + (1 - downwardGaze) * 0.18))
    let sadness = bounded(
      mouthNegative * 0.72 + downwardGaze * 0.46 + compression * 0.06
        - fatigue * 0.22 - tension * 0.12)
    let heaviness = bounded(fatigue * 0.72 + sadness * 0.36)

    // Fear has a rounded, tense aperture; surprise uses circularity instead. Calm trust occupies
    // the middle of the lid-compression range and recedes smoothly into fatigue at higher closure.
    let anxiety = bounded(ellipse * 0.72 + pinch * 0.22 + mouthNegative * 0.06)
    let calmWindow = bounded((compression - 0.12) / 0.28)
      * (1 - bounded((compression - 0.44) / 0.30))
    let calmTrust = bounded(
      calmWindow * (1 - alert * 0.75) * (1 - sadness * 0.80)
        * (1 - tension * 0.50) * (1 - fatigue * 0.35))
    let joy = bounded(
      max(0, warmth - gratitudeCourtesy * 0.48 - gratitudeFondness * 0.25)
        * (0.68 + openness * 0.32) * (1 - fatigue * 0.45))
    let energy = bounded(pose.motionEnergy + pose.writingOpacity * 0.12)

    self.mouthArticulation = articulation
    self.mouthCurvature = curvature
    self.mouthOpenness = openness
    self.mouthWidth = width
    self.mouthSkew = skew
    self.warmth = warmth
    self.alert = alert
    self.surprise = surprise
    self.anxiety = anxiety
    self.tension = tension
    self.fatigue = fatigue
    self.calmTrust = calmTrust
    self.affection = affection
    self.tenderness = tenderness
    self.gratitude = gratitude
    self.gratitudeCourtesy = gratitudeCourtesy
    self.gratitudeFondness = gratitudeFondness
    self.sadness = sadness
    self.joy = joy
    self.heaviness = heaviness
    self.communication = openness
    self.energy = energy
  }

  var headScaleX: Double {
    1 + warmth * 0.020 + affection * 0.018 + tenderness * 0.014 + gratitude * 0.020
      + gratitudeCourtesy * 0.010 + gratitudeFondness * 0.016 + joy * 0.012 + calmTrust * 0.006
      - alert * 0.040 + surprise * 0.034 - anxiety * 0.012 + fatigue * 0.030 + sadness * 0.018
      + heaviness * 0.014 - tension * 0.012
  }

  var headScaleY: Double {
    1 - warmth * 0.028 - affection * 0.010 - tenderness * 0.016 - gratitude * 0.016
      - gratitudeCourtesy * 0.018 - gratitudeFondness * 0.008 - joy * 0.010 - calmTrust * 0.008
      + alert * 0.052 - surprise * 0.038 + anxiety * 0.012 - fatigue * 0.032 - sadness * 0.018
      - heaviness * 0.014 + tension * 0.008
  }

  var headOffsetY: Double {
    -alert * 8.8 + surprise * 5.0 - warmth * 3.4 - joy * 1.8 + affection * 0.8 + tenderness * 4.6
      + gratitude * 2.4 + gratitudeCourtesy * 6.8 + gratitudeFondness * 2.4 + calmTrust * 1.2
      + fatigue * 10.8 + sadness * 9.0 + heaviness * 4.2 + tension * 2.2
  }

  var headOffsetX: Double {
    warmth * 1.2 + affection * 0.5 - tenderness * 1.1 - gratitude * 0.5
      - gratitudeCourtesy * 1.8 + gratitudeFondness * 0.4 - sadness * 2.6
      - heaviness * 0.8 - tension * 1.2 + anxiety * 0.8
  }

  var headAngle: Double {
    warmth * 0.026 + affection * 0.012 - tenderness * 0.026 - gratitude * 0.010
      - gratitudeCourtesy * 0.052 + gratitudeFondness * 0.010 - sadness * 0.082
      - tension * 0.030 - fatigue * 0.028 - heaviness * 0.018 - anxiety * 0.014
  }

  var tailAngle: Double {
    warmth * 0.18 + alert * 0.14 + affection * 0.08 + tenderness * 0.02
      + gratitude * 0.004 - gratitudeCourtesy * 0.030 + gratitudeFondness * 0.018
      + joy * 0.050 + calmTrust * 0.030 - fatigue * 0.34 - sadness * 0.24
      - heaviness * 0.16 - tension * 0.08
  }

  var tailOffsetY: Double {
    -warmth * 9.0 - alert * 9.0 - affection * 1.2 - tenderness * 1.2 + gratitude * 0.8
      + gratitudeCourtesy * 2.2 + gratitudeFondness * 0.4 - joy * 1.2 + calmTrust * 0.4
      + fatigue * 15.2 + sadness * 11.0 + heaviness * 4.2 + tension * 2.5
  }

  var tailOffsetX: Double {
    warmth * 3.2 + affection * 0.8 + tenderness * 0.2 + gratitude * 0.1
      - gratitudeCourtesy * 0.6 + gratitudeFondness * 0.4 - sadness * 6.0
      - fatigue * 2.4 - tension * 2.2
  }

  var tailScaleX: Double {
    1 - alert * 0.04 + warmth * 0.014 + joy * 0.008 - fatigue * 0.024 - sadness * 0.014
  }

  var tailScaleY: Double {
    1 + alert * 0.08 + warmth * 0.03 + affection * 0.02 + gratitudeFondness * 0.008
      - gratitudeCourtesy * 0.004 - fatigue * 0.084 - sadness * 0.038
  }

  func earAngle(left: Bool, base: Double) -> Double {
    let sign = left ? -1.0 : 1.0
    let relaxedOpen = sign * (warmth * 0.030 + affection * 0.040 + tenderness * 0.030
      + gratitudeCourtesy * 0.040 + gratitudeFondness * 0.072 + joy * 0.035 + calmTrust * 0.024)
    let perk = -sign * (alert * (1 - surprise * 0.48) * 0.052 + anxiety * 0.025)
    let sadOut = sign * sadness * 0.120
    let fatigueBack = sign * fatigue * 0.046
    let droop = -0.11 * tension - 0.28 * fatigue - sadness * 0.135
      - gratitudeCourtesy * 0.058 - gratitudeFondness * 0.018
    return min(0.36, max(-0.36, base + relaxedOpen + perk + sadOut + fatigueBack + droop))
  }

  func earOffsetY() -> Double {
    -alert * 7.0 + surprise * 4.2 - warmth * 2.0 + affection * 0.2 + tenderness * 1.6 + gratitude * 1.2
      + gratitudeCourtesy * 2.8 + gratitudeFondness * 0.8 + joy * 0.8
      + fatigue * 10.4 + sadness * 6.8 + heaviness * 2.2
  }

  func earScaleY() -> Double {
    1 + alert * 0.050 - surprise * 0.050 + anxiety * 0.018 - fatigue * 0.100 - sadness * 0.050
      - heaviness * 0.016
  }

  func faceAnchors(
    gazeX: Double, gazeY: Double, writingIntensity: Double
  ) -> CharacterSEMIFaceAnchorRig {
    let centerX = 255 + gazeX * 3.4 - writingIntensity * 2.2
      + gratitudeFondness * 0.8 - gratitudeCourtesy * 1.2
    let centerY = 252 + gazeY * 3.0 + gratitudeCourtesy * 2.0 + sadness * 2.8
      + fatigue * 3.6 + writingIntensity * 6.0 - joy * 1.2 + calmTrust * 0.6
    let eyeY = 231 + gazeY * 2.2 + gratitudeCourtesy * 1.8 + sadness * 2.0
      + fatigue * 3.2 + writingIntensity * 5.4 - joy * 1.0 + anxiety * 0.8
    let noseX = centerX - 1.0 + gazeX * 1.2
    let noseY = centerY + 15.2 + gratitudeCourtesy * 0.8 + sadness * 1.0
      + fatigue * 1.4 + writingIntensity * 1.5
    let mouthX = noseX + mouthSkew * 0.85
      + (gratitudeFondness * 0.4 - sadness * 0.2) * mouthArticulation
    let mouthY = noseY + 11.9 + communication * 0.9
      + (fatigue * 0.7 + sadness * 0.5 - warmth * 0.2) * mouthArticulation
    return .init(
      centerX: centerX, centerY: centerY, eyeY: eyeY,
      noseX: noseX, noseY: noseY, mouthX: mouthX, mouthY: mouthY,
      muzzleWidth: 58 + (gratitudeFondness * 4 - sadness * 2) * mouthArticulation,
      muzzleHeight: 34 + (communication * 4 + fatigue * 2) * mouthArticulation)
  }

  func headActingTransform(
    surface: CharacterSurfacePose, gazeX: Double, gazeY: Double, writingIntensity: Double
  ) -> CharacterSceneTransform {
    let bowedWriting = writingIntensity * 0.95
    return .around(x: 256, y: 210,
      angle: headAngle + surface.angle * 1.06 + gazeX * 0.012 - gazeY * 0.010
        + (communication - 0.24) * 0.026 - bowedWriting * 0.082,
      scaleX: headScaleX + communication * 0.010 - bowedWriting * 0.014,
      scaleY: headScaleY - communication * 0.008 + bowedWriting * 0.024,
      offsetX: headOffsetX + surface.offsetX * 32 + gazeX * 2.6 + bowedWriting * 5.2,
      offsetY: headOffsetY + surface.offsetY * 42 - communication * 6.2 - energy * 2.8
        + bowedWriting * 12.8)
  }
}

struct CharacterSEMIFaceAnchorRig {
  let centerX: Double
  let centerY: Double
  let eyeY: Double
  let noseX: Double
  let noseY: Double
  let mouthX: Double
  let mouthY: Double
  let muzzleWidth: Double
  let muzzleHeight: Double

  func eyeX(left: Bool) -> Double {
    left ? centerX - 54 : centerX + 55
  }
}

extension CharacterSEMIDrawing {
  var faceAnchorRig: CharacterSEMIFaceAnchorRig {
    expressionRig.faceAnchors(gazeX: gazeX, gazeY: gazeY, writingIntensity: writingIntensity)
  }

  var headActingTransform: CharacterSceneTransform {
    expressionRig.headActingTransform(
      surface: pose.surface, gazeX: gazeX, gazeY: gazeY, writingIntensity: writingIntensity)
  }
}
