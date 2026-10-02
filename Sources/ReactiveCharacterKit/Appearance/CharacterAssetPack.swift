import Foundation

/// Where the renderer resolves an image resource.
public enum CharacterAssetSource: String, Sendable, Equatable, Hashable, CaseIterable {
  /// Resolve from CharacterKit's Swift Package resource bundle.
  case package
  /// Resolve from the host application's main bundle.
  case application
}

public enum CharacterAssetError: Error, Sendable, Equatable {
  case invalidName
  case invalidValue(field: String, value: Double)
}

/// A lightweight reference to local artwork. Resolution uses package/application bundles only.
public struct CharacterImageAsset: Sendable, Equatable, Hashable {
  public let name: String
  public let source: CharacterAssetSource

  public init(name: String, source: CharacterAssetSource = .application) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CharacterAssetError.invalidName }
    self.name = trimmed
    self.source = source
  }

  init(uncheckedName name: String, source: CharacterAssetSource) {
    self.name = name
    self.source = source
  }
}

/// The feature region an accessory follows when the art direction changes layout.
public enum CharacterAssetAnchor: String, Sendable, Equatable, Hashable, CaseIterable {
  case face
  case eyes
  case nose
  case mouth
  case writing
}

/// Accessories are intentionally limited to two painter layers.
public enum CharacterAssetLayer: String, Sendable, Equatable, Hashable, CaseIterable {
  case behindFeatures
  case foreground
}

/// Image artwork positioned relative to one normalized feature region.
public struct CharacterAccessoryAsset: Sendable, Equatable, Hashable {
  public let image: CharacterImageAsset
  public let anchor: CharacterAssetAnchor
  public let layer: CharacterAssetLayer
  public let centerX: Double
  public let centerY: Double
  public let width: Double
  public let height: Double
  public let angle: Double
  public let opacity: Double
  public let accessibilityLabel: String?

  public init(
    image: CharacterImageAsset,
    anchor: CharacterAssetAnchor = .face,
    layer: CharacterAssetLayer = .foreground,
    centerX: Double = 0.5,
    centerY: Double = 0.5,
    width: Double,
    height: Double,
    angle: Double = 0,
    opacity: Double = 1,
    accessibilityLabel: String? = nil
  ) throws {
    try CharacterAccessoryValidation.validate(
      centerX: centerX, centerY: centerY, width: width, height: height,
      angle: angle, opacity: opacity, centerRange: -1...2, maximumSize: 3,
      invalidValue: { CharacterAssetError.invalidValue(field: $0, value: $1) })
    self.image = image
    self.anchor = anchor
    self.layer = layer
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.opacity = opacity
    self.accessibilityLabel = accessibilityLabel
  }

  init(
    uncheckedImage image: CharacterImageAsset,
    anchor: CharacterAssetAnchor,
    layer: CharacterAssetLayer,
    centerX: Double,
    centerY: Double,
    width: Double,
    height: Double,
    angle: Double = 0,
    opacity: Double = 1,
    accessibilityLabel: String? = nil
  ) {
    self.image = image
    self.anchor = anchor
    self.layer = layer
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.opacity = opacity
    self.accessibilityLabel = accessibilityLabel
  }
}

/// Static artwork used by one art direction.
///
/// The background and face are optional. When `face` is absent the hybrid renderer draws
/// a procedural surface, so a custom design can start with colors only and add artwork later.
public struct CharacterAssetPack: Sendable, Equatable {
  public let background: CharacterImageAsset?
  public let face: CharacterImageAsset?
  public let accessories: [CharacterAccessoryAsset]

  public init(
    background: CharacterImageAsset? = nil,
    face: CharacterImageAsset? = nil,
    accessories: [CharacterAccessoryAsset] = []
  ) {
    self.background = background
    self.face = face
    self.accessories = accessories
  }

  public static let empty = Self()
}

extension CharacterImageAsset {
  /// Palette-matched built-in headset artwork. Geometry and occlusion are identical across variants.
  public static let blackHeadset = Self(uncheckedName: "headset-black", source: .package)
  public static let whiteHeadset = Self(uncheckedName: "headset-white", source: .package)
  public static let arcadeHeadset = Self(uncheckedName: "headset-arcade", source: .package)

  public static let hood = Self(uncheckedName: "hood", source: .package)
  public static let baseballCap = Self(uncheckedName: "baseballCap", source: .package)
  public static let bunnyEars = Self(uncheckedName: "bunnyEars", source: .package)
}

extension CharacterAccessoryAsset {
  public static let blackHeadset = CharacterBuiltInAccessoryCatalog.headset(image: .blackHeadset)
    .asset
  public static let whiteHeadset = CharacterBuiltInAccessoryCatalog.headset(image: .whiteHeadset)
    .asset
  public static let arcadeHeadset = CharacterBuiltInAccessoryCatalog.headset(image: .arcadeHeadset)
    .asset
  public static let hood = CharacterBuiltInAccessoryCatalog.hood.asset
  public static let baseballCap = CharacterBuiltInAccessoryCatalog.baseballCap.asset
  public static let bunnyEars = CharacterBuiltInAccessoryCatalog.bunnyEars.asset
}

extension CharacterAssetPack {
  /// Palette-matched artwork packs. Face geometry remains identical.
  public static let black = Self(accessories: [.blackHeadset])
  public static let white = Self(accessories: [.whiteHeadset])
  public static let arcade = Self(accessories: [.arcadeHeadset])
}
