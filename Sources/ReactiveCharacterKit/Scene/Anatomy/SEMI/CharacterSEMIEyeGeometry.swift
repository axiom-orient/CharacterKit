import Foundation

/// Authored artwork coordinates and bounded presentation responses. Not semantic state.
enum CharacterSEMIMetrics {
  static let width = 512.0
  static let height = 560.0
  static let leftEyeX = 172.0
  static let rightEyeX = 355.0
  static let eyeY = 306.0
  static let eyeWidth = 112.0
  static let eyeHeight = 124.0
  static let closedEyeHeight = 0.040
  static let neutralEyeWidth = 0.19
  static let neutralEyeHeight = 0.43
  static let maximumEyeWidth = 152.0
  static let maximumEyeHeight = 164.0
  static let contourClosureWeight = 0.82
  static let minimumProjectedEyeWidthScale = 0.72
  static let maximumProjectedEyeWidthScale = 1.20
  static let minimumProjectedEyeHeightScale = 0.68
  static let maximumProjectedEyeHeightScale = 1.22
  static let maximumEarAngle = 0.24
  static let maximumGazeTravel = 19.0
  static let maximumMuzzleTravel = 12.0
  static let irisWidth = 73.0
  static let irisHeight = 106.0
  static let pupilBaseWidthRatio = 0.14
  static let pupilDilationWidthGain = 0.24
  static let pupilBaseHeightRatio = 0.84
  static let pupilDilationHeightLoss = 0.08
  static let glintHorizontalGazeFollow = 0.52
  static let glintVerticalGazeFollow = 0.28
  static let maximumMouthOpen = 70.0
  static let mouthRestDeadband = 0.04
  static let pupilContourSamples = 32
  static let closedThreshold = 0.008
  static let irisFiberCount = 28

  static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
    min(upper, max(lower, value))
  }
}

/// A sampled anatomical aperture. The immutable pose remains the only input authority.
struct CharacterSEMIEyeGeometry {
  let centerX: Double
  let centerY: Double
  let width: Double
  let height: Double
  let closure: Double
  let happiness: Double
  let pinch: Double
  let ellipse: Double
  let surprise: Double
  let heart: Double
  let angle: Double

  init(
    eye: CharacterEyePose, contour: CharacterEyeContour, left: Bool,
    gazeX: Double, gazeY: Double, sizeResponse: Double = 1
  ) {
    let c = CharacterSEMIMetrics.clamp
    centerX = (left ? CharacterSEMIMetrics.leftEyeX : CharacterSEMIMetrics.rightEyeX) + gazeX * 10
    centerY = CharacterSEMIMetrics.eyeY + gazeY * 7

    happiness = contour.crescent
    pinch = contour.innerPinch
    ellipse = contour.ellipse
    surprise = contour.circular
    heart = contour.heart

    // Blink is its own presentation channel. Gaze/projection changes the unblinked eye size but
    // must never be reinterpreted as eyelid closure.
    closure = c(
      max(
        eye.blink, max(contour.lidCompression * CharacterSEMIMetrics.contourClosureWeight, happiness)
      ),
      0, 1)

    let sourceDynamicWidth = c(
      eye.unblinkedWidth / CharacterSEMIMetrics.neutralEyeWidth,
      CharacterSEMIMetrics.minimumProjectedEyeWidthScale,
      CharacterSEMIMetrics.maximumProjectedEyeWidthScale)
    let sourceDynamicHeight = c(
      eye.unblinkedHeight / CharacterSEMIMetrics.neutralEyeHeight,
      CharacterSEMIMetrics.minimumProjectedEyeHeightScale,
      CharacterSEMIMetrics.maximumProjectedEyeHeightScale)
    let response = CharacterSEMIMetrics.clamp(sizeResponse)
    let dynamicWidth = 1 + (sourceDynamicWidth - 1) * response
    let dynamicHeight = 1 + (sourceDynamicHeight - 1) * response
    let treatmentHeightScale = 1.0

    // The emotion contour remains the silhouette authority. Dynamic pose dimensions only add
    // bounded activity/projection response around that shape.
    width = min(
      CharacterSEMIMetrics.maximumEyeWidth,
      CharacterSEMIMetrics.eyeWidth * dynamicWidth * contour.widthScale
        * (1 + surprise * 0.08 + ellipse * 0.03 + pinch * 0.02))
    height = min(
      CharacterSEMIMetrics.maximumEyeHeight,
      CharacterSEMIMetrics.eyeHeight * dynamicHeight * contour.heightScale * treatmentHeightScale
        * (1 + surprise * 0.08 + ellipse * 0.04))
    angle = c(eye.angle * 0.34, -0.14, 0.14)
  }

