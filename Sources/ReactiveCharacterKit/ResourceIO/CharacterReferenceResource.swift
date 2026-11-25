import Foundation

#if os(iOS) || os(macOS)
  import SwiftUI
  #if os(iOS)
    import UIKit
    typealias CharacterPlatformImage = UIImage
  #else
    import AppKit
    typealias CharacterPlatformImage = NSImage
  #endif

  enum CharacterReferenceResourceError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    var description: String {
      switch self { case .unavailable(let name): "Unavailable character image: \(name)" }
    }
  }

  /// Platform image I/O only. Pose, scene construction and geometry are shared unchanged.
  enum CharacterPlatformImageLoader {
    static func resolve(_ image: CharacterSceneImage) -> (image: Image, size: CGSize)? {
      if let walk = image.feltWalk {
        return CharacterFeltWalkRenderer.image(walk).map(canvasImage)
      }
      let asset = image.asset
      if asset.source == .package, CharacterFeltCatRigRenderer.isGenerated(asset.name) {
        return CharacterFeltCatRigRenderer.image(named: asset.name).map(canvasImage)
      }
      return named(asset).map { ($0.characterSwiftUIImage, $0.size) }
    }

    static func contains(_ image: CharacterSceneImage) -> Bool {
      if let walk = image.feltWalk { return CharacterFeltWalkRenderer.hasSource(walk) }
      let asset = image.asset
      if asset.source == .package, CharacterFeltCatRigRenderer.isGenerated(asset.name) {
        return CharacterFeltCatRigRenderer.hasSource(named: asset.name)
      }
      return named(asset) != nil
    }

    static func load(url: URL?, name: String) throws -> CharacterPlatformImage {
      guard let url, let image = CharacterPlatformImage(contentsOfFile: url.path) else {
        throw CharacterReferenceResourceError.unavailable(name)
      }
      return image
    }
    static func named(_ asset: CharacterImageAsset) -> CharacterPlatformImage? {
      let bundle: Bundle = asset.source == .package ? .module : .main
      #if os(iOS)
        return UIImage(named: asset.name, in: bundle, compatibleWith: nil)
      #else
        return bundle.image(forResource: NSImage.Name(asset.name))
      #endif
    }

    private static func canvasImage(_ image: CGImage) -> (image: Image, size: CGSize) {
      // Generated frames already own their pixels and do not need a platform image wrapper.
      (Image(decorative: image, scale: 1), CGSize(width: image.width, height: image.height))
    }
  }
  extension CharacterPlatformImage {
    var characterSwiftUIImage: Image {
      #if os(iOS)
        Image(uiImage: self)
      #else
        Image(nsImage: self)
      #endif
    }
  }
#endif
