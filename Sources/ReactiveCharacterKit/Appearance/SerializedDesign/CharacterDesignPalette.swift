import Foundation

/// Opaque sRGB colors. Profiles use explicit #RRGGBB, never platform-dependent names.
public struct CharacterDesignPalette: Sendable, Equatable {
  public let stage: CharacterColor
  public let surface: CharacterColor
  public let surfaceShade: CharacterColor
  public let eye: CharacterColor
  public let feature: CharacterColor
  public let detail: CharacterColor
  public let accent: CharacterColor
  public let outline: CharacterColor

  init(_ definition: CharacterDesignPaletteDefinition, path: String) throws {
    stage = try .designHex(definition.stage, path: "\(path).stage")
    surface = try .designHex(definition.surface, path: "\(path).surface")
    surfaceShade = try .designHex(definition.surfaceShade, path: "\(path).surfaceShade")
    feature = try .designHex(definition.feature, path: "\(path).feature")
    eye = try definition.eye.map { try .designHex($0, path: "\(path).eye") } ?? feature
    detail = try .designHex(definition.detail, path: "\(path).detail")
    accent = try .designHex(definition.accent, path: "\(path).accent")
    outline = try .designHex(definition.outline, path: "\(path).outline")
  }

  public func color(for role: CharacterDesignColorRole) -> CharacterColor {
    switch role {
    case .surface: surface
    case .feature: feature
    case .detail: detail
    case .accent: accent
    case .outline: outline
    }
  }

  var partColors: CharacterPartColors {
    CharacterPartColors(
      surface: surface, eyes: eye, nose: feature, mouth: feature,
      mouthDetail: detail, tongue: accent, writing: feature, accent: accent,
      accessory: accent, accessoryDetail: detail)
  }

  /// Explicit accessibility projection, not a persisted mutation of the profile.
  func increasedContrast() -> Self {
    let bright = surface.relativeLuminance > 0.5
    return Self(
      stage: stage, surface: bright ? .designWhite : .designBlack,
      surfaceShade: bright ? .designWhite : .designBlack,
      feature: bright ? .designBlack : .designWhite,
      detail: bright ? .designWhite : .designBlack,
      accent: bright ? .designBlack : .designWhite,
      outline: bright ? .designBlack : .designWhite)
  }

  private init(
    stage: CharacterColor, surface: CharacterColor, surfaceShade: CharacterColor,
    feature: CharacterColor, detail: CharacterColor, accent: CharacterColor, outline: CharacterColor
  ) {
    self.stage = stage
    self.surface = surface
    self.surfaceShade = surfaceShade
    self.eye = feature
    self.feature = feature
    self.detail = detail
    self.accent = accent
    self.outline = outline
  }
}

extension CharacterColor {
  static let designWhite = try! Self(red: 1, green: 1, blue: 1)
  static let designBlack = try! Self(red: 0, green: 0, blue: 0)

  static func designHex(_ text: String, path: String) throws -> Self {
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    guard text.utf8.count == 7, text.first == "#",
      text.dropFirst().unicodeScalars.allSatisfy({ allowed.contains($0) }),
      let rgb = UInt32(text.dropFirst(), radix: 16)
    else {
      throw CharacterDesignError.invalid(
        path: path, reason: "expected an opaque sRGB #RRGGBB color")
    }
    return try Self(
      red: Double((rgb >> 16) & 255) / 255,
      green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
  }
}

public struct CharacterDesignPalettes: Codable, Sendable, Equatable {
  public var light: CharacterDesignPaletteDefinition
  public var dark: CharacterDesignPaletteDefinition

  public init(
    light: CharacterDesignPaletteDefinition,
    dark: CharacterDesignPaletteDefinition
  ) {
    self.light = light
    self.dark = dark
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case light, dark
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    light = try values.decode(CharacterDesignPaletteDefinition.self, forKey: .light)
    dark = try values.decode(CharacterDesignPaletteDefinition.self, forKey: .dark)
  }
}

public struct CharacterDesignPaletteDefinition: Codable, Sendable, Equatable {
  public var stage: String
  public var surface: String
  public var surfaceShade: String
  public var feature: String
  /// Eye color must contrast with the face and surrounding colors. Nil inherits feature.
  public var eye: String?
  public var detail: String
  public var accent: String
  public var outline: String

  public init(
    stage: String,
    surface: String,
    surfaceShade: String,
    feature: String,
    detail: String,
    accent: String,
    outline: String,
    eye: String? = nil
  ) {
    self.stage = stage
    self.surface = surface
    self.surfaceShade = surfaceShade
    self.feature = feature
    self.eye = eye
    self.detail = detail
    self.accent = accent
    self.outline = outline
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case stage, surface, surfaceShade, feature, detail, accent, outline, eye
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    stage = try values.decode(String.self, forKey: .stage)
    surface = try values.decode(String.self, forKey: .surface)
    surfaceShade = try values.decode(String.self, forKey: .surfaceShade)
    eye = values.contains(.eye) ? try values.decode(String.self, forKey: .eye) : nil
    feature = try values.decode(String.self, forKey: .feature)
    detail = try values.decode(String.self, forKey: .detail)
    accent = try values.decode(String.self, forKey: .accent)
    outline = try values.decode(String.self, forKey: .outline)
  }
}
