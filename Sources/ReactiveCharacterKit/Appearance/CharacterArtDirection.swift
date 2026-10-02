import Foundation

/// Validation failures for a visual configuration.
public enum CharacterArtDirectionError: Error, Sendable, Equatable {
  case invalidName
  case conflictingFaceAsset
  case unsupportedAnatomyConfiguration(field: String)
  case invalidValue(field: String, value: Double)
}

/// The complete visual configuration for a character.
///
/// Replacing this value changes presentation only. Semantic state remains owned by
/// `CharacterState` and `CharacterReducer`.
public struct CharacterArtDirection: Sendable, Equatable {
  public let name: String
  public let anatomy: CharacterAnatomy
  public let components: CharacterComponents
  public let layout: CharacterLayout
  public let style: CharacterStyle
  public let surface: CharacterSurface
  public let projection: CharacterProjection
  public let motionProfile: CharacterMotionProfile
  public let transitionProfile: CharacterTransitionProfile
  public let assets: CharacterAssetPack
  public let featureGlow: Double
  public let ornamentGlow: Double
  public let contentInset: Double

  /// One face frame for all built-in appearances. A palette must never resize the character.
  public static let canonicalContentInset = 0.12

  public init(
    name: String,
    components: CharacterComponents = .default,
    layout: CharacterLayout = .standard,
    style: CharacterStyle = .black,
    surface: CharacterSurface = .visible,
    projection: CharacterProjection = .softSphere,
    motionProfile: CharacterMotionProfile = .expressive,
    transitionProfile: CharacterTransitionProfile = .expressive,
    assets: CharacterAssetPack = .empty,
    featureGlow: Double = 0,
    ornamentGlow: Double = 0,
    contentInset: Double = 0,
    anatomy: CharacterAnatomy = .minimal
  ) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CharacterArtDirectionError.invalidName }
    for (field, value) in [("featureGlow", featureGlow), ("ornamentGlow", ornamentGlow)] {
      guard value.isFinite, (0...1.5).contains(value) else {
        throw CharacterArtDirectionError.invalidValue(field: field, value: value)
      }
    }
    guard contentInset.isFinite, (0...0.25).contains(contentInset) else {
      throw CharacterArtDirectionError.invalidValue(field: "contentInset", value: contentInset)
    }
    if assets.face != nil, anatomy != .minimal {
      throw CharacterArtDirectionError.conflictingFaceAsset
    }
    if anatomy != .minimal {
      guard layout == .standard else {
        throw CharacterArtDirectionError.unsupportedAnatomyConfiguration(field: "layout")
      }
      guard featureGlow == 0 else {
        throw CharacterArtDirectionError.unsupportedAnatomyConfiguration(field: "featureGlow")
      }
    }
    self.anatomy = anatomy
    self.name = trimmed
    self.components = components
    self.layout = layout
    self.style = style
    self.surface = surface
    self.projection = projection
    self.motionProfile = motionProfile
    self.transitionProfile = transitionProfile
    self.assets = assets
    self.featureGlow = featureGlow
    self.ornamentGlow = ornamentGlow
    self.contentInset = contentInset
  }

  public func replacingMotionProfile(_ motionProfile: CharacterMotionProfile) -> Self {
    rebuilt(style: style, motionProfile: motionProfile)
  }

  /// Recolors procedural parts without changing geometry or semantic state.
  /// Authored bitmap fur, noses and accessories retain their original artwork colors.
  public func replacingPartColors(_ partColors: CharacterPartColors) -> Self {
    rebuilt(style: style.replacingPartColors(partColors))
  }

  /// Changes only eye/mouth presentation treatment. Emotion still owns the expression itself.
  public func replacingFaceTreatment(
    eyes: CharacterEyeTreatment? = nil,
    mouth: CharacterMouthTreatment? = nil
  ) -> Self {
    rebuilt(style: style.replacingFaceTreatment(eyes: eyes, mouth: mouth))
  }

  /// Changes smile-eye geometry while preserving anatomy and the rest of the visual configuration.
  public func replacingSmileEyeShape(_ shape: CharacterSmileEyeShape) -> Self {
    rebuilt(style: style.replacingSmileEyeShape(shape))
  }

  private func rebuilt(
    style: CharacterStyle, motionProfile: CharacterMotionProfile? = nil
  ) -> Self {
    Self(
      uncheckedName: name, components: components, layout: layout, style: style,
      surface: surface, projection: projection, motionProfile: motionProfile ?? self.motionProfile,
      transitionProfile: transitionProfile, assets: assets, featureGlow: featureGlow,
      ornamentGlow: ornamentGlow, contentInset: contentInset, anatomy: anatomy)
  }

  /// A portrait preset with its native layout, palette and motion policy.
  static func portrait(
    _ portraitStyle: CharacterPortraitStyle,
    components: CharacterComponents = .default.union(.writing),
    surface: CharacterSurface = .visible
  ) -> Self {
    Self(
      uncheckedName: "Portrait", components: components, layout: .standard,
      style: portraitStyle.boyViewpoint == nil ? .portrait : .portraitBoy,
      surface: surface, projection: .softSphere, motionProfile: .cartoon,
      transitionProfile: .cartoon, assets: .empty, featureGlow: 0, ornamentGlow: 0,
      contentInset: canonicalContentInset, anatomy: .portrait(portraitStyle))
  }

  /// Selects the authored rig without creating a second pose, reducer or renderer.
  public static func reference(
    _ appearance: CharacterReferenceAppearance,
    components: CharacterComponents = .default.union([.nose, .writing])
  ) -> Self {
    let appearance: CharacterReferenceAppearance = if !components.contains(.accessories),
      case .mascot(let variant, let body, _) = appearance {
      .mascot(variant: variant, body: body, headset: nil)
    } else { appearance }
    return Self(
      uncheckedName: appearance.isCat ? "Norwegian Forest Cat" : "Reference Mascot",
      components: components, layout: .standard,
      style: appearance.isCat ? .catNorwegianForest : .black,
      surface: .visible, projection: .flat, motionProfile: .cartoon,
      transitionProfile: .cartoon, assets: .empty, featureGlow: 0, ornamentGlow: 0,
      contentInset: 0, anatomy: .reference(appearance))
  }

  private init(
    uncheckedName name: String,
    components: CharacterComponents,
    layout: CharacterLayout,
    style: CharacterStyle,
    surface: CharacterSurface,
    projection: CharacterProjection,
    motionProfile: CharacterMotionProfile,
    transitionProfile: CharacterTransitionProfile,
    assets: CharacterAssetPack,
    featureGlow: Double,
    ornamentGlow: Double,
    contentInset: Double,
    anatomy: CharacterAnatomy
  ) {
    self.name = name
    self.anatomy = anatomy
    self.components = components
    self.layout = layout
    self.style = style
    self.surface = surface
    self.projection = projection
    self.motionProfile = motionProfile
    self.transitionProfile = transitionProfile
    self.assets = assets
    self.featureGlow = featureGlow
    self.ornamentGlow = ornamentGlow
    self.contentInset = contentInset
  }
}

// These are references only. Resolving bytes stays in the I/O adapter.
extension CharacterArtDirection {
  public var requiredImageAssets: [CharacterImageAsset] {
    var result = [assets.background, assets.face].compactMap { $0 }
    if components.contains(.accessories) { result += assets.accessories.map(\.image) }
    if case .reference(let appearance) = anatomy {
      result += appearance.rig.layers.flatMap { layer -> [CharacterImageAsset] in
        guard !layer.part.isHardware || components.contains(.accessories) else { return [] }
        return [appearance.asset(for: layer)].compactMap { $0 }
      }
      result.append(.init(uncheckedName: "reference-\(appearance.artworkID.rawValue)-backdrop", source: .package))
    } else if case .cat(.animated) = anatomy {
      if surface == .visible { result += CharacterCatAssets.body }
      if components.contains(.nose) { result.append(CharacterCatAssets.nose) }
      if surface == .visible { result += CharacterCatAssets.whiskers }
    }
    var seen = Set<CharacterImageAsset>()
    return result.filter { seen.insert($0).inserted }
  }
}
