import Foundation

@testable import ReactiveCharacterKit

#if os(iOS)
  import UIKit
#endif

/// Reference-sheet fixtures retained for resource and source-glyph coverage tests.
/// Production face renderers use CharacterMouthGeometry and never swap to these bitmaps.
enum MouthReferenceRasterLibrary {
  private static let resourceSubdirectory = "MouthReferenceGlyphs"

  static func resourceURL(for glyph: CharacterMouthGlyph) -> URL? {
    let name = glyph.rawValue
    if let nested = Bundle.module.url(
      forResource: name,
      withExtension: "png",
      subdirectory: resourceSubdirectory
    ) {
      return nested
    }
    return Bundle.module.url(forResource: name, withExtension: "png")
  }

  #if os(iOS)
    @available(iOS 16.0, *)
    private static let cachedPlatformImages: [CharacterMouthGlyph: UIImage] = {
      Dictionary(
        uniqueKeysWithValues: CharacterMouthGlyph.allCases.compactMap { glyph in
          guard
            let image = try? CharacterPlatformImageLoader.load(
              url: resourceURL(for: glyph), name: glyph.rawValue)
          else {
            return nil
          }
          return (glyph, image)
        }
      )
    }()

    @available(iOS 16.0, *)
    static func platformImage(for glyph: CharacterMouthGlyph) throws -> UIImage {
      guard let image = cachedPlatformImages[glyph] else {
        throw CharacterReferenceResourceError.unavailable(glyph.rawValue)
      }
      return image
    }

    @available(iOS 16.0, *)
    static var unavailableGlyphs: [CharacterMouthGlyph] {
      CharacterMouthGlyph.allCases.filter { cachedPlatformImages[$0] == nil }
    }
  #endif
}
