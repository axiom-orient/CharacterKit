import Foundation

/// Presentation-only choices. They never change emotion, task identity or the session clock.
public struct CharacterPortraitStyle: Sendable, Equatable {
  public enum Hairstyle: String, CaseIterable, Sendable, Hashable {
    case bob
    case sidePart = "side-part"
    case crop
  }

  public enum Eyewear: String, CaseIterable, Sendable, Hashable {
    case none
    case sunglasses
    case loweredSunglasses = "lowered-sunglasses"
  }

  /// The visible adornment, including clips, flowers and caps.
  public enum HairAccessory: String, CaseIterable, Sendable, Hashable {
    case none, bar, cross, flower
    case backwardCap = "backward-cap"
  }

  /// Authored camera views, independent of attention/gaze. Only Boy can select these views.
  public enum BoyViewpoint: String, CaseIterable, Sendable, Hashable {
    case front
    case threeQuarterRight = "three-quarter-right"
  }

  enum ClassicHairstyle: Sendable, Equatable {
    case bob, sidePart
  }

  enum Head: Sendable, Equatable {
    case classic(ClassicHairstyle)
    case boy(BoyViewpoint)
  }

  let head: Head
  public var hairstyle: Hairstyle {
    switch head {
    case .classic(.bob): .bob
    case .classic(.sidePart): .sidePart
    case .boy: .crop
    }
  }
  public var boyViewpoint: BoyViewpoint? {
    guard case .boy(let viewpoint) = head else { return nil }
    return viewpoint
  }
  public let eyewear: Eyewear
  public let hairAccessory: HairAccessory
  public let hairColor: CharacterColor

  public init(
    hairstyle: Hairstyle = .bob, eyewear: Eyewear = .none,
    hairAccessory: HairAccessory = .bar,
    hairColor: CharacterColor = CharacterPortraitStyle.defaultHairColor
  ) {
    switch hairstyle {
    case .bob: head = .classic(.bob)
    case .sidePart: head = .classic(.sidePart)
    case .crop: head = .boy(.front)
    }
    self.hairAccessory = hairAccessory
    self.eyewear = eyewear
    self.hairColor = hairColor
  }

  public static let standard = Self()
  /// Shared expression channels; each anatomy owns its reference proportions.
  public static let bobGirl = Self(hairstyle: .bob, hairAccessory: .cross)
  public static let shortHairBoy = boy(viewpoint: .front, hairAccessory: .none)
  public static let flowerGirl = Self(hairstyle: .bob, hairAccessory: .flower)
  public static let cappedBoy = boy(viewpoint: .front)
  public static let defaultHairColor = CharacterColor(
    uncheckedRed: 0.025, green: 0.025, blue: 0.025)

  public static let defaultBoyHairColor = CharacterColor(
    uncheckedRed: 34.0 / 255, green: 34.0 / 255, blue: 34.0 / 255)

  /// The ordinary Boy wears a cap; use `.none` for the supplied anime-hair reference.
  /// Unlike a free camera field on every portrait, this cannot create an unsupported Bob view.
  public static func boy(
    viewpoint: BoyViewpoint,
    eyewear: Eyewear = .none,
    hairAccessory: HairAccessory = .backwardCap,
    hairColor: CharacterColor = defaultBoyHairColor
  ) -> Self {
    Self(viewpoint: viewpoint, eyewear: eyewear, hairAccessory: hairAccessory, hairColor: hairColor)
  }

  private init(
    viewpoint: BoyViewpoint, eyewear: Eyewear,
    hairAccessory: HairAccessory, hairColor: CharacterColor
  ) {
    head = .boy(viewpoint)
    self.eyewear = eyewear
    self.hairAccessory = hairAccessory
    self.hairColor = hairColor
  }

  public var artDirection: CharacterArtDirection {
    CharacterArtDirection.portrait(self)
  }

  /// Selects visible components through the public API, without recreating portrait anatomy.
  /// Skin/outline can be hidden while live facial features remain available for composition.
  public func artDirection(
    components: CharacterComponents, surface: CharacterSurface = .visible
  ) -> CharacterArtDirection {
    CharacterArtDirection.portrait(self, components: components, surface: surface)
  }
}

extension CharacterArtDirection {
  public static let portrait = CharacterPortraitStyle.standard.artDirection
}

extension CharacterStyle {
  /// A small-feature, eyebrow-led, flat portrait. No authored bitmap resources are required.
  public static let portrait: Self = {
    do {
      let ink = try CharacterColor(red: 0.035, green: 0.035, blue: 0.035)
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 0.99, green: 0.99, blue: 0.985),
          eyes: ink, mouth: ink,
          mouthDetail: CharacterColor(red: 0.99, green: 0.99, blue: 0.985),
          tongue: CharacterColor(red: 0.78, green: 0.48, blue: 0.47),
          writing: ink,
          accent: CharacterColor(red: 0.65, green: 0.65, blue: 0.63),
          accessory: CharacterColor(red: 0.23, green: 0.23, blue: 0.23),
          accessoryDetail: CharacterColor(red: 0.40, green: 0.40, blue: 0.39)),
        eyeTreatment: .vertical, mouthTreatment: .outline, lineWidth: 0.010)
    } catch { preconditionFailure("Invalid built-in portrait style: \(error)") }
  }()
}


extension CharacterStyle {
  /// The supplied Boy's palette; the existing Bob/Side-part palette remains unchanged.
  static let portraitBoy = portrait.replacingPartColors(
    CharacterPartColors(
      surface: CharacterColor(uncheckedRed: 254.0 / 255, green: 254.0 / 255, blue: 254.0 / 255),
      eyes: CharacterColor(uncheckedRed: 7.0 / 255, green: 7.0 / 255, blue: 7.0 / 255),
      mouth: CharacterColor(uncheckedRed: 10.0 / 255, green: 10.0 / 255, blue: 10.0 / 255),
      mouthDetail: CharacterColor(uncheckedRed: 254.0 / 255, green: 254.0 / 255, blue: 254.0 / 255),
      tongue: CharacterColor(uncheckedRed: 0.78, green: 0.48, blue: 0.47),
      writing: CharacterColor(uncheckedRed: 10.0 / 255, green: 10.0 / 255, blue: 10.0 / 255),
      accent: CharacterColor(uncheckedRed: 161.0 / 255, green: 159.0 / 255, blue: 155.0 / 255),
      accessory: CharacterColor(uncheckedRed: 0.23, green: 0.23, blue: 0.23),
      accessoryDetail: CharacterColor(uncheckedRed: 0.40, green: 0.40, blue: 0.39)))
}
