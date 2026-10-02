/// Authored silhouettes/pad treatments. Selection changes presentation, not semantic state.
/// The original CharacterCatSupplementalAsset.pawPad and its resource name are unchanged.
public enum CharacterPawVariant: String, CaseIterable, Sendable, Hashable, Identifiable {
  case front, back, open, tiny, badge, happy, excited, waving, heart, squish
  case blackHeart = "black-heart"
  case black, outline, silhouette, sparkles, love, dash

  public typealias Representation = CharacterCatSupplementalAsset.Representation
  public var id: String { rawValue }
  public var resourceName: String { "cat-paw-" + rawValue }
  public var name: String { "Cat Paw — " + rawValue.split(separator: "-").joined(separator: " ") }
  public var pngImageAsset: CharacterImageAsset {
    .init(uncheckedName: resourceName, source: .package)
  }
  public var artDirection: CharacterArtDirection {
    .pawAsset(pngImageAsset, name: name)
  }
}

extension CharacterArtDirection {
  static func pawAsset(_ image: CharacterImageAsset, name: String) -> Self {
    do {
      let paw = try CharacterAccessoryAsset(
        image: image, width: 0.92, height: 0.92, accessibilityLabel: name)
      return try Self(
        name: name, components: [.accessories], surface: .transparent,
        motionProfile: .cartoon, transitionProfile: .cartoon,
        assets: .init(accessories: [paw]), contentInset: canonicalContentInset)
    } catch { preconditionFailure("Invalid built-in paw presentation: \(error)") }
  }
}