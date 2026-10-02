import Foundation

/// A validated normalized boundary for one visual part.
public struct CharacterRegion: Sendable, Equatable, Hashable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(
    name: String = "custom",
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) throws {
    let values = [x, y, width, height]
    guard values.allSatisfy(\.isFinite) else {
      throw CharacterAppearanceError.invalidRegion(
        name: name,
        reason: "all values must be finite"
      )
    }
    guard width > 0, height > 0 else {
      throw CharacterAppearanceError.invalidRegion(
        name: name,
        reason: "width and height must be positive"
      )
    }
    guard x >= 0, y >= 0, x + width <= 1, y + height <= 1 else {
      throw CharacterAppearanceError.invalidRegion(
        name: name,
        reason: "bounds must remain inside 0...1"
      )
    }
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  fileprivate init(
    uncheckedX x: Double,
    y: Double,
    width: Double,
    height: Double
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

/// Owns the independent normalized bounds of eyes, nose, mouth, and writing.
public struct CharacterLayout: Sendable, Equatable {
  public let eyes: CharacterRegion
  public let nose: CharacterRegion
  public let mouth: CharacterRegion
  public let writing: CharacterRegion

  public init(
    eyes: CharacterRegion,
    nose: CharacterRegion,
    mouth: CharacterRegion,
    writing: CharacterRegion
  ) {
    self.eyes = eyes
    self.nose = nose
    self.mouth = mouth
    self.writing = writing
  }

  /// Default composition for the circular character.
  /// The writing region is a compact outer-corner activity accessory; every renderer is clipped.
  public static let `default` = Self(
    eyes: .init(uncheckedX: 0.08, y: 0.06, width: 0.84, height: 0.64),
    nose: .init(uncheckedX: 0.42, y: 0.50, width: 0.16, height: 0.12),
    // Keep a positive vertical gap below the full eye band (0.06...0.70).
    mouth: .init(uncheckedX: 0.28, y: 0.71, width: 0.44, height: 0.12),
    // Writing is an activity accessory, not a second face feature. Keep it in
    // the compact lower-right corner so it clears the mouth and eye bands.
    writing: .init(uncheckedX: 0.80, y: 0.85, width: 0.18, height: 0.12)
  )

  /// Non-overlapping bands for applications that enable all optional parts together.
  public static let strict = Self(
    eyes: .init(uncheckedX: 0.12, y: 0.08, width: 0.76, height: 0.37),
    nose: .init(uncheckedX: 0.42, y: 0.47, width: 0.16, height: 0.10),
    mouth: .init(uncheckedX: 0.27, y: 0.59, width: 0.46, height: 0.11),
    writing: .init(uncheckedX: 0.80, y: 0.82, width: 0.18, height: 0.15)
  )

  /// Large expressive face with extra breathing room around the mouth and ornaments.
  public static let hero = Self(
    eyes: .init(uncheckedX: 0.08, y: 0.10, width: 0.84, height: 0.50),
    nose: .init(uncheckedX: 0.43, y: 0.50, width: 0.14, height: 0.09),
    mouth: .init(uncheckedX: 0.25, y: 0.64, width: 0.50, height: 0.16),
    writing: .init(uncheckedX: 0.77, y: 0.80, width: 0.20, height: 0.16)
  )

  /// Standard face staging: large eyes above a centered, independently authored mouth band.
  /// The mouth remains invisible in neutral silence; writing has its own lower-right band.
  public static let standard = Self(
    eyes: .init(uncheckedX: 0.14, y: 0.23, width: 0.72, height: 0.46),
    nose: .init(uncheckedX: 0.46, y: 0.60, width: 0.08, height: 0.05),
    mouth: .init(uncheckedX: 0.30, y: 0.71, width: 0.40, height: 0.17),
    writing: .init(uncheckedX: 0.76, y: 0.82, width: 0.16, height: 0.12)
  )

  /// Fills a standalone view with the eye character while preserving eye containment.
  public static let eyesOnly = Self(
    eyes: .init(uncheckedX: 0.04, y: 0.05, width: 0.92, height: 0.90),
    nose: .init(uncheckedX: 0.45, y: 0.48, width: 0.10, height: 0.08),
    mouth: .init(uncheckedX: 0.30, y: 0.66, width: 0.40, height: 0.12),
    writing: .init(uncheckedX: 0.80, y: 0.80, width: 0.18, height: 0.16)
  )

  /// Fills a transparent standalone view with the writing gesture.
  public static let writingOnly = Self(
    eyes: .init(uncheckedX: 0.10, y: 0.10, width: 0.80, height: 0.35),
    nose: .init(uncheckedX: 0.45, y: 0.42, width: 0.10, height: 0.08),
    mouth: .init(uncheckedX: 0.30, y: 0.50, width: 0.40, height: 0.12),
    writing: .init(uncheckedX: 0.03, y: 0.08, width: 0.94, height: 0.84)
  )
}
