import Foundation

public struct CharacterDesignAccessory: Codable, Sendable, Equatable {
  public var id: String
  public var label: String
  public var glyph: CharacterDesignAccessoryGlyph
  public var anchor: CharacterAccessoryAnchor
  public var layer: CharacterAccessoryLayer
  public var centerX: Double
  public var centerY: Double
  public var width: Double
  public var height: Double
  public var angle: Double
  public var opacity: Double
  public var color: CharacterDesignColorRole

  public init(
    id: String,
    label: String,
    glyph: CharacterDesignAccessoryGlyph,
    anchor: CharacterAccessoryAnchor = .face,
    layer: CharacterAccessoryLayer = .foreground,
    centerX: Double = 0.5,
    centerY: Double = 0.5,
    width: Double,
    height: Double,
    angle: Double = 0,
    opacity: Double = 1,
    color: CharacterDesignColorRole = .accent
  ) {
    self.id = id
    self.label = label
    self.glyph = glyph
    self.anchor = anchor
    self.layer = layer
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.opacity = opacity
    self.color = color
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, label, glyph, anchor, layer, centerX, centerY, width, height, angle, opacity, color
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    label = try values.decode(String.self, forKey: .label)
    glyph = try values.decode(CharacterDesignAccessoryGlyph.self, forKey: .glyph)
    anchor = try values.decode(CharacterAccessoryAnchor.self, forKey: .anchor)
    layer = try values.decode(CharacterAccessoryLayer.self, forKey: .layer)
    centerX = try values.decode(Double.self, forKey: .centerX)
    centerY = try values.decode(Double.self, forKey: .centerY)
    width = try values.decode(Double.self, forKey: .width)
    height = try values.decode(Double.self, forKey: .height)
    angle = try values.decode(Double.self, forKey: .angle)
    opacity = try values.decode(Double.self, forKey: .opacity)
    color = try values.decode(CharacterDesignColorRole.self, forKey: .color)
  }
}

extension CharacterDesignAccessory {
  /// Authored vector artwork plus default placement; callers can edit any field
  /// and compile the enclosing profile. No semantic events are generated.
  public static func recommended(_ glyph: CharacterDesignAccessoryGlyph) -> Self {
    switch glyph {
    case .roundGlasses:
      Self(
        id: "glasses", label: "Round glasses", glyph: glyph, anchor: .eyes,
        width: 1.04, height: 0.92, color: .accent)
    case .visor:
      Self(id: "visor", label: "Visor", glyph: glyph, centerY: 0.20, width: 0.64, height: 0.17)
    case .crown:
      Self(id: "crown", label: "Crown", glyph: glyph, centerY: 0.07, width: 0.42, height: 0.22)
    case .bowTie:
      Self(id: "bow-tie", label: "Bow tie", glyph: glyph, centerY: 0.88, width: 0.28, height: 0.14)
    case .badge:
      Self(
        id: "badge", label: "Badge", glyph: glyph, centerX: 0.81, centerY: 0.70, width: 0.14,
        height: 0.14)
    case .headphones:
      Self(
        id: "headphones", label: "Headphones", glyph: glyph, centerY: 0.39, width: 1.04,
        height: 0.83)
    case .halo:
      Self(id: "halo", label: "Halo", glyph: glyph, centerY: 0.015, width: 0.58, height: 0.16)
    }
  }
}

public struct CharacterDesignedAccessory: Sendable, Equatable {
  public let id: String
  public let label: String
  public let glyph: CharacterDesignAccessoryGlyph
  public let placement: CharacterAccessoryPlacement
  public let color: CharacterDesignColorRole
}
