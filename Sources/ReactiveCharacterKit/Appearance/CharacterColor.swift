import Foundation

public struct CharacterColor: Sendable, Equatable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double = 1
  ) throws {
    for (field, value) in [
      ("red", red),
      ("green", green),
      ("blue", blue),
      ("alpha", alpha),
    ] {
      guard value.isFinite else {
        throw CharacterAppearanceError.nonFiniteColorComponent(field: field, value: value)
      }
      guard (0...1).contains(value) else {
        throw CharacterAppearanceError.colorComponentOutOfRange(field: field, value: value)
      }
    }
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  init(
    uncheckedRed red: Double,
    green: Double,
    blue: Double,
    alpha: Double = 1
  ) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let surfaceDefault = Self(
    uncheckedRed: 0.025,
    green: 0.024,
    blue: 0.036
  )

  public static let featureDefault = Self(
    uncheckedRed: 0.80,
    green: 0.74,
    blue: 0.98
  )

  public static let accentDefault = Self(
    uncheckedRed: 0.88,
    green: 0.82,
    blue: 1.0,
    alpha: 0.94
  )
}

extension CharacterColor {
  /// Deterministic companion shade for a runtime-customized surface color.
  /// Keeps the same hue family without creating a second configurable color owner.
  var characterShade: Self {
    Self(
      uncheckedRed: red * 0.72,
      green: green * 0.72,
      blue: blue * 0.72,
      alpha: alpha
    )
  }

  /// WCAG sRGB luminance math; callers must account for compositing/gradients.
  public var relativeLuminance: Double {
    func linear(_ v: Double) -> Double {
      v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// Opaque endpoint contrast only. This does not certify rendered accessibility.
  public func contrastRatio(with other: CharacterColor) -> Double {
    let a = relativeLuminance
    let b = other.relativeLuminance
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}
