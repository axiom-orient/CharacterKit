import Foundation

/// Flat-cat geometry in the existing 512 × 560 anatomy space.
/// Only the pinna tip bends. Both root endpoints remain inside the convex head ellipse.
enum CharacterSimpleCatGeometry {
  static let headBounds = CharacterRect(x: 36, y: 157, width: 440, height: 332)
  static let faceBounds = CharacterRect(x: 70, y: 255, width: 372, height: 224)
  static let eyeCenters = (left: 178.0, right: 334.0)
  static let eyeY = 346.0
  static let eyeWidth = 23.0
  static let eyeHeight = 78.0
  static let expressionWidth = 55.0
  static let eyeInkWidth = 6.0
  static let whiskerInkWidth = 7.0
  /// Points at or below this line are skull attachment and remain fixed.
  /// The visible head covers this overlap, so the pinna can bend without opening a seam.
  static let rootY = 232.0
  static let tipY = 76.0
  static let maximumEarAngle = 0.16

  /// Simple 2D ears communicate expression, not gaze. Keeping gaze out of this policy avoids
  /// a distracting ear twitch whenever the eyes make a micro-saccade.
  static func earAngle(
    contour: CharacterEyeContour, surfaceAngle: Double, left: Bool
  ) -> Double {
    let sign = left ? -1.0 : 1.0
    return CharacterCatMetrics.clamp(
      sign
        * (contour.lidCompression * 0.075 + contour.innerPinch * 0.075
          - contour.circular * 0.055 + contour.chevron * 0.060)
        + surfaceAngle * 0.045,
      -maximumEarAngle, maximumEarAngle)
  }

  static func ear(left: Bool, inner: Bool, angle: Double) -> CharacterVectorPath {
    var path = CharacterVectorPath()
    if inner {
      path.move(91, 267)
      path.cubic(86, 226, 92, 179, 107, 135)
      path.quad(109, 120, 117, 131)
      path.cubic(134, 158, 156, 195, 176, 221)
      path.line(153, 258)
    } else {
      path.move(75, 295)
      path.cubic(60, 226, 68, 146, 94, 86)
      path.cubic(99, 72, 106, 70, 116, 78)
      path.cubic(161, 110, 203, 166, 228, 238)
    }
    path.close()
    let boundedAngle = CharacterCatMetrics.clamp(
      angle, -maximumEarAngle, maximumEarAngle)
    return path.mapped { point in
      // A smooth distance weight, not another skeleton, clock or mutable simulation.
      let distance = CharacterCatMetrics.clamp((rootY - point.y) / (rootY - tipY))
      let weight = distance * distance * (3 - 2 * distance)
      let x = left ? point.x : CharacterCatMetrics.width - point.x
      let pivotX = left ? 158.0 : CharacterCatMetrics.width - 158.0
      let rotation = boundedAngle * weight
      let dx = x - pivotX
      let dy = point.y - 252
      return .init(
        x: pivotX + dx * cos(rotation) - dy * sin(rotation),
        y: 252 + dx * sin(rotation) + dy * cos(rotation))
    }
  }

  static func smoothstep(_ value: Double) -> Double {
    let t = CharacterCatMetrics.clamp(value)
    return t * t * (3 - 2 * t)
  }
}
