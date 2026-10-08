import Foundation

public enum CharacterColorError: Error, Sendable, Equatable {
  case nonFiniteComponent(field: String, value: Double)
  case componentOutOfRange(field: String, value: Double)
}

public struct CharacterColor: Sendable, Equatable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) throws {
    for (field, value) in [("red", red), ("green", green), ("blue", blue), ("alpha", alpha)] {
      guard value.isFinite else { throw CharacterColorError.nonFiniteComponent(field: field, value: value) }
      guard (0...1).contains(value) else { throw CharacterColorError.componentOutOfRange(field: field, value: value) }
    }
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  init(uncheckedRed red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public var relativeLuminance: Double {
    func linear(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  public func contrastRatio(with other: CharacterColor) -> Double {
    let a = relativeLuminance
    let b = other.relativeLuminance
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}
