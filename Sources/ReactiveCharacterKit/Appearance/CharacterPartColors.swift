import Foundation

/// Concrete visual colors for independently controllable character parts.
///
/// These values are presentation configuration only. They never encode semantic emotion or
/// execution state, so changing color cannot change reducer decisions.
/// Defaults resolve once at initialization; `replacing` changes only named roles.
/// `accent` owns portrait clothing, `clothingDetail` owns collar/cuffs, `outline` owns
/// anatomy contours, and `brows` is independent of the eyes. Surface material roles apply
/// to procedural round artwork; raster-reference materials keep their explicit appearance API.
public struct CharacterPartColors: Sendable, Equatable {
  public let surface: CharacterColor
  public let eyes: CharacterColor
  public let nose: CharacterColor
  public let mouth: CharacterColor
  public let mouthDetail: CharacterColor
  public let tongue: CharacterColor
  public let writing: CharacterColor
  public let accent: CharacterColor
  public let accessory: CharacterColor
  public let accessoryDetail: CharacterColor

  public let outline: CharacterColor
  public let brows: CharacterColor
  public let clothingDetail: CharacterColor
  public let surfaceShade: CharacterColor
  public let surfaceHighlight: CharacterColor
  public let surfaceRim: CharacterColor

  public init(
    surface: CharacterColor = .surfaceDefault,
    eyes: CharacterColor = .featureDefault,
    nose: CharacterColor? = nil,
    mouth: CharacterColor = .featureDefault,
    mouthDetail: CharacterColor? = nil,
    tongue: CharacterColor? = nil,
    writing: CharacterColor = .featureDefault,
    accent: CharacterColor? = nil,
    accessory: CharacterColor? = nil,
    accessoryDetail: CharacterColor? = nil,
    outline: CharacterColor? = nil,
    brows: CharacterColor? = nil,
    clothingDetail: CharacterColor? = nil,
    surfaceShade: CharacterColor? = nil,
    surfaceHighlight: CharacterColor? = nil,
    surfaceRim: CharacterColor? = nil
  ) {
    let resolvedAccent = accent ?? .accentDefault
    self.surface = surface
    self.eyes = eyes
    self.nose = nose ?? eyes
    self.mouth = mouth
    self.mouthDetail = mouthDetail ?? eyes
    self.tongue = tongue ?? resolvedAccent
    self.writing = writing
    self.accent = resolvedAccent
    self.accessory = accessory ?? resolvedAccent
    self.accessoryDetail = accessoryDetail ?? eyes
    self.outline = outline ?? mouth
    self.brows = brows ?? eyes
    self.clothingDetail = clothingDetail ?? surface
    let bright = surface.relativeLuminance > 0.5
    let shadeFactor = bright ? 0.72 : 0.35
    self.surfaceShade = surfaceShade ?? CharacterColor(
      uncheckedRed: surface.red * shadeFactor, green: surface.green * shadeFactor,
      blue: surface.blue * shadeFactor, alpha: surface.alpha)
    self.surfaceHighlight = surfaceHighlight ?? CharacterColor(
      uncheckedRed: bright ? 1 : 0.86, green: bright ? 1 : 0.86,
      blue: bright ? 1 : 0.88, alpha: surface.alpha)
    self.surfaceRim = surfaceRim ?? CharacterColor(
      uncheckedRed: bright ? 0.48 : 0.32, green: bright ? 0.48 : 0.32,
      blue: bright ? 0.50 : 0.34, alpha: surface.alpha)
  }

  public func replacing(
    surface: CharacterColor? = nil,
    eyes: CharacterColor? = nil,
    nose: CharacterColor? = nil,
    mouth: CharacterColor? = nil,
    mouthDetail: CharacterColor? = nil,
    tongue: CharacterColor? = nil,
    writing: CharacterColor? = nil,
    accent: CharacterColor? = nil,
    accessory: CharacterColor? = nil,
    accessoryDetail: CharacterColor? = nil,
    outline: CharacterColor? = nil,
    brows: CharacterColor? = nil,
    clothingDetail: CharacterColor? = nil,
    surfaceShade: CharacterColor? = nil,
    surfaceHighlight: CharacterColor? = nil,
    surfaceRim: CharacterColor? = nil
  ) -> Self {
    Self(
      surface: surface ?? self.surface,
      eyes: eyes ?? self.eyes,
      nose: nose ?? self.nose,
      mouth: mouth ?? self.mouth,
      mouthDetail: mouthDetail ?? self.mouthDetail,
      tongue: tongue ?? self.tongue,
      writing: writing ?? self.writing,
      accent: accent ?? self.accent,
      accessory: accessory ?? self.accessory,
      accessoryDetail: accessoryDetail ?? self.accessoryDetail,
      outline: outline ?? self.outline,
      brows: brows ?? self.brows,
      clothingDetail: clothingDetail ?? self.clothingDetail,
      surfaceShade: surfaceShade ?? self.surfaceShade,
      surfaceHighlight: surfaceHighlight ?? self.surfaceHighlight,
      surfaceRim: surfaceRim ?? self.surfaceRim
    )
  }

  public static let `default` = Self()
}
