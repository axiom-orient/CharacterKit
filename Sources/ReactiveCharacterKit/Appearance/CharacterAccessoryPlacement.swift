import Foundation

/// An attachment follows a layout region and the character's whole-surface pose.
/// It does not deform the eyes or mouth, and never changes semantic state.
public enum CharacterAccessoryAnchor: String, CaseIterable, Sendable, Equatable {
  case face
  case eyes
  case nose
  case mouth
  case writing
}

/// Stable painter order. Within one layer the caller's array order is preserved.
public enum CharacterAccessoryLayer: String, CaseIterable, Sendable, Equatable {
  case behindSurface
  case behindFeatures
  case foreground
}

public enum CharacterAccessoryPlacementError: Error, Sendable, Equatable {
  case invalidValue(field: String, value: Double)
}

/// A normalized image envelope relative to its anchor, not an image's pixel bounds.
/// Images are aspect-fitted inside this envelope. Angle is in radians.
public struct CharacterAccessoryPlacement: Sendable, Equatable {
  public let anchor: CharacterAccessoryAnchor
  public let layer: CharacterAccessoryLayer
  public let centerX: Double
  public let centerY: Double
  public let width: Double
  public let height: Double
  public let angle: Double
  public let opacity: Double

  /// Centers may extend beyond the anchor (-2...3); sizes must be in (0...4].
  /// These finite normalized bounds prevent unbounded offscreen drawing geometry.
  /// Opacity is 0...1; angle is -2π...2π. No values are silently repaired.
  public init(
    anchor: CharacterAccessoryAnchor = .face,
    layer: CharacterAccessoryLayer = .foreground,
    centerX: Double = 0.5,
    centerY: Double = 0.5,
    width: Double,
    height: Double,
    angle: Double = 0,
    opacity: Double = 1
  ) throws {
    try CharacterAccessoryValidation.validate(
      centerX: centerX, centerY: centerY, width: width, height: height,
      angle: angle, opacity: opacity, centerRange: -2...3, maximumSize: 4,
      invalidValue: { CharacterAccessoryPlacementError.invalidValue(field: $0, value: $1) })
    self.anchor = anchor
    self.layer = layer
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.opacity = opacity
  }

  // Slots, not bundled artwork. The host supplies each image.
  public static let glasses = try! Self(anchor: .eyes, width: 0.98, height: 0.85)
  public static let crown = try! Self(centerY: 0.12, width: 0.46, height: 0.22)
  public static let bowTie = try! Self(centerY: 0.89, width: 0.28, height: 0.16)
  public static let badge = try! Self(centerX: 0.82, centerY: 0.60, width: 0.14, height: 0.14)
}

/// Pure geometry shared by the iOS renderer and platform-independent tests.
enum CharacterAccessoryGeometry {
  static func envelope(
    for placement: CharacterAccessoryPlacement,
    face: CharacterRect,
    layout: CharacterLayout
  ) -> CharacterRect {
    let anchor: CharacterRect
    switch placement.anchor {
    case .face: anchor = face
    case .eyes: anchor = CharacterGeometry.map(layout.eyes, into: face)
    case .nose: anchor = CharacterGeometry.map(layout.nose, into: face)
    case .mouth: anchor = CharacterGeometry.map(layout.mouth, into: face)
    case .writing: anchor = CharacterGeometry.map(layout.writing, into: face)
    }
    let width = anchor.width * placement.width
    let height = anchor.height * placement.height
    return CharacterRect(
      x: anchor.x + anchor.width * placement.centerX - width / 2,
      y: anchor.y + anchor.height * placement.centerY - height / 2,
      width: width,
      height: height
    )
  }

  static func aspectFit(image: CharacterSize, in envelope: CharacterRect) -> CharacterRect? {
    guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0 else {
      return nil
    }
    let scale = min(envelope.width / image.width, envelope.height / image.height)
    let width = image.width * scale
    let height = image.height * scale
    return CharacterRect(
      x: envelope.midX - width / 2,
      y: envelope.midY - height / 2,
      width: width,
      height: height
    )
  }
}
