#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  extension CharacterCatSupplementalAsset {
    /// Resolves a package-owned supplemental asset into the existing host overlay boundary.
    /// Failure is explicit; no substitute artwork is manufactured.
    public func accessoryOverlay(
      placement: CharacterAccessoryPlacement = .catPawSticker,
      tint: CharacterColor? = nil,
      accessibilityLabel: String? = nil
    ) throws -> CharacterAccessoryOverlay {
      let url = try packageURL(for: .png)
      let image = try CharacterPlatformImageLoader.load(url: url, name: rawValue)
      return CharacterAccessoryOverlay(
        image: image.characterSwiftUIImage,
        placement: placement,
        tint: tint,
        accessibilityLabel: accessibilityLabel ?? name
      )
    }
  }
  @available(iOS 16.0, macOS 13.0, *)
  extension CharacterPawVariant {
    public func accessoryOverlay(
      placement: CharacterAccessoryPlacement = .catPawSticker,
      tint: CharacterColor? = nil, accessibilityLabel: String? = nil
    ) throws -> CharacterAccessoryOverlay {
      let image = try CharacterPlatformImageLoader.load(
        url: packageURL(for: .png), name: resourceName)
      return CharacterAccessoryOverlay(
        image: image.characterSwiftUIImage, placement: placement, tint: tint,
        accessibilityLabel: accessibilityLabel ?? name)
    }
  }
#endif
