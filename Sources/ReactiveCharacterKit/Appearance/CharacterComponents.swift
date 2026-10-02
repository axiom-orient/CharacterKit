/// Independently selectable visual parts. This configuration never changes semantic state.
/// `.default` is the simple face contract: eyes + mouth + accessories.
/// Nose and ornament overlays are explicit opt-in capabilities.
public struct CharacterComponents: OptionSet, Sendable, Hashable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let eyes = Self(rawValue: 1 << 0)
  public static let nose = Self(rawValue: 1 << 1)
  public static let mouth = Self(rawValue: 1 << 2)
  public static let writing = Self(rawValue: 1 << 3)
  public static let ornaments = Self(rawValue: 1 << 4)
  public static let accessories = Self(rawValue: 1 << 5)

  public static let `default`: Self = [.eyes, .mouth, .accessories]
  public static let face: Self = [.eyes, .mouth, .accessories]
  public static let all: Self = [.eyes, .nose, .mouth, .writing, .ornaments, .accessories]
}

public enum CharacterSurface: Sendable, Equatable {
  case visible
  case transparent
}