  private struct ApertureGeometry {
    let left: CharacterVectorPoint
    let right: CharacterVectorPoint
    let upperControl1: CharacterVectorPoint
    let upperControl2: CharacterVectorPoint
    let lowerControl1: CharacterVectorPoint
    let lowerControl2: CharacterVectorPoint
  }

  /// Computes one shared anatomical boundary. The upper and lower lid strokes below deliberately
  /// reuse these points so a narrowed eye cannot drift away from the mask used by its iris.
  private func apertureGeometry(left: Bool) -> ApertureGeometry {
    let sign = left ? 1.0 : -1.0
    let rx = width / 2
    let ry = height / 2
    let open = 1 - closure
    let roundness = CharacterSEMIMetrics.clamp(ellipse * 0.72 + surprise * 0.85, 0, 1)
    let top = -ry * open
    let bottom = ry * sqrt(open)
    let bend = height * (0.025 * (1 - happiness) - 0.19 * happiness) * closure
    let outerY = pinch * -height * 0.08 * open
    let innerY = pinch * height * 0.19 * open
    let leftY = sign > 0 ? outerY : innerY
    let rightY = sign > 0 ? innerY : outerY
    let upperX = 0.72 + roundness * 0.10
    let lowerOuterX = (0.88 * open + 0.64 * closure) + roundness * 0.06 * open
    let lowerInnerX = (0.83 * open + 0.72 * closure) + roundness * 0.05 * open
    let roundTop = top * (1.30 - roundness * 0.16)
    let roundBottom = bottom * (1.24 - roundness * 0.08)

    return .init(
      left: .init(x: centerX - rx, y: centerY + leftY),
      right: .init(x: centerX + rx, y: centerY + rightY),
      upperControl1: .init(
        x: centerX - rx * upperX, y: centerY + roundTop + bend),
      upperControl2: .init(
        x: centerX + rx * (upperX - 0.08), y: centerY + roundTop * 0.97 + bend),
      lowerControl1: .init(
        x: centerX + rx * lowerOuterX, y: centerY + roundBottom + bend),
      lowerControl2: .init(
        x: centerX - rx * lowerInnerX, y: centerY + roundBottom * 1.01 + bend))
  }

  /// Upper and lower lids share endpoints. Eyeball contents use this exact mask in both backends.
  func aperture(left: Bool) -> CharacterVectorPath {
    let geometry = apertureGeometry(left: left)
    var p = CharacterVectorPath()
    p.move(geometry.left.x, geometry.left.y)
    p.cubic(
      geometry.upperControl1.x, geometry.upperControl1.y,
      geometry.upperControl2.x, geometry.upperControl2.y,
      geometry.right.x, geometry.right.y)
    p.cubic(
      geometry.lowerControl1.x, geometry.lowerControl1.y,
      geometry.lowerControl2.x, geometry.lowerControl2.y,
      geometry.left.x, geometry.left.y)
    p.close()
    return p
  }

  func upperLid(left: Bool) -> CharacterVectorPath {
    let geometry = apertureGeometry(left: left)
    var path = CharacterVectorPath()
    path.move(geometry.left.x, geometry.left.y)
    path.cubic(
      geometry.upperControl1.x, geometry.upperControl1.y,
      geometry.upperControl2.x, geometry.upperControl2.y,
      geometry.right.x, geometry.right.y)
    return path
  }

  /// Explicit under-eye contour for compact and half-closed expressions. The sclera boundary is
  /// still the clip/mask authority; this separate stroke keeps the lower lid legible after the
  /// iris disappears behind a descending upper lid.
  func lowerLid(left: Bool) -> CharacterVectorPath {
    let geometry = apertureGeometry(left: left)
    var path = CharacterVectorPath()
    path.move(geometry.right.x, geometry.right.y)
    path.cubic(
      geometry.lowerControl1.x, geometry.lowerControl1.y,
      geometry.lowerControl2.x, geometry.lowerControl2.y,
      geometry.left.x, geometry.left.y)
    return path
  }
}
