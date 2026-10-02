import Foundation

@testable import ReactiveCharacterKit

// Test-only containment oracle; it is not a renderer feature.
extension CharacterGeometry {
  static func capsuleBounds(
    _ capsule: CharacterCapsule
  ) -> CharacterRect {
    let cosine = abs(cos(capsule.angle))
    let sine = abs(sin(capsule.angle))
    let extentX = cosine * capsule.width / 2 + sine * capsule.height / 2
    let extentY = sine * capsule.width / 2 + cosine * capsule.height / 2
    return CharacterRect(
      x: capsule.centerX - extentX,
      y: capsule.centerY - extentY,
      width: extentX * 2,
      height: extentY * 2
    )
  }

  static func contains(
    _ outer: CharacterRect,
    _ inner: CharacterRect,
    epsilon: Double = 1e-8
  ) -> Bool {
    inner.minX >= outer.minX - epsilon
      && inner.minY >= outer.minY - epsilon
      && inner.maxX <= outer.maxX + epsilon
      && inner.maxY <= outer.maxY + epsilon
  }

}
